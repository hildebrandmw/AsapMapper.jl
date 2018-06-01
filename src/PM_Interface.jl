################################################################################
# Project Manager Datafile
################################################################################

"""
    Project Manager File Constructor

This controls dispatch to the constructor for the taskgraph and options parser.

The constructor will attach the following pieces of metadata to the constructed
taskgraph.

# Nodes

## Direct metadata - retrieved from Project Manager.
* `"type"` - The task type of this task given by the Project Manager.
    Preserves captalization and punctuation.

    Expected types: `String`

## Computed metadata - used for internal computation.
* `"mapper_type"` - Mapper specific type for this task. Generally, there
    will be a 1-to-1 mapping between Mapper types and Project Manager types,
    except that Mapper types will all lower case.

    Exceptions: Memories will be converted to either "memory_1port" or
    "memory_2port" depending on the number of neighbors they have. This ensures
    that memory tasks needing 2 ports will not be mapped to a single ported
    memory on Asap 4.

    Expected types: `String`

# Edges

## Direct metadata - retrieved from Project Manager
* `"source_task"` - The name of the source task for this edge.
    Expected types: `String`

* `"source_index"` - The original index in the Project Manager's datastructure
    where this edge originated. Used to disambiguate between multiple links
    and allows the Project Manager to reconstruct routings.

    Expected types: `String, Int`

* `"dest_task"` - The name of the destination task. Expected types: `String`.

* `"dest_index"` - Same as `source_index` except for destination.

* `"measurements_dict"` - Dictionary containing measurements. This is optional
    and will be marked as `missing` if not present.

* `"pm_class"` - The class of this link given by the Project Manager.

## Computed metadata
* `"mapper_class"` - The mapper equivalend of the given `pm_class`. Right now,
    it is just the lowercase version of `pm_class`.

* `"cost"` - Mapper assigned cost to the link. Currently, only assigns a higher
    weight to memory links.

* `"preserve_dest"` - Preserve the destination index. This keeps the mapper from
    swapping out destination fifos.
"""
struct PMConstructor <: MapConstructor
    file    ::String
    options ::Dict{Symbol,Any}

    #--inner constructor
    function PMConstructor(file::String, options = Dict{Symbol,Any}())
        # Iterate through each opion in "kwargs" - ensure it is in the list of
        # options provided by "_defult_options_"
        default_options = _get_default_options()
        for key in keys(options)
            if !haskey(default_options, key)
                error("Unrecognized Mapper Override option $(key).")
            end
        end
        return new(file, options)
    end
end

# Central list of options that are expected from the project manager input
# file or are to be over-ridden by local options.
function _get_default_options()
    return Dict(
        # General Options
        # ---------------
        :verbosity => "info",

        # Architecture Generation
        # -----------------------

        # Default to nothing. If this is not set in the input file, a run
        # time error will be generated somewhere.
        :architecture => nothing,

        # Default the number of links to 2 to match Asap3/4 architectures.
        # Invalid if:
        #   - typeof(architecture) <: FunctionCall
        :num_links => 2,

        # Mapping Options
        # ---------------
        # Number of times to retry place and route if congested.
        :num_retries => 3,

        # Set to true to use packet links during placement.
        :use_packet_links => false,

        # Set to "true" to assign weights to inter-task communication links
        # according to the normalized number of writes on that link.
        :use_profiled_links => false,

        # Set to "true" to include frequency as a criteria for mapping.
        :use_task_suitability => false,

        # Penalty term applied to missing a rank requirement.
        :task_rank_penalty_start    => 64.0,

        # Set which entry in the "Measurements Dict" is to be used to select
        # the metric for rank.
        :task_rank_key              => "Rank",

        # Choose method of normailzation. 
        :absolute_rank_normalization => true,

        # Method for loading an existing file.
        :existing_map => nothing,
      )
end

function Base.parse(c::PMConstructor)
    json_dict = open(c.file, "r") do f
        JSON.parse(f)
    end
    # Parse options from the project manager.
    final_options = parse_options(c.options, json_dict["mapper_options"])
    json_dict["mapper_options"] = final_options
    @debug """
        Final Options Dict:
        $final_options
    """
    return json_dict
end

