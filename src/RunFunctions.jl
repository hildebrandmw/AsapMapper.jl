################################################################################
# MAIN PLACE AND ROUTE FUNCTION
################################################################################
function place_and_route(architecture, profile_path, dump_path)
    # Initialize an uncompressed taskgraph constructor
    tc = SimDumpConstructor{false}("blank", profile_path)
    t = build_taskgraph(tc)

    # Dispatch architecture
    if architecture == "asap4"
        a = asap4(2, KCStandard)
    elseif architecture == "asap3"
        a = asap3(2, KCNoWeight)
    else
        KeyError("Architecture $architecture not implemented.")
    end

    # Build the Map
    m = NewMap(a, t)

    # Run placement
    m = place(m)

    # Run Routing
    m = route(m)

    # Dump mapping to given dump path
    Mapper2.save(m, dump_path, false)
end

function load_taskgraph(name)
    constructor = CachedSimDump(name)
    return build_taskgraph(constructor)
end

function testmap()
    options = Dict{Symbol, Any}()
    println("Building Architecture")
    #arch = asap4(2, KCStandard)
    #arch = asap3_hex(2, KCStandard)
    arch = asap3(3, KCStandard)
    #arch = generic(16,16,4,initialize_dict(16,16,12), KCStandard)
    tg = load_taskgraph("sort")
    return NewMap(arch, tg)
end

struct PlacementTest
    arch_constructor::Function
    arch_args       ::Vector{Any}
    place_type      ::String
    taskgraph       ::Taskgraph
    place_kwargs    ::Dict{Symbol,Any}
    num_placements  ::Int64
    metadata        ::Dict{String,Any}
end

function run(t::PlacementTest)
    # Make closure for doing the bulk placement.
    f(x) = generate_placement(t.arch_constructor,
                              first(t.arch_args),
                              t.taskgraph,
                              t.place_kwargs,
                              x)

    # Get the specified number of sample runs.
    pmap(i -> f(i), 1:t.num_placements)

    # Iterate through all the architecture arguments, route each of the 
    # placements generated previously
    for arch_arg in t.arch_args
        g(x) = run_routing(t.arch_constructor,
                           arch_arg,
                           t.taskgraph,
                           x)
        pre_data = pmap(i -> g(i), 1:t.num_placements)
        data = collect(filter(x -> x["success"], pre_data))
        # Collect results
        metadata = Dict(
            "architecture"      => string(t.arch_constructor),
            "architecture_args" => arch_arg,
            "place_type"        => t.place_type,
            "taskgraph"         => t.taskgraph.name,
            "placement_args"    => t.place_kwargs,
            "num_placements"    => t.num_placements,
        )

        summary = Dict(
            "data" => data,
            "meta" => metadata,
        )

        save(summary)
    end
end

function generate_placement(arch_constructor, 
                            arch_args, 
                            taskgraph::Taskgraph,
                            place_kwargs,
                            iter::Int)
    # Build Architecture
    arch = arch_constructor(arch_args...)
    # Construct a new Map object
    m = NewMap(arch, taskgraph)
    # Run Placement
    m = place(m; place_kwargs...)
    # Save the resulting placement to file.
    save_path = joinpath(PKGDIR, "saved", string(iter))
    Mapper2.MapType.save(m, save_path)
    return nothing
end

function run_routing(arch_constructor,
                     arch_args,
                     taskgraph::Taskgraph,
                     iter::Int)
    
    # Build Architecture
    arch = arch_constructor(arch_args...)
    # Construct a new Map object
    m = NewMap(arch, taskgraph)
    # Load placement from file
    load_path = joinpath(PKGDIR, "saved", string(iter))
    Mapper2.MapType.load(m, load_path)

    # Begin routing
    stats_dict = Dict{String,Any}()
    try
        m = route(m)
        stats_dict["success"] = m.metadata["routing_success"]
        # Get statistics from the mapping.

        # Returns a histogram dictionary where keys are the hop distances and
        # values are the number of communication links of that distance
        histogram = Mapper2.MapType.global_link_histogram(m)
        # Total number of global routing links used.
        num_links = sum(values(histogram))
        global_links = sum(k*v for (k,v) in histogram)
        # Get the average link length
        average_length = global_links / num_links
        max_length = maximum(keys(histogram))
        # Construct a weighted number of links based on the product of the link
        # length and the number of writes made on a link.
        weighted_objective = 0
        for (taskgraph_link, mapped_link) in zip(m.taskgraph.edges, m.mapping.edges)
            # Get the number of global routing links used
            link_count = Mapper2.MapType.count_global_links(mapped_link)
            weight = taskgraph_link.metadata["num_writes"]
            weighted_objective += link_count * weight
        end

        # Record results in the dictionary
        stats_dict["global_links"] = global_links
        stats_dict["average_length"] = average_length
        stats_dict["max_length"] = max_length
        stats_dict["weighted_objective"] = weighted_objective
        return stats_dict
    # Catch un-routable placements.
    catch e
        print_with_color(:red, e, "\n")
        stats_dict["success"] = false
        return stats_dict
    end
