abstract type TaskgraphConstructor end

function apply_transforms(tg, c::TaskgraphConstructor)
    @debug "Applying Transforms"
    # Get the transforms requested by the constructor.
    transforms = get_transforms(c)
    for t in transforms
        @debug "Transform: $t"
        tg = t(tg)::Taskgraph
    end
    return tg
end

get_transforms(::TaskgraphConstructor) = ()

"""
    getkeys(d::T, keys, required = true) where T <: Dict

Return a dictionary `r` of type `T` with just the requested keys and
corresponding values from `d`. If `required = true`, throw `KeyError` if a key
`k` is not found. Otherwise, set `r[k] = missing`.
"""
function getkeys(d::T, keys, required = true) where T <: Dict
    r = T()
    for k in keys
        if required && !haskey(d, k)
            throw(KeyError(k))
        end
        r[k] = get(d, k, missing)
    end
    return r
end

"""
    load_taskgraph(name)

Load the sim-dumpe taskgraph with the given name.
"""
function load_taskgraph(name)
    @info "Loading Taskgraph: $name"
    constructor = CompressedSimDump(name)
    return build_taskgraph(constructor)
end

################################################################################
# Project Manager Datafile
################################################################################
struct PMConstructor <: TaskgraphConstructor
    file::String
end

function Base.parse(c::PMConstructor)
    f = open(c.file, "r")
    jsn = JSON.parse(f)
    close(f)
    return jsn
end

const _pm_task_required = ("type",)
const _pm_task_optional = ()
const _pm_edge_required = ("source_task","source_port","dest_task","dest_port")
const _pm_edge_optional = ("measurements_dict",)

type_sanitize(::Type{T}, v::T) where T = v
function type_sanitize(::Type{T}, v::U) where {T,U}
    throw(TypeError(:type_sanitize, "Unexpected type for link definitions",T,U))
end

const _index_types = Union{Int64,String}
const _name_types  = String

const _accepted_task_types = (
        "Input_Handler",
        "Output_Handler",
        "Processor",
        "Memory",
       )

function build_taskgraph(c::TaskgraphConstructor)
    jsn = parse(c)

    t = Taskgraph()
    parse_input(t, jsn["task_structure"])
    apply_transforms(t,c)
    return t
end

