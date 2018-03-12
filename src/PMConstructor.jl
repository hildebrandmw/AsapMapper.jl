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
    arch::String
    file::String
end

function Base.parse(c::PMConstructor)
    f = open(c.file, "r")
    jsn = JSON.parse(f)
    close(f)
    return jsn
end

function build_map(c::PMConstructor)
    # set "make_copies" argument to "true" - assignign proc-specific metadata
    if c.arch == "asap4"
        a = asap4(2, KCStandard, true)
    elseif c.arch == "asap3"
        a = asap3(2, KCStandard, true)
    else
        KeyError("Architecture $architecture not implemented.")
    end
    # Parse the input json file
    json_dict = parse(c)     
    # Build taskgraph
    t = build_taskgraph(c, json_dict)
    # Run operations on the architecture according.
    name_mappables(a, json_dict)

    return NewMap(a, t)
end

const _pm_task_required = ("type",)
const _pm_task_optional = ()
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

function build_taskgraph(c::MapConstructor, json_dict::Dict)
    t = Taskgraph()
    parse_input(t, json_dict["task_structure"])

    # post-processing routines
    for op in taskgraph_ops(c)
        t = op(t)
    end
    return t
end

taskgraph_ops(::PMConstructor) = (transform_task_types,
                                  compute_edge_metadata,
                                  apply_link_weights,
                                 )

function parse_input(t::Taskgraph, tasklist)
    # One iteration to collect all of the task nodes.
    for task in tasklist
        name = task["name"]
        required_metadata = getkeys(task, _pm_task_required)
        optional_metadata = getkeys(task, _pm_task_optional, false)
        metadata = merge(required_metadata, optional_metadata)
        add_node(t, TaskgraphNode(name, metadata))
    end

    # Iterate through again, collect and add all edges. Each edge can be
    # uniquely represented as a tuple
    # (source_task, source_index, dest_task, dest_index).
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
            # Abort packet links
            if link_class == "Packet_Link"
                if packet_warn
                    @warn "Ignoring Packet Links"
                    packet_warn = false
                end
                continue
            end
            # Deep dictionary walking ...
            for io_declarations in values(link_dict)
                isempty(io_declarations) && continue
                for link_def in values(io_declarations)
                    # Extract the link tuple fields.
                    source_task  = type_sanitize(_name_types,link_def["source_task"])
                    source_index = type_sanitize(_index_types, link_def["source_index"])
                    dest_task    = type_sanitize(_name_types,link_def["dest_task"])
                    dest_index   = type_sanitize(_index_types, link_def["dest_index"])
                    # Construct and check link tuple
                    link_tuple = (source_task, source_index, dest_task, dest_index)
                    in(link_tuple, seen_tuples) && continue
                    push!(seen_tuples, link_tuple)

                    preserve_dest = (link_class == "Circuit_Link")

                    # Merge in the metadata
                    basic_metadata = Dict{String,Any}(
                          "pm_class"        => link_class,
                          "source_task"     => source_task,
                          "source_index"    => source_index,
                          "dest_task"       => dest_task,
                          "dest_index"      => dest_index,
                         )

                    metadata = merge(basic_metadata, link_def["measurements_dict"])
                    new_edge = TaskgraphEdge(source_task, dest_task, metadata)
                    add_edge(t, new_edge)
                end
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
function compute_edge_metadata(t::Taskgraph)
    for edge in getedges(t)
        edge.metadata["link_class"] = lowercase(edge.metadata["pm_class"])
        edge.metadata["preserve_dest"] = (edge.metadata["pm_class"] == "Circuit_Link")
    end
    return t
end


"""
    transform_task_types(t::Taskgraph)

Transform the Project Manager Task Types to the task type used internally by
the Mapper.
"""
function transform_task_types(t::Taskgraph)
    direct_task_dict = Dict(
        "Input_Handler"     => "input_handler",
        "Output_Handler"    => "output_handler",
        "Processor"         => "processor",
    )
    memory_neighbors = String[]
    for task in getnodes(t)
        # Get the project manager class
        task_type = task.metadata["type"]
        if haskey(direct_task_dict, task_type)
            task.metadata["mapper_type"] = direct_task_dict[task_type]
        elseif task_type == "Memory"
            # join the input and output to determine if 1 port or 2
            neighbors = vcat(in_node_names(t, task.name), 
                             out_node_names(t, task.name))
            num_neighbors = length(unique(neighbors))

            if num_neighbors == 1
                task.metadata["mapper_type"] = "memory_1port"
            elseif num_neighbors == 2
                task.metadata["mapper_type"] = "memory_2port"
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
        if !in(task.metadata["mapper_type"], ("processor","memory_processor"))
            error("Expected neighbors of memories to have type \"processor\".")
        end
        task.metadata["mapper_type"] = "memory_processor"
    end
    return t
end

function apply_link_weights(t::Taskgraph)
    for edge in getedges(t)
        if edge.metadata["pm_class"] in ("Memory_Request_Link", "Memory_Response_Link") 
            edge.metadata["cost"] = 5.0
        else
            edge.metadata["cost"] = 1.0
        end
    end
    return t
end

################################################################################
# Architecture operations
################################################################################

function Base.ismatch(c::Component, pm_base_type)
    haskey(c.metadata, "attributes") || (return false)
    # Check the two implemented mapper attributes for processors
    if pm_base_type == "Processor_Core"
        return "processor" in c.metadata["attributes"]
    # generalize to n-ported memory using regex.
    elseif pm_base_type == "Memory_Core"
        attr = c.metadata["attributes"]

        # search through each attribute in the array.
        for a in attr
            ismatch(r"^memory_\d+port$", a) && (return true)
        end
        return false
    # input/output handlers done by direct look-up
    elseif pm_base_type == "Input_Handler_Core"
        return "input_handler" in c.metadata["attributes"] 
    elseif pm_base_type == "Output_Handler_Core"
        return "output_handler" in c.metadata["attributes"] 
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
        # Get the address for the core - apply pm->mapper offset
        addr = CartesianIndex(core["address"]...) + CartesianIndex(2,2)
        base_type = core["base_type"]
        found_match = false
        if !haskey(a.children, addr)
            @warn "No address $addr found for core $(core["name"])."
            continue
        end
        parent = a.children[addr]
        for path in walk_children(parent)
            component = parent[path]
            if ismatch(component, base_type)
                # Set the metadata for this component and exit
                component.metadata["pm_name"] = core["name"]
                component.metadata["pm_type"] = core["type"]
                found_match = true
                break
            end
        end
    end
end