"""
    parse_options(internal::Dict, external::Dict)

Parse the options passed internally and externally. Prune all external options
that are not in the `default_options` dict and return a final options
dictionary with the following option precedences from highest to lowest:

`internal`, `external`, `default`.
"""
function parse_options(internal::Dict{Symbol,Any}, external::Dict{String,Any})
    # Convert the keys of 'external' to symbols for uniformity.
    external_sym = Dict(Symbol(k) => v for (k,v) in external)

    default_options = _get_default_options()

    # Generally, we don't know what could come in the externally parsed options
    # dictionary. Filter out unrecognized symbols to make sure that we only
    # have options that are implemented in AsapMapper.
    #
    # Delete all other keys.
    keys_to_delete = Symbol[]

    for key in keys(external_sym)
        if !haskey(default_options,key)
            @warn "Unrecognized Mapper option: $key."
            push!(keys_to_delete, key)
        end
    end
    for key in keys_to_delete
        delete!(external_sym, key)
    end

    # Merge all results together. Use the precedence in the `merge` operation to
    # get this correct.
    final_dict = merge(default_options, external_sym, internal)

    # Do any global actions with side-effects here.
    parse_verbosity(final_dict[:verbosity])

    return final_dict
end

function parse_verbosity(verbosity)
    # Just redirect to "set_logging"
    if verbosity in ("debug", "info", "warn", "error")
        set_logging(Symbol(verbosity))
    else
        @warn "Unknown Verbosity option: $verbosity"
        set_logging(:info)
    end
end

################################################################################
# build_map - Top level function for creating Map objects from the Project
#   Manager.
################################################################################
function build_map(c::PMConstructor)
    # Parse the input json file
    json_dict = parse(c)
    a = build_architecture(c, json_dict)
    t = build_taskgraph(c, json_dict)

    # Run Architecture transforms.
    name_mappables(a, json_dict)
    compute_ranks(a, json_dict)

    # build the map and attach the options dictionary to it.
    m = NewMap(a,t)
    options = json_dict[_options_path_]
    m.options = options

    # if options[:use_task_suitability] && options[:use_quartile_normalization]
    #     quartile_normalize_processors(m)
    # end

    # Load an existing map if provided with one.
    if typeof(options[:existing_map]) <: String
        Mapper2.MapperCore.load(m, options[:existing_map])
    end


    # Print out the important operations for information/debugging purposes.
    task_rank_key = options[:use_task_suitability] ? options[:task_rank_key] : ""
    @info """
    Mapper Options Summary
    ----------------------

    Using Link Weights: $(options[:use_profiled_links])

    Using Task Suitability: $(options[:use_task_suitability])

    Task Rank Key: $task_rank_key

    Existing Map: $(options[:existing_map])
    """

    return m
end

mutable struct AuxStorage{T}
    # Value to multiply the ratio of task rank to core rank. Helps emphasize
    # communication energy versus task suitability.
    task_penalty_multiplier ::Float64

    # NOTE: Currently unused.
    # Value to multiply the link costs.
    link_penalty_multiplier ::Float64

    # Store the task rank to core rank ratios inside a mutable binary maxheap
    # from DataStructures. When moving a task, reference its entry in the 
    # handles vector to change its ratio.
    ratio_max_heap::T
end

AuxStorage(x, heap) = AuxStorage(Float64(x), 0.0, heap)


function asap_pnr(m::Map{A,D}) where {A,D}
    println("Map type: ", A)
    if m.options[:use_task_suitability]
        # Allocate the max_heap to store ratio information and the handles vector.
        maxheap = DataStructures.mutable_binary_maxheap(Float64)

        # Add metadata pointing to the handle to each node.
        for task in getnodes(m.taskgraph)
            # Initialize all ranks to 0.0. These will all be updated correctly
            # when the nodes first get moved.
            handle = push!(maxheap, 0.0)

            # Going to store the handles for each entry in the heap in the 
            # metadata. WHen the "RankedNode" get generated, we will look up
            # the handle in the metadata and attach it to the node.
            task.metadata["heap_handle"] = handle
        end


        aux = AuxStorage(m.options[:task_rank_penalty_start], maxheap)
        while true
            m = place(m, enable_address = true, aux = aux)
            success = true
            # Sometimes, routing will fail if memory processors are not located
            # next to their respective memories. This try-catch block makes sure
            # the whole routine doesn't break if this happens.
            try
                m = route(m)
            catch
                success = false
            end
            if success && check_routing(m; quiet = true)
                break
            else
                aux.task_penalty_multiplier /= 2
                @info "Routing Failed. Trying aux = $(aux.task_penalty_multiplier)"
            end
        end
    else
        for i in 1:m.options[:num_retries]
            try
                place(m)
                route(m)
                check_routing(m; quiet = true) && break
            catch err
                @error "Received routing error: $err. Trying again."
            end
        end
    end

    # for debug purposes
    # save the mapping.
    #path = augment(".", "mapper_out.jls")
    #println("Saving to $path")
    #Mapper2.MapperCore.save(m, path)

    return m
