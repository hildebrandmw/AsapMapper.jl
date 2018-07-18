const _pm_task_fields = ("type", "measurements_dict",)

const _index_types = Union{Int64,String}
const _name_types  = String

const _accepted_task_types = (
    "Input_Handler",
    "Output_Handler",
    "Processor",
    "Memory",
)

build_taskgraph(c::MapConstructor) = build_taskgraph(c, parse(c))
function build_taskgraph(c::MapConstructor, json_dict::Dict)
    t = Taskgraph()
    options = json_dict[_options_path_]
    parse_input(t, json_dict["task_structure"], options)


    # post-processing routines
    for op in taskgraph_ops(c)
        @debug "Running Taskgraph Trasnform $op"
        t = op(t, options)
    end
    return t
end

taskgraph_ops(::PMConstructor) = (
                                  transform_task_types,
                                  compute_edge_metadata,
                                  apply_link_weights,
                                  experimental_transforms,
                                 )

function parse_input(t::Taskgraph, tasklist, options)
    # Check if packet_links will be included in the netlist.
    use_packet_links = options[:use_packet_links]

    # One iteration to collect all of the task nodes.
    for task in tasklist
        name = task["name"]
        metadata = getkeys(task, _pm_task_fields)
        add_node(t, TaskgraphNode(name, metadata = metadata))
    end

    # Iterate through again, collect and add all edges. Each edge can be
    # uniquely represented as a tuple
    # (link_class, source_task, source_index, dest_task, dest_index).
    #
    # Keep track of these tuples to avoid adding redundant links.
    seen_tuples = Set()
    packet_warn = true
    for task in tasklist
        # leaf_node_dict should be a dict of dicts. Where:
        # - keys are link class ("Circuit_Link", "Packet_Link" etc)
        # - values eventually end up with the link tuple.
        leaf_node_dict = task["leaf_node_dict"]
        for (link_class, link_dict) in leaf_node_dict
            if !use_packet_links && link_class == "Packet_Link"
                continue
            end
            # Deep dictionary walking ...
            for io_decl in values(link_dict), link_def in values(io_decl)
                # Extract the link tuple fields.
                source_task  = type_sanitize(_name_types,link_def["source_task"])
                source_index = type_sanitize(_index_types, link_def["source_index"])
                dest_task    = type_sanitize(_name_types,link_def["dest_task"])
                dest_index   = type_sanitize(_index_types, link_def["dest_index"])
                # Construct and check link tuple
                link_tuple = (link_class, source_task, source_index, dest_task, dest_index)
                in(link_tuple, seen_tuples) && continue
                push!(seen_tuples, link_tuple)

                # Determine whether or not this link should be routed.
                # Right now, only Packet Links are not supposed to be routed.
                # TODO: Fix this.
                route_link = !(link_class == "Packet_Link")

                # Create metadata for this link.
                metadata = Dict{String,Any}(
                      "pm_class"            => link_class,
                      "source_task"         => source_task,
                      "source_index"        => source_index,
                      "dest_task"           => dest_task,
                      "dest_index"          => dest_index,
                      "route_link"          => route_link,
                      "measurements_dict"   => link_def["measurements_dict"],
                     )

                new_edge = TaskgraphEdge(source_task, dest_task, metadata = metadata)
                add_edge(t, new_edge)
            end
        end
    end
    @info """
    Taskgraph Constructed.

    Number of Tasks: $(num_nodes(t))

    Number of Links: $(num_edges(t))
    """
end

#-------------------------------------------------------------------------------
# Project manager taskgraph transforms.
#-------------------------------------------------------------------------------
function compute_edge_metadata(t::Taskgraph, options::Dict)
    for edge in getedges(t)
        edge.metadata["link_class"] = lowercase(edge.metadata["pm_class"])
        # Preserve the destination fifo if the edge is a circuit link and it
        # does not end at an output handler.
        if edge.metadata["pm_class"] == "Circuit_Link"
            neighbor = getsinks(edge)
            @assert length(neighbor) == 1

            neighbor_node = getnode(t, first(neighbor))

            # I came across an edge case when doing so mappings for ASAP2 with
            # the output mux. For Asap3/4, there is only one output port, so
            # setting "preserve_dest" has no affect. But for Asap2, it's nice
            # to not have this set to the router can use any of the output
            # ports.
            if isoutput(neighbor_node)
                edge.metadata["preserve_dest"] = false
            else
                edge.metadata["preserve_dest"] = true
            end
        else
            edge.metadata["preserve_dest"] = false
        end
    end
    return t
