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

    num_links                = options[:num_links]
    use_profiled_links       = options[:use_profiled_links]
    use_task_suitability     = options[:use_task_suitability]
    use_heterogenous_mapping = options[:use_heterogenous_mapping]

    # Hack at the moment - make sure both specialized mapping options are not
    # active at the same time.
    @assert !(use_task_suitability && use_heterogenous_mapping)
    kc_type = KC{use_task_suitability, use_heterogenous_mapping}

    @debug "Use KC Type: $kc_type"

    # Perform manual dispatch based on the string.
    if arch == "Array_Asap3"
        toplevel =  asap3(num_links, kc_type)
    elseif arch == "Array_Asap4"
        toplevel =  asap4(num_links, kc_type)
    else
        error("Unrecognized Architecture: $arch_string")
    end

    # Run some transformations on the generated architecture
    name_mappables(toplevel, json_dict)
    experimental_transforms(toplevel, json_dict)

    return toplevel
end

function Base.ismatch(c::Component, pm_base_type)
    haskey(c.metadata, typekey()) || (return false)
    # Check the two implemented mapper attributes for processors
    if pm_base_type == "Processor_Core"
        return isproc(c)
    elseif pm_base_type == "Memory_Core"
        return ismemory(c)
    elseif pm_base_type == "Input_Handler_Core"
        return isinput(c)
    elseif pm_base_type == "Output_Handler_Core"
        return isoutput(c)
    end

    return false
end

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
                component.metadata["pm_name"] = get(core, "name", missing)
                component.metadata["pm_type"] = get(core, "type", missing)
                component.metadata["mapper_annotation"] = get(core, "mapper_annotation", missing)

                rank = get(core,"max_frequency",missing)
                setrank!(component, CoreRank(rank))
                break
            end
        end
    end
end

function experimental_transforms(a::TopLevel, json_dict)
    options = json_dict[_options_path_]

    use_task_suitability = options[:use_task_suitability]
    use_heterogenous_mapping = options[:use_heterogenous_mapping]

    # Normalize the rank assigned to each core based on its provided
    # maximum operating frequency.
    if use_task_suitability
        normalize_ranks(a, options)

    # Read through the special_assignments dictionary to assign cores as either
    # high-performance or low-power
    elseif use_heterogenous_mapping
        specialize_cores(a, options)
    end
end

function normalize_ranks(a::TopLevel, options)
    all_components = [a[path] for path in walk_children(a)]

    nonranking_types = (MTypes.input, MTypes.output)
    ranking_types = (MTypes.proc, MTypes.memory(1), MTypes.memory(2))

    # First, handle input/output handlers
    # Set all of their ranks to 1.0 because right now, we aren't ranking input
    # or output handlers.
    for component in all_components
        if ismappable(component) && isnonranking(component)
            getrank(component).normalized_rank = 1.0
        end
    end

    # Now, handle ranking components. Gather all of the ranks that matter and
    # find the maximum of the non-missing assignments.
    ranking_components = [c for c in all_components if ismappable(c) && !isnonranking(c)]
    coreranks = [getrank(c) for c in ranking_components]

    rank_max::Float64 = typemin(Float64)
    for corerank in coreranks
        rank = corerank.rank
        if !ismissing(rank)
            rank_max = max(rank_max, rank)
        end
    end

    # If range is zero - all cores have the same frequency.
    num_digits = 6

    # Must make sure that no core has a rank of zero, otherwise ratios of task
    # rank to core rank can be infinity, which is not very useful.
    minimum_rank = 2.0 ^ (-num_digits)

    ranks = Float64[]
    for component in ranking_components
        corerank = getrank(component)

        rank = corerank.rank
        if ismissing(rank)
            corerank.normalized_rank = minimum_rank
        else
            corerank.normalized_rank = max(
                round( rank / rank_max, num_digits, 2),
                minimum_rank
            )
        end

        # For debugging.
        push!(ranks, corerank.normalized_rank)
    end

    @debug "$ranks"
end

# Specialize processor cores as either "high-performance" or "low-power".
function specialize_cores(toplevel::TopLevel, options::Dict)
    # Iterate through all processor types, add metadata based on their 
    # annotation.
    all_components = [toplevel[path] for path in walk_children(toplevel)]

    # Counters for debugging
    num_low_power = 0
    num_high_performance = 0

    for component in all_components
        # Default memory processors to high-performance for now. 
        # TODO: Rethink if this is the right thing todo. Since memories tend to
        # be highly utilized, it's probably okay for now.
        if ismemoryproc(component)
            add_highperformance(component)
            num_high_performance += 1

        # Get the annotation for the component. Throw an error for now if 
        # "mapper_annotation" is not found for debugging purposes.
        elseif isproc(component)
            annotation = component.metadata["mapper_annotation"]
            specialization = annotation["specialization"]

            if specialization == "low_power"
                add_lowpower(component)
                num_low_power += 1

            elseif specialization == "high_performance"
                add_highperformance(component)

                # Add the low_power attribute as well to allow low_power
                # tasks to still be mapped to these processors.
                add_lowpower(component)

                num_high_performance += 1

            else
                throw(KeyError(specialization))
            end
        end
    end

    @debug """
    Number of high performance cores: $num_high_performance

    Number of low power cores: $num_low_power
    """
end