end

#-------------------------------------------------------------------------------
# Methods for building the architecture

# Location in the input dictionary where the architecture specification
# can be found.
const _options_path_ = KeyChain(("mapper_options",))

# Dispatch function.
function build_architecture(c::PMConstructor, json_dict)
    # Get the architecture from the options dictionary.
    options = json_dict[_options_path_]
    arch = options[:architecture]

    # If a custom FunctionCall is passed - use that as an architecture
    # constructor. Otherwise, parse through the passed string to decode the
    # architecture.
    if typeof(arch) <: FunctionCall
        @debug "Dispatching Custom Architecture: $(arch)"
        return call(arch)
    end

    num_links             = options[:num_links]
    use_profiled_links    = options[:use_profiled_links]
    use_task_suitability  = options[:use_task_suitability]

    kc_type = KC{true,use_task_suitability}
    @debug "Use KC Type: $kc_type"

    # Perform manual dispatch based on the string.
    if arch == "Array_Asap3"
        return asap3(num_links, kc_type)
    elseif arch == "Array_Asap4"
        return asap4(num_links, kc_type)
    else
        error("Unrecognized Architecture: $arch_string")
    end
end
#-------------------------------------------------------------------------------

const _pm_task_fields = ("type", "measurements_dict",)
const _pm_edge_required = ("source_task","source_port","dest_task","dest_port")
const _pm_edge_optional = ("measurements_dict",)

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
                                  assign_ranks,
                                 )

function parse_input(t::Taskgraph, tasklist, options)
    # Check if packet_links will be included in the netlist.
    use_packet_links = options[:use_packet_links]

    # One iteration to collect all of the task nodes.
    for task in tasklist
        name = task["name"]
        metadata = getkeys(task, _pm_task_fields)
        add_node(t, TaskgraphNode(name, metadata))
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
                route_link = !(link_class == "Packet_Link")

                # Merge in the metadata
                basic_metadata = Dict{String,Any}(
                      "pm_class"        => link_class,
                      "source_task"     => source_task,
                      "source_index"    => source_index,
                      "dest_task"       => dest_task,
                      "dest_index"      => dest_index,
                      "route_link"      => route_link,
                     )

                measurements = Dict("measurements_dict" => link_def["measurements_dict"])

                metadata = merge(basic_metadata, measurements)
                new_edge = TaskgraphEdge(source_task, dest_task, metadata)
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

function assign_ranks(t::Taskgraph, options::Dict)
    # Early Abort
    options[:use_task_suitability] || (return t)
    # Get callback for frequency assignment.
    # Can choose to either use data encoded directly in the taskgraph or to
    # generate synthetic data.
    read_task_ranks(t, options)
    #options[:task_rank_source](t, options)
    # Use the selected binning function to bin frequencies.
    normalize_ranks(t, options)
    #options[:task_rank_normalize](t, options)

    return t
end

function read_task_ranks(t::Taskgraph, options::Dict)
    rank_key        = options[:task_rank_key]

    # Iterate through all nodes. Create an empty "TaskRank" type and attach
    # it to the metadata for each node.
    for task in getnodes(t)
        measurements = task.metadata["measurements_dict"]

        # Get the specified rank from the measurements dictionary
        # Set them to "missing" if not provided.
        #
        # This will be taken care of
        # when they are normalized in a later processing step.
        rank        = get(measurements, rank_key, missing)

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
    # Do this by iterating through all ranks to find the minimum and maximum
    # rank value.
    #
    # If a given rank is missing, assume it is important.
    rank_min = typemax(Float64)
    rank_max = typemin(Float64)

    for taskrank in taskranks
        # unpack raw ranks
        rank = taskrank.rank
        if !ismissing(rank)
            rank_min = min(rank, rank_min)
            rank_max = max(rank, rank_max)
        end
    end

    # Assign all tasks a maximum normalized rank if rank_min == rank_max.
    maximize_all_ranks = rank_max == rank_min

    @debug """
    Rank Max: $rank_max

    Rank Min: $rank_min
    """

    num_digits = 6
    min_val = 2.0 ^ (-num_digits)

    ranks = Float64[]

    for task in getnodes(t)
        taskrank = getrank(task)

        # Normalize to the range 0 to 1
        rank = taskrank.rank
        if isnonranking(task)
            taskrank.normalized_rank = 0.0
        elseif ismissing(rank) || maximize_all_ranks
            taskrank.normalized_rank = 1.0
        elseif absolute_normalize
            taskrank.normalized_rank = max(
                ceil(rank / rank_max, num_digits, 2),
                min_val,
               )
        else
            taskrank.normalized_rank = max(
               ceil( (rank - rank_min) / (rank_max - rank_min), num_digits, 2),
               min_val
              )
        end

        push!(ranks, taskrank.normalized_rank)#
    end

    @debug "$ranks"
    @debug "$(maximum(ranks))"
