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
    function PMConstructor(file::String, options = Dict{Symbol,Any}())
        # Iterate through each opion in "kwargs" - ensure it is in the list of
        # options provided by "_defult_options_"
        for key in keys(options)
            if !haskey(_default_options, key)
                error("Unrecognized Mapper Override option $(key).")
            end
        end
        return new(file, options)
    end
end

# Central list of options that are expected from the project manager input
# file or are to be over-ridden by local options.
#
# The first value in each Pair is the dict key, second value is the default.
const _default_options = Dict(
    # Architecture Generation
    # -----------------------

    # Default to nothing for error handling. 
    :architecture => nothing,
    # Default the number of links to 2 to match Asap3/4 architectures.
    # This option will be invalid if ':architecture' is a FunctionCall.
    :num_links => 2,

    # Mapping Options
    # ---------------
    # Set to "true" to assign weights to inter-task communication links
    # according to the normalized number of writes on that link.
    :weight_links => true,
    # Set to "true" to include frequency as a criteria for mapping.
    :use_frequency => false,
    :frequency_penalty_start => 10.0,
    # If these options are left as "nothing", will pull frequency information
    # out of the Project Manager input file. Otherwise, if they are a 
    # "FunctionCall" to a synthetic generation function, that function will be
    # used to to generate frequency data.
    :task_freq_source   => t::Taskgraph -> generate_task_frequencies(t),
    :task_freq_bin      => t::Taskgraph -> bin_task_frequencies(t, 5),
    :proc_freq_source   => x::TopLevel -> generate_arch_frequencies(x),
    :proc_freq_bin      => x::TopLevel -> bin_arch_frequencies(x, 5),
  )

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
that are not in the `_default_options` dict and return a final options 
dictionary with the following option precedences from highest to lowest:

`internal`, `external`, `default`.
"""
function parse_options(internal::Dict{Symbol,Any}, external::Dict{String,Any})
    # Convert the keys of 'external' to symbols for uniformity.
    external_sym = Dict(Symbol(k) => v for (k,v) in external)
    # Filter out unrecognized options.
    keys_to_delete = Symbol[]
    for key in keys(external_sym)
        if !haskey(_default_options,key)
            @warn "Unrecognized Mapper option: $key."
            push!(keys_to_delete, key)
        end
    end
    for key in keys_to_delete
        delete!(external_sym, key)
    end
    # Merge all results together. Use the precedence in the `merge` operation to
    # get this correct.
    return merge(_default_options, external_sym, internal)
end

################################################################################
# build_map - Top level function for creating Map objects from the Project
#   Manager.
################################################################################
function build_map(c::PMConstructor)
    # Parse the input json file
    json_dict = parse(c)
    # Build the architecture based off the config file.
    a = build_architecture(c, json_dict)
    # Build taskgraph
    t = build_taskgraph(c, json_dict)
    # Run operations on the architecture according.
    name_mappables(a, json_dict)
    compute_frequencies(a, json_dict)

    # build the map and attach the options dictionary to it.
    m = NewMap(a,t)
    m.options = json_dict[_options_path_]

    return m
end

function asap_pnr(m::Map)
    if m.options[:use_frequency]
        aux = m.options[:frequency_penalty_start] 
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
            if success && check_routing(m)
                break
            else
                aux = aux / 2
                @info "Routing Failed. Trying aux = $(aux)"
            end
        end
    else
        m = place(m)
        m = route(m)
    end
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

    num_links       = options[:num_links]
    weight_links    = options[:weight_links]
    use_frequency   = options[:use_frequency]

    kc_type = KC{weight_links,use_frequency}
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

const _pm_task_required = ("type",)
const _pm_task_optional = ("Get_Workload()",)
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
    parse_input(t, json_dict["task_structure"])

    # post-processing routines
    for op in taskgraph_ops(c)
        @debug "Running Taskgraph Trasnform $op"
        t = op(t, options)
    end
    return t
end

taskgraph_ops(::PMConstructor) = (transform_task_types,
                                  compute_edge_metadata,
                                  apply_link_weights,
                                  interpret_frequency,
                                 )

function parse_input(t::Taskgraph, tasklist)
    # One iteration to collect all of the task nodes.
    for task in tasklist
        name = task["name"]
        required_metadata = getkeys(task, _pm_task_required)
        optional_metadata = getkeys(task, _pm_task_optional, false)
        metadata = merge(optional_metadata, required_metadata)
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
            for io_decl in values(link_dict), link_def in values(io_decl)
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
        edge.metadata["preserve_dest"] = (edge.metadata["pm_class"] == "Circuit_Link")
    end
    return t
end


"""
    transform_task_types(t::Taskgraph, options::Dict)