end


"""
    transform_task_types(t::Taskgraph, options::Dict)

Transform the Project Manager Task Types to the task type used internally by
the Mapper.
"""
function transform_task_types(t::Taskgraph, options::Dict)
    memory_neighbors = String[]
    for task in getnodes(t)
        # Get the project manager class
        task_type = task.metadata["type"]

        # Brute-force decoding.
        if task_type == "Input_Handler"
            make_input!(task)
        elseif task_type == "Output_Handler"
            make_output!(task)
        elseif task_type == "Processor"
            make_proc!(task)
        elseif task_type == "Memory"
            # join the input and output to determine if 1 port or 2
            neighbors = union(innode_names(t, task.name), outnode_names(t, task.name))
            num_neighbors = length(unique(neighbors))

            if num_neighbors in (1,2)
                make_memory!(task, num_neighbors)
            else
                error("""
                    Expected memory $(task.name) to have 1 or 2 neighbors.
                    Found $num_neighbors.
                    """)
            end
            append!(memory_neighbors, neighbors)
        end
    end

    # Give "memory_processor" attributes to all neighbors of memory processors.
    for name in unique(memory_neighbors)
        task = getnode(t, name)
        if !isproc(task) && !ismemoryproc(task)
            error("Expected neighbors of memories to have type \"processor\".")
        end
        make_memoryproc!(task)
    end
    return t
end

function apply_link_weights(t::Taskgraph, options::Dict)
    # Number of binary digits to round the weights to. Making this number too
    # larger results in some links being ignored entirely, which is pretty bad
    # for routing purposes. Setting it to 3 seems to hit a sweet spot.
    ndigits = 3

    # Set a minimum linke weight to ensure that no link gets assigned a weight
    # of 0. This causes problems for both routing and placement.
    minimum_link_weight = 2.0 ^ (-ndigits)

    # Weight to assign memory links.
    memory_link_weight = 5.0

    # Need to still apply weight in order to get memory modules to work correctly.
    # Just assigns unit weights to each non-memory link and a weight of 5.0
    # to each memory link.
    use_profiled_links = options[:use_profiled_links]

    # Determine the maximium and minimum number of writes over the entire
    # colletion of edges. Do this in a single pass through the input
    # dictionary as this will work correctly even if the "num_writes" field
    # of the measurements dict is not available.
    min_writes = typemax(Int64)
    max_writes = typemin(Int64)
    for edge in getedges(t)
        measurements = edge.metadata["measurements_dict"]
        source_task = getnode(t, first(getsources(edge)))
        if haskey(measurements, "num_writes")
            num_writes = measurements["num_writes"]
            # Keep track of minimum and maximum number of writes.
            min_writes = min(min_writes, num_writes)
            max_writes = max(max_writes, num_writes)
        end
    end

    range = max_writes - min_writes

    @debug """
        Min Writes: $min_writes
        Max Writes: $max_writes
        Minimum link weight: $minimum_link_weight
    """

    # Assign weight to each edge based on the number of writes compared with
    # the average.
    for edge in getedges(t)
        measurements = edge.metadata["measurements_dict"]
        source_task = getnode(t, first(getsources(edge)))
        dest_task   = getnode(t, first(getsinks(edge)))

        # Since memory processors must be located directly next to their
        # respective memories, assign a high cost to memory links.
        if edge.metadata["pm_class"] in ("Memory_Request_Link", "Memory_Response_Link")
                edge.metadata["cost"] = memory_link_weight

        # Default value if per-link weight is not being used, or if for some
        # reason measurements associated with a link are missing.
        elseif !use_profiled_links || !haskey(measurements, "num_writes")
            edge.metadata["cost"] = 1.0

        # By default, scale the weight of a link with the number of writes
        # on the link. Scale between the minimum and maximum number of writes
        # so the weight is between "minimum_link_weight" and 1.0
        else
            num_writes = measurements["num_writes"]
            scaled_cost = (num_writes - min_writes) / range
            cost = max(
                       ceil(scaled_cost, ndigits, 2),
                       minimum_link_weight
                      )

            edge.metadata["cost"] = cost
        end
    end
    return t
