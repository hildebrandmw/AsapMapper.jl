function build_architecture(c::PMConstructor, json_dict)
    # Get the architecture from the options dictionary.
    options = json_dict[_options_path_]
    arch = options[:architecture]

    # If a custom function is passed - use that as an architecture
    # constructor. Otherwise, parse through the passed string to decode the
    # architecture.
    if isa(arch, Function)
        @debug "Dispatching Custom Architecture"
        return arch()
    end

    num_links = options[:num_links]

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
                # Check if core name is "nothing".
                if core["name"] === nothing
                    msg = "Address $addr not found"
                else
                    msg = "No address $addr found for core $(core["name"])."
                end
                @warn msg

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
                break
            end
        end
    end
end