Transform the Project Manager Task Types to the task type used internally by
the Mapper.
"""
function transform_task_types(t::Taskgraph, options::Dict)
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

function apply_link_weights(t::Taskgraph, options::Dict)
    options[:weight_links] || (return t)

    # For now, just assign unit weights.
    for edge in getedges(t)
        if edge.metadata["pm_class"] in ("Memory_Request_Link", "Memory_Response_Link")
            edge.metadata["cost"] = 5.0
        else
            edge.metadata["cost"] = 1.0
        end
    end
    return t
end

function interpret_frequency(t::Taskgraph, options::Dict)
    # Early Abort
    options[:use_frequency] || (return t)
    # Get callback for frequency assignment.
    # Can choose to either use data encoded directly in the taskgraph or to
    # generate synthetic data.
    options[:task_freq_source](t)
    # Use the selected binning function to bin frequencies.
    options[:task_freq_bin](t)
    return t
end

function generate_task_frequencies(t::Taskgraph)
    @debug "Generating Task Frequencies"
    for task in getnodes(t)
        task.metadata["frequency"] = randn()
    end
end

function bin_task_frequencies(t::Taskgraph, nbins::Int)
    @debug "Binning Task Frequencies"
    # Step 1: Collect the range of frequencies to determine the size of each bin.
    frequencies = [task.metadata["frequency"] for task in getnodes(t)]
    fmin, fmax = extrema(frequencies)
    binsize = (fmax - fmin) / nbins

    # Step 2: Assign bins to each task. Fastest frequency requirement 
    # (highest bin) will get the lowest bin.
    for task in getnodes(t)
        task_freq = task.metadata["frequency"]
        # Quick check to put the max frequency into bin 1.0
        if task_freq == fmax
            bin = 1.0
        else
            bin = ceil( (fmax - task_freq) / binsize )
        end
        task.metadata["frequency_bin"] = bin
    end
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
                component.metadata["max_frequency"] = core["max_frequency"]
                break
            end
        end
    end
end

function compute_frequencies(a::TopLevel, json_dict)
    options = json_dict[_options_path_]     
    # Abort if 'use_frequency' is false
    !options[:use_frequency] && (return)
    # Callback for synthetically assigning frequencies if needed.
    options[:proc_freq_source](a)
    # Callback for binning frequencies.
    options[:proc_freq_bin](a)
end

# Synthetic generator for architecture frequencies.
function generate_arch_frequencies(a::TopLevel)
    f(path) = search_metadata(a[path], "attributes")
    paths = filter(f, walk_children(a))

    for path in paths
        a[path].metadata["max_frequency"] = randn()
    end
end

function bin_arch_frequencies(a::TopLevel, nbins::Int)
    f(path) = search_metadata(a[path], "attributes")
    paths = filter(f, walk_children(a))
    
    frequencies = [a[path].metadata["max_frequency"] for path in paths]
    fmin, fmax = extrema(frequencies)
    binsize = (fmax - fmin) / nbins

    for path in paths
        core_freq = a[path].metadata["max_frequency"]
        if core_freq == fmax
            bin = 1.0
        else
            bin = ceil( (fmax - core_freq) / binsize )
        end
        a[path].metadata["frequency_bin"] = bin
    end
end
