# Location in the input dictionary where the architecture specification 
# can be found.
const _options_path_ = KeyChain(("mapper_options",))

# Don't rank input or output nodes.
isnonranking(t) = isinput(t) || isoutput(t)

struct PMConstructor{T <: Union{String,Dict}} <: MapConstructor
    file    ::T
    options ::NamedTuple

    #--inner constructor
    function PMConstructor(file::T, options::NamedTuple = NamedTuple()) where T
        # Iterate through each opion in "kwargs" - ensure it is in the list of
        # options provided by "_defult_options_"
        default_options = _get_default_options()
        for key in keys(options)
            if !haskey(default_options, key)
                error("Unrecognized Mapper Override option $(key).")
            end
        end
        return new{T}(file, options)
    end
end


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

        # Load Existing Maps
        # ------------------

        # Path (string) to an existing map. Must be compatible with the rest of 
        # the options provided or bad things might happen.
        :existing_map => nothing,
      )
end

function Base.parse(c::PMConstructor{String})
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

function Base.parse(c::PMConstructor{<:Dict})
    dict = c.file
    final_options = parse_options(c.options, dict["mapper_options"])
    dict["mapper_options"] = final_options
    return dict
end

"""
    parse_options(internal::NamedTuple, external::Dict)

Parse the options passed internally and externally. Prune all external options
that are not in the `default_options` dict and return a final options
dictionary with the following option precedences from highest to lowest:

`internal`, `external`, `default`.
"""
function parse_options(internal::NamedTuple, external::Dict)
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
    final_dict = merge(default_options, external_sym, Dict(pairs(internal)))

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

    # build the map and attach the options dictionary to it.
    options = json_dict[_options_path_]

    use_task_suitability = options[:use_task_suitability]

    kc_rule = KC{use_task_suitability}()
    m = Map(kc_rule,a,t)
    m.options = options

    # Load an existing map if provided with one.
    if typeof(options[:existing_map]) <: String
        Mapper2.MapperCore.load(m, options[:existing_map])
    end


    # Print out the important operations for information/debugging purposes.
    task_rank_key = options[:use_task_suitability] ? options[:task_rank_key] : ""

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
    #
    # Parameterize this to avoid typing out the whole type-name.
    ratio_max_heap::T
end

AuxStorage(x, heap) = AuxStorage(Float64(x), 0.0, heap)


function asap_pnr(m::Map{A,D}) where {A,D}
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
            place!(m, enable_address = true, aux = aux)
            success = true
            # Sometimes, routing will fail if memory processors are not located
            # next to their respective memories. This try-catch block makes sure
            # the whole routine doesn't break if this happens.
            try
                route!(m)
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
                place!(m)
                route!(m)
                check_routing(m; quiet = true) && break
            catch err
                @error "Received routing error: $err. Trying again."
            end
        end
    end

    return m
end

