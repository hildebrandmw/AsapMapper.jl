function place_and_route(input_profile, output_file, appname)
    # Build the asap4 architecture
    arch = build_asap4(A = KCStandard) 

    # Construct the taskgraph from the given profile file.
    sdc  = SimDumpConstructor{false}(appname, input_profile)
    taskgraph = Taskgraph(sdc)
    tg = apply_transforms(taskgraph, sdc)

    # Build a map
    m = NewMap(arch, tg)
    
    # Run Placement and routing
    m = (route ∘ place)(m)
    
    # Save the placement and routing information
    dump(m, output_file)
    return nothing
end

function testmap()
    options = Dict{Symbol, Any}()
    println("Building Architecture")
    #arch = build_asap4()
    arch = build_asap3()
    #arch = build_generic(15,16,4,initialize_dict(15,16,12), A = KCStandard)
    sdc   = CachedSimDump("aes")
    println("Building Taskgraph")
    taskgraph = build_taskgraph(sdc)
    tg    = apply_transforms(taskgraph, sdc)
    return NewMap(arch, tg)
end

function get_maps()
    app = "ldpc"
    # Build up the architectures to test.
    generic_15_16_4    = build_generic(15,16,4, initialize_dict(15,16,12))
    generic_16_16_4    = build_generic(16,16,4, initialize_dict(16,16,12))
    generic_16_17_4    = build_generic(16,17,4, initialize_dict(16,17,12))
    generic_17_17_4    = build_generic(17,17,4, initialize_dict(17,17,12))
    generic_17_18_4    = build_generic(17,18,4, initialize_dict(17,18,12))
    generic_18_18_4    = build_generic(18,18,4, initialize_dict(18,18,12))
    generic_18_19_4    = build_generic(18,19,4, initialize_dict(18,19,12))
    generic_19_19_4    = build_generic(19,19,4, initialize_dict(19,19,12))

    # Add all of the architectures to an array.
    architectures = [generic_15_16_4,
                     generic_16_16_4,
                     generic_16_17_4,
                     generic_17_17_4,
                     generic_17_18_4,
                     generic_18_18_4,
                     generic_18_19_4,
                     generic_19_19_4]

    # Give names to each of the architectures - append the app name to
    # the front
    save_names = "$(app)_" .* ["generic_15_16_4",
                               "generic_16_16_4",
                               "generic_16_17_4",
                               "generic_17_17_4",
                               "generic_17_18_4",
                               "generic_18_18_4",
                               "generic_18_19_4",
                               "generic_19_19_4"]

    # Build the taskgraphs
    taskgraph_constructor = SimDumpConstructor(app)
    debug_print(:start, "Building Taskgraph\n")
    taskgraph = Taskgraph(taskgraph_constructor)
    taskgraph = apply_transforms(taskgraph, taskgraph_constructor)

    # Build the maps for each architecture/taskgraph pair.
    maps = NewMap.(architectures, taskgraph)

    return maps, save_names
end


function bulk_run()
    maps, save_names = get_maps()

    # Build an anonymous function to allow finer control of the placement
    # function.
    place_algorithm = m -> place(m,
          move_attempts = 500000,
          warmer = DefaultSAWarm(0.95, 1.1, 0.99),
          cooler = DefaultSACool(0.998),
         )

    # Execute the parallel run
    routed_maps = parallel_run(maps, save_names, place_algorithm = place_algorithm)

    return routed_maps
end

"""
    parallel_run(maps, save_names)

Place and route the given collection of maps in parallel. After routing,
all maps will be saved according to the respective entry in `save_names`.
"""
function parallel_run(maps, save_names; place_algorithm = m -> place(m))
    # Parallel Placement
    placed = pmap(place_algorithm, maps)
    # Parallel Routing
    routed = pmap(m -> route(m), placed)
    # Print out statistic for each run - also save everything.
    print_with_color(:yellow, "Run Statistics\n")
    for (m, name) in zip(routed, save_names)
        print_with_color(:light_cyan, name, "\n")
        report_routing_stats(m)
        save(m, name)
    end
    return routed
end

function slow_run(m)
    # Run placement
    m = place(m,
          move_attempts = 50000,
          warmer = DefaultSAWarm(0.95, 1.1, 0.99),
          cooler = DefaultSACool(0.99),
         )
    m = route(m)
    return m
end

function shotgun(m::Map{A,D}, iterations; kwargs...) where {A,D}
    # Get the placement struct.
    placement_struct = get_placement_struct(m)
    structs = typeof(placement_struct)[]
    first = true
    local state
    for i = 1:iterations
        if first
            ps = deepcopy(placement_struct)
            state = place(ps; kwargs...)
            push!(structs, ps)
            first = false
        else
            ps = deepcopy(last(structs))
            state = place(ps; supplied_state = state,
                              kwargs...,
                              warmer = TrueSAWarm(),
                             )
            push!(structs, ps)
        end
    end

    first = true
    best  = 0
    for ps in structs
        # Record the placement.
        record(m, ps)
        # Run the routing protocol.
        routing_struct = RoutingStruct(m)
        algorithm = routing_algorithm(m, routing_struct)
        route(algorithm, routing_struct)
        # Continue if routing structure is congested
        iscongested(routing_struct) && continue
        tl = total_links(routing_struct)
        if first
            best = tl
            record(m, routing_struct)
            first = false
        else
            if best > tl
                best = tl
                record(m, routing_struct)
            end
        end
    end
    first == true && error()
    return m
end