end

# Special, experimental transforms to turn on and off.
function experimental_transforms(t::Taskgraph, options::Dict)
    use_task_suitability = options[:use_task_suitability]
    use_heterogenous_mapping = options[:use_heterogenous_mapping]
    # Get callback for frequency assignment.
    # Can choose to either use data encoded directly in the taskgraph or to
    # generate synthetic data.
    if use_task_suitability
        read_task_ranks(t, options)
        normalize_ranks(t, options)
    elseif use_heterogenous_mapping
        assign_heterogenous_data(t, options)
    end

    return t
end

function assign_heterogenous_data(t::Taskgraph, options::Dict)
    key = options[:task_rank_key]
    # Iterate through each node in the taskgraph. If the node's metric rank
    # is above the threshold, or if the node is a memory neighbor, assign it
    # as high-performance.
    #
    # Only apply to processor types - leave all other types alone.

    # Counters for debugging
    num_high_performance = 0
    num_low_power = 0

    for node in getnodes(t)
        haskey(node.metadata["measurements_dict"], "specialization") || continue

        specialization = node.metadata["measurements_dict"]["specialization"]
        if ismemoryproc(node)
            make_highperformance(node)
            num_high_performance += 1

        elseif isproc(node)
            if specialization == "high_performance"
                make_highperformance(node)
                num_high_performance += 1

            elseif specialization == "low_power"
                make_lowpower(node)
                num_low_power += 1
            else
                throw(KeyError(specialization))
            end
        end
    end

    @debug """
    Number of high-performance tasks: $num_high_performance

    Number of low-power tasks: $num_low_power
    """
end

function read_task_ranks(t::Taskgraph, options::Dict)
    rank_key = options[:task_rank_key]

    # Iterate through all nodes. Create an empty "TaskRank" type and attach
    # it to the metadata for each node.
    for task in getnodes(t)
        measurements = task.metadata["measurements_dict"]

        # Get the specified rank from the measurements dictionary
        # Set them to "missing" if not provided.
        #
        # This will be taken care of
        # when they are normalized in a later processing step.
        rank = get(measurements, rank_key, missing)

        taskrank = TaskRank(rank)
        setrank!(task, taskrank)
    end
end

################################################################################
function normalize_ranks(t::Taskgraph, options::Dict)
    @debug "Normalizing Ranks"

    #absolute_normalize = options[:absolute_rank_normalization]
    absolute_normalize = true

    # Gather all of the rank types from the tasks.
    taskranks = [getrank(task) for task in getnodes(t) if !isnonranking(task)]

    # Want to scale the rank portions between 0 and 1, where a higher rank
    # indicates it is more important.
    #
    # Do this by iterating through all ranks to find the maximum rank value. 
    rank_max::Float64 = typemin(Float64)

    for taskrank in taskranks
        # unpack raw ranks
        rank = taskrank.rank

        # Skip missing values to keep rank_min and rank_max floats.
        if !ismissing(rank)
            rank_max = max(rank, rank_max)
        end
    end

    @debug "Maximum rank: $rank_max"

    num_digits = 6
    min_val = 2.0 ^ (-num_digits)

    ranks = Float64[]

    # Normalize task ranks between 0 and 1
    for task in getnodes(t)
        taskrank = getrank(task)
        rank = taskrank.rank

        # Deprioritize tasks that don't matter. This includes input handlers
        # and output handlers.
        if isnonranking(task)
            taskrank.normalized_rank = 0.0

        # If a task has not been assigned a rank, assume it is important and 
        # give it a normalized rank of 1.0
        elseif ismissing(rank)
            taskrank.normalized_rank = 1.0

        # Default case: Scale this task's rank using the max rank.
        # Assign a minimum value to ensure that processor at least has some
        # rank.
        else 
            taskrank.normalized_rank = max(
                ceil(rank / rank_max, num_digits, 2),
                min_val,
            )
        end

        # For debugging.
        push!(ranks, taskrank.normalized_rank)
    end

    @debug "$ranks"
    @debug "$(maximum(ranks))"
end
