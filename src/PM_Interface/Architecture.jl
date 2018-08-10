function build_architecture(c::PMConstructor, json_dict)
    # Get the architecture from the options dictionary.
    options = json_dict[_options_path_]
    arch = options[:architecture]

    # If a custom FunctionCall is passed - use that as an architecture
    # constructor. Otherwise, parse through the passed string to decode the
    # architecture.
    if isa(arch, Function)
        @debug "Dispatching Custom Architecture"
        return arch()
    end

    num_links                = options[:num_links]
    use_profiled_links       = options[:use_profiled_links]
    use_task_suitability     = options[:use_task_suitability]

    # Perform manual dispatch based on the string.
    if arch == "Array_Asap3"
        toplevel =  asap3(Rectangular(num_links, 1))
    elseif arch == "Array_Asap4"
        toplevel =  asap4(Rectangular(num_links, 1))
    elseif arch == "Array_Asap2"
        toplevel = asap2(Rectangular(num_links, 1))
    else
        error("Unrecognized Architecture: $arch_string")
    end

    # Run some transformations on the generated architecture
    name_mappables(toplevel, json_dict)
    experimental_transforms(toplevel, json_dict)

    return toplevel
end

function ismatch(c::Component, pm_base_type)
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

function name_mappables(toplevel::TopLevel, json_dict)
    warnings_given = 0
    warning_limit = 10
    for core in json_dict["array_cores"]
        # Get the address for the core
        addr = CartesianIndex(core["address"]...)
        base_type = core["base_type"]

        # Spit out a warning is the address is not in the model.
        if !isaddress(toplevel, addr)
            # Suppress if to many warnings have been generated.
            if warnings_given < warning_limit
                @warn "No address $addr found for core $(core["name"])."
                warnings_given += 1
            elseif warnings_given == warning_limit
                @warn "Suppressing further address warnings."
                warnings_given = warning_limit + 1
            end

            continue
        end

        parent = toplevel[addr]
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

function experimental_transforms(toplevel::TopLevel, json_dict)
    options = json_dict[_options_path_]

    use_task_suitability = options[:use_task_suitability]

    # Normalize the rank assigned to each core based on its provided
    # maximum operating frequency.
    if use_task_suitability
        normalize_ranks(toplevel, options)
    end
end

function normalize_ranks(toplevel::TopLevel, options)
    all_components = [toplevel[path] for path in walk_children(toplevel)]

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