get_transforms(c::PMConstructor) = (transform_task_types,
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

                    # Merge in the metadata
                    basic_metadata = Dict{String,Any}(
                          "class"           => link_class,
                          "source_index"    => source_index,
                          "dest_index"      => dest_index)

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
            task.metadata["required_attributes"] = direct_task_dict[task_type]
        elseif task_type == "Memory"
            # join the input and output to determine if 1 port or 2
            neighbors = vcat(in_node_names(t, task.name), 
                             out_node_names(t, task.name))
            num_neighbors = length(unique(neighbors))
            if num_neighbors == 1
                task.metadata["required_attributes"] = "memory_1port"
            elseif num_neighbors == 2
                task.metadata["required_attributes"] = "memory_2port"
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
        if task.metadata["required_attributes"] != "processor"
            error("Expected neighbors of memories to have type \"processor\".")
        end
        task.metadata["required_attributes"] = "memory_processor"
    end
    return t
end

function apply_link_weights(t::Taskgraph)
    for edge in getedges(t)
        if edge.metadata["class"] in ("Memory_Request_Link", "Memory_Response_Link") 
            edge.metadata["weight"] = 5.0
        else
            edge.metadata["weight"] = 1.0
        end
    end
    return t
end


################################################################################
# Taskgraph Constructors used by the Kilocore framework.
################################################################################
"""
    SimDump{C}

Construct a taskgraph from a `profile.json` file generated by the ASAP
simulator/project manager.

# Parameter:

* `C::Bool` - If `true`, source file is `.gz` compressed. Otherwise, it is a
    plain text file.
"""
struct SimDump{C} <: TaskgraphConstructor
    name::String
    file::String
end

# Fields for metadata attachment

const required_fields = Dict(
        :node => ["Get_Type_String()"],
        :edge => []
      )

const optional_fields = Dict(
        :node => ["output_buffers","attached_memory"],
        :edge => ["num_writes","destination_fifo","source_index"]
      )

# function get_fields(d::Dict, key::Symbol)
#     r = Dict{String,Any}()
#     # Get required fields
#     for field in required_fields[key]
#         if !haskey(d, field)
#             throw(KeyError(field))
#         end
#         r[field] = d[field]
#     end
#     # Get optional fields
#     for field in optional_fields[key]
#         r[field] = get(d, field, missing)
#     end
#     return r
# end

"""
    CompressedSimDump(appname::String)

Create a constructor for a taskgraph from a GZip compressed `profile.json`
generated by the Project Manager.

Argument `appname` will be split at the first `.` and the suffix `.json.gz` will
be attached.
"""
function CompressedSimDump(appname::String)
    name = split(appname, ".")[1]
    appname = "$name.json.gz"

    path = joinpath(PKGDIR, "sim-dumps", appname)
    return SimDump{true}(appname, path)
end

Base.open(c::SimDump{true}) = GZip.open(c.file, "r")
Base.open(c::SimDump{false}) = open(c.file, "r")

@doc """
    open(c::SimDump)

Open the file pointed to by `c`. Return the opened object.
"""


function build_taskgraph(c::SimDump)
    # Get the file from the sim-dump constructor and JSON parse the file.
    f = open(c)
    jsn = JSON.parse(f)::Dict{String,Any}
    close(f)
    # Construct taskgraph nodes from the name.
    nodes = [TaskgraphNode(k,get_fields(v,:node)) for (k,v) in jsn]
    # Iterate through the whole dictionary again to build up adjacency
    edges = build_edges(jsn)
    # Create the taskgraph
    name = first(split(c.name, "."))

    taskgraph = Taskgraph(name, nodes, edges)
    return apply_transforms(taskgraph, c)
end



"""
    build_edges(jsn::Dict)

Given a `jsn` dictionary from the `profile.json` input file, construct shell
`TaskgraphEdge` types with just source and sink information. Metadata extracted:

* `destination_fifo` - The index in the `input_buffers` field that this edge
    connects to.
* `num_writes` - If the `input_buffers` entry has a `num_writes` field, the
    value of this field is copied. Otherwise, a value of `missing` is given
    here.
* `source_index` - The index of `output_buffers` field where this link was
    taken from.
"""
function build_edges(jsn::Dict)
    # Two passes - one to populate all of the edges, the next to get source_index.
    edges = TaskgraphEdge[]
    for (taskname, data) in jsn
        haskey(data, "input_buffers") || continue
        for (fifo_index, buffer) in enumerate(data["input_buffers"])
            # skip empty entries.
            buffer == nothing && continue
            # extract required/optional metadata
            metadata = get_fields(buffer, :edge)
            # assign fifo-index. Subtract 1 for zero-indexing.
            metadata["destination_fifo"] = fifo_index - 1

            source = buffer["writer_core"]::String
            sink   = taskname
            newedge = TaskgraphEdge(source, sink, metadata)
            push!(edges, newedge)
        end
    end
    # ensure no duplicates - fallback in case one task has multiple links to
    # another task with the exact same number of writes.
    seen_edges = Set()
    for edge in edges
        source          = first(getsources(edge))
        source_dict     = jsn[source]
        expected_sink   = first(getsinks(edge))
        expected_writes = edge.metadata["num_writes"]

        for (index, buffer) in enumerate(source_dict["output_buffers"])
            buffer == nothing && continue
            sink = buffer["reader_core"]
            writes = get(buffer, "num_writes", missing)

            source_dict["Get_Type_String()"]

            if sink == expected_sink && writes == expected_writes
                key = (source,sink,edge.metadata["destination_fifo"],index)
                if !in(key, seen_edges)
                    edge.metadata["source_index"] = index
                    push!(seen_edges, key)
                end
            end
        end
    end
    return edges
end

################################################################################
# Custom Taskgraph Transforms.
################################################################################

"""
    get_transforms(sdc::SimDump)

Return the list of transforms needed by the `SimDump`.
"""
function get_transforms(sdc::SimDump)
    return (
        t_unpack_attached_memories,
        t_unpack_type_strings,
        t_confirm_and_sort_attributes,
        t_assign_link_weights,
    )
end



#=
################################################################################
Transforms needed to get Mapper2 to the state of Mapper1:

0. Assign attributes needed to each node based off the type string.
1. Unpack the "attached_memory" field if there is one.
2. Annotate the links with weights and distance limits.
    - Think about if it makes sense to break apart having just pure weights
        and adding distnace limits as one of the options that can be chosen
        by the top level Map data structure.
################################################################################
=#

"""
    t_unpack_attached_memories(tg::Taskgraph)

Iterates through all nodes in a taskgraph. If it finds a node with a metadata
field of "attached_memory", will create a new node for that attached memory and
a bidirectional link from the memory to the node.

Also removes the "attached_memory" field from the node so it should be safe to
run multiple times.
"""
function t_unpack_attached_memories(tg::Taskgraph)
    nodes_added = 0
    edges_added = 0
    # Record a set of unpacked memories so a memory that has a node in
    # the graph isn't accidentally added again.
    memories_unpacked = Set{String}()
    for node in getnodes(tg)
        # Check if this has the Get_Type_String() == memory property. If so,
        # we need to add an output link to its host processor.
        if get(node.metadata, "Get_Type_String()", "") == "memory"
            haskey(node.metadata, "output_buffers") || continue
            # Get all the input buffers, filter out all entries of "nothing"
            if haskey(node.metadata, "output_buffers")
                for (index,output_buffer) in enumerate(node.metadata["output_buffers"])
                    output_buffer == nothing && continue
                    # Create a link from the writer core to the current core
                    # referenced by "name". Use the whole buffer dict as metadata.
                    metadata = get_fields(output_buffer, :edge)
                    metadata["source_index"] = index
                    metadata["destination_fifo"] = "attached_memory"

                    source   = node.name
                    sink     = output_buffer["reader_core"]::String
                    add_edge(tg, TaskgraphEdge(source, sink, metadata))
                    edges_added += 1
                end
            end
        elseif !ismissing(node.metadata["attached_memory"])
            memory = node.metadata["attached_memory"]
            if !hasnode(tg, memory)
                error("Memory $memory is not defined in input file!")
            end
        end
    end
    @debug """
        Nodes added: $nodes_added
        Edges added: $edges_added
        """
    return tg
end


"""
    t_unpack_type_strings(tg::Taskgraph)

Assign required attributes to each task node based on the "Get_Type_String()"
field of the JSON dump. No effect if the "Get_Type_String()" field does not
exist in a node's metadata.

Deletes the "Get_Type_String()" entry from the metadata dictionary after running
so is safe to run multiple times.
"""
function t_unpack_type_strings(tg::Taskgraph)
    for node in getnodes(tg)
        # Quick check to make sure this field exists
        haskey(node.metadata, "Get_Type_String()") || continue
        type_string = node.metadata["Get_Type_String()"]
        if type_string == "memory"
            # Check the number of neighbors
            neighbors = length(tg.adjacency_out[node.name])
            if neighbors == 1
                push_to_dict(node.metadata, "required_attributes", "memory_1port")
            elseif neighbors == 2
                push_to_dict(node.metadata, "required_attributes", "memory_2port")
            else
                error("Memory module ", node.name, " has ", neighbors,
                      " neighbors. Expected 1 or 2.")
            end
            # Iterate through each out node - attach the "memory_processor"
            # attribute to this node.
            # TODO: Make this more robust to make sure destination is actually a
            # processor
            for out_node in out_nodes(tg, node)
                push_to_dict(out_node.metadata, "required_attributes",
                             "memory_processor")
            end
        else
            push_to_dict(node.metadata, "required_attributes", type_string)
        end
        # Delete the "Get_Type_String()" field to make this function safe to run
        # multiple times.
        delete!(node.metadata, "Get_Type_String()")
    end
    return tg
end


"""
    t_assign_link_weights(tg::Taskgraph)

Assign weights to each link in the taskgraph by comparing the number of writes
for a link to the average number of writes across all links.

If "num_writes" is not defined for a link, a default value is used.
"""
function t_assign_link_weights(tg::Taskgraph)
    # First - get the average number of writes over all links.
    # Accumulator for the total number of writes.
    total_writes = 0::Int64
    # Some edges might not have a number of writes field (such as the unpacked
    # memories). This variable will track the number of edges that have this
    # field and thus contribute to the total number of writes
    contributing_edges = 0
    for edge in getedges(tg)
        ismissing(edge.metadata) && continue
        total_writes += edge.metadata["num_writes"]::Int64
        contributing_edges += 1
    end
    average_writes = total_writes / contributing_edges
    # Assign link weights by comparing to the average. Round to three binary
    # digits.
    base            = 2
    round_digits    = 3
    default_weight  = 1.0
    # Assign weights.
    for edge in getedges(tg)
        if !ismissing(edge.metadata["num_writes"])
            ratio = edge.metadata["num_writes"] / average_writes::Float64
            rounded_weight = round(ratio, round_digits, base)
            weight = max(1, rounded_weight)
            edge.metadata["weight"] = weight
        else
            edge.metadata["weight"] = default_weight
        end
        # Check if any of the sources or sinks of this edge is an input.
        # if so - assign a small weight to that link
        for nodename in chain(edge.sources, edge.sinks)
            if oneofin(tg.nodes[nodename].metadata["required_attributes"],
                       ("memory_1port","memory_2port"))
                edge.metadata["weight"] = 3.0
            end
        end
    end

    return tg
end

"""
    t_confirm_and_sort_attributes(tg::Taskgraph)

Confirm that each node in the taskgraph has a non-empty "required_attributes"
field. Sort that field for consistency.
"""
function t_confirm_and_sort_attributes(tg::Taskgraph)
    badnodes = TaskgraphNode[]
    for node in getnodes(tg)
        #=
        Ensure that each node has a "required_attributes" field. If not, add
        it to a list to help with debugging.
        =#
        if haskey(node.metadata, "required_attributes")
            sort!(node.metadata["required_attributes"])
        else
            push!(badnodes, node)
        end
    end
    if length(badnodes) > 0
        print_with_color(:red, "Found ", length(badnodes), " nodes without a",
                         " \"required_attributes\" metadata.")
        for node in badnodes
            println(node)
        end
        error()
    end
    return tg
end