end

function bulk_test(num_runs)
    tests = []
    # Common arguments across all runs
    place_kwargs = Dict{Symbol,Any}(
        :move_attempts  => 500000,
        :warmer         => Mapper2.Place.DefaultSAWarm(0.95, 1.1, 0.99),
        :cooler         => Mapper2.Place.DefaultSACool(0.99),
    )

    app_names = ("alexnet", "sort", "ldpc", "aes", "fft")
    taskgraphs = Dict(i => load_taskgraph(i) for i in app_names)
    strategies = (KCStandard, KCNoWeight)

    asap3_hex_tests(tests, strategies, num_runs, taskgraphs, place_kwargs)
    # Test AlexNet on KiloCore 2 - weighted links
    # let
    #     for A in (KCStandard, KCNoWeight)
    #         arch = asap4
    #         # Check architecture variations
    #         arch_args = [(nlinks,A) for nlinks in 2:6]
    #         tg        = taskgraphs["alexnet"]

    #         new_test  = PlacementTest(arch,
    #                                   arch_args,
    #                                   string(A),
    #                                   tg,
    #                                   place_kwargs,
    #                                   num_runs,
    #                                   Dict{String,Any}(),
    #                                  )
    #         push!(tests, new_test)
    #     end
    # end
    # let
    #     apps    = ("aes", "fft", "sort", "ldpc")
    #     archs   = (KCStandard, KCNoWeight)
    #     for (A,app) in Iterators.product(archs, apps)
    #         arch = asap3
    #         # Check architecture variations
    #         arch_args = [(nlinks,A) for nlinks in 2:6]
    #         tg   = taskgraphs[app]

    #         new_test = PlacementTest(arch,
    #                                  arch_args,
    #                                  string(A),
    #                                  tg,
    #                                  place_kwargs,
    #                                  num_runs,
    #                                  Dict{String,Any}(),
    #                                 )

    #         push!(tests, new_test)
    #     end
    # end
    # let
    #     apps    = ("aes", "fft", "sort", "ldpc")
    #     archs   = (KCStandard, KCNoWeight)
    #     for (A,app) in Iterators.product(archs, apps)
    #         arch = generic
    #         # Check architecture variations
    #         arch_args = [(16,16,4,12,A,nl) for nl in 2:4]
    #         tg   = taskgraphs[app]

    #         new_test = PlacementTest(arch,
    #                                  arch_args,
    #                                  string(A),
    #                                  tg,
    #                                  place_kwargs,
    #                                  num_runs,
    #                                  Dict{String,Any}(),
    #                                 )

    #         push!(tests, new_test)
    #     end
    # end
    # let
    #     apps    = ("sort",)
    #     archs   = (KCStandard, KCNoWeight)
    #     for (A,app) in Iterators.product(archs, apps)
    #         arch = generic
    #         # Check architecture variations
    #         arch_args = [(10,10,10,0,A,nl) for nl in 2:4]
    #         tg   = taskgraphs[app]

    #         new_test = PlacementTest(arch,
    #                                  arch_args,
    #                                  string(A),
    #                                  tg,
    #                                  place_kwargs,
    #                                  num_runs,
    #                                  Dict{String,Any}(),
    #                                 )

    #         push!(tests, new_test)
    #     end
    # end

    for t in tests
        run(t)
    end
    return nothing
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