end

# Don't rank input or output nodes.
isnonranking(t) = isinput(t) || isoutput(t)

################################################################################
# Architecture operations
################################################################################

function Base.ismatch(c::Component, pm_base_type)
    haskey(c.metadata, typekey()) || (return false)
    # Check the two implemented mapper attributes for processors
    if pm_base_type == "Processor_Core"
        return isproc(c)
    # generalize to n-ported memory using regex.
    elseif pm_base_type == "Memory_Core"
        return ismemory(c)
    # input/output handlers done by direct look-up
    elseif pm_base_type == "Input_Handler_Core"
        return isinput(c)
    elseif pm_base_type == "Output_Handler_Core"
        return isoutput(c)
    end

    return false
end

"""
    name_mappables(a::TopLevel, json_dict)

Find the project-manager names for components in the architecture and assign
their metadata accordingly.
"""
function name_mappables(a::TopLevel, json_dict)
    for core in json_dict["array_cores"]
        # Get the address for the core
        addr = CartesianIndex(core["address"]...)
        base_type = core["base_type"]

        # Spit out a warning is the address is not in the model.
        if !haskey(a.address_to_child, addr)
            @warn "No address $addr found for core $(core["name"])."
            continue
        end

        parent = getchild(a, addr)
        for path in walk_children(parent)
            component = parent[path]
            # Try to match the base_type of the Project_Manager core with
            # its type in the Mapper's model.
            #
            # This will break if multiple cores of the same type exist in the
            # same tile.
            if ismatch(component, base_type)
                # Set the metadata for this component and exit
                component.metadata["pm_name"] = core["name"]
                component.metadata["pm_type"] = core["type"]

                rank = get(core,"max_frequency",missing)
                setrank!(component, CoreRank(rank))
                break
            end
        end
    end
end

function compute_ranks(a::TopLevel, json_dict)
    options = json_dict[_options_path_]
    # Abort if 'use_task_suitability' is false
    options[:use_task_suitability] || (return)
    # Callback for synthetically assigning frequencies if needed.
    normalize_ranks(a, options)
end

function normalize_ranks(a::TopLevel, options)
    children = walk_children(a)

    nonranking_types = (MTypes.input, MTypes.output)
    ranking_types = (MTypes.proc, MTypes.memory(1), MTypes.memory(2))

    # First, handle input/output handlers
    # Set all of their ranks to 1.0 because right now, we aren't ranking input
    # or output handlers.
    types = (MTypes.input, MTypes.output)
    g(x) = search_metadata(a[x], typekey(), nonranking_types, oneofin)
    iopaths = filter(g, children)

    for path in iopaths
        getrank(a[path]).normalized_rank = 1.0
    end

    # Now handle processors and memories
    f(x) = search_metadata(a[x], typekey(), ranking_types, oneofin)
    paths = filter(f, walk_children(a))

    coreranks = [getrank(a[path]) for path in paths]

    rank_min = typemax(Float64)
    rank_max = typemin(Float64)
    for corerank in coreranks
        rank = corerank.rank
        if !ismissing(rank)
            rank_min = min(rank_min, rank)
            rank_max = max(rank_max, rank)
        end
    end

    #absolute_normalize = options[:absolute_rank_normalization]
    absolute_normalize = true

    rank_range = (rank_max - rank_min)

    @debug """
    Rank Max: $rank_max

    Rank Min: $rank_min
    """


    # If range is zero - all cores have the same frequency.
    minimize_all_ranks = iszero(rank_range)
    num_digits = 6

    # Must make sure that no core has a rank of zero, otherwise ratios of task
    # rank to core rank can be infinity, which is not very useful.
    minval = 2.0 ^ (-num_digits)

    ranks = Float64[]
    for path in paths
        corerank = getrank(a[path])

        rank = corerank.rank
        if minimize_all_ranks
            corerank.normalized_rank = minval
        elseif absolute_normalize
            corerank.normalized_rank = max(
                   round( rank / rank_max, num_digits, 2),
                   minval
                )
        else
            corerank.normalized_rank = max(
                round( (rank - rank_min) / rank_range, num_digits, 2),
                minval
               )
        end

        push!(ranks, corerank.normalized_rank)
    end

    @debug "$ranks"
end
