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

function load_taskgraph(name)
    constructor = CachedSimDump(name)
    return apply_transforms(build_taskgraph(constructor), constructor)
end

function testmap()
    options = Dict{Symbol, Any}()
    println("Building Architecture")
    #arch = build_asap4()
    #arch = build_asap3()
    arch = build_generic(16,16,4,initialize_dict(16,16,12), KCStandard)
    tg = load_taskgraph("aes")
    return NewMap(arch, tg)
end

function run_wrapper(arch_fun,
                     args,
                     taskgraph::Taskgraph,
                     place_kwargs = Dict{Symbol,Any}())
    # Build architecture
    arch = arch_fun(args...)
    # Construct map object
    m = NewMap(arch, taskgraph)
    # Run placement
    m = place(m; place_kwargs...)
    # Run routing
    m = route(m)
    return m
end

function mapping(args...)
    stats_dict = Dict{String,Any}()
    # Scope map object out of the try-catch block
    try
        m = run_wrapper(args...)

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

struct Test
    args::Any
    num_runs::Int64
    metadata::Dict{String,Any}
end

function run(t::Test)
    # Get the specified number of sample runs.
    prefiltered_data = pmap(m -> mapping(t.args...), 1:t.num_runs)
    # Filter out any runs that failed.
    data = collect(filter(x -> x["success"], prefiltered_data))
    # Add fields to the metadata.
    t.metadata["architecture"]      = string(t.args[1])
    t.metadata["architecture_args"] = t.args[2]
    t.metadata["taskgraph"]         = t.args[3].name
    t.metadata["placement_args"]    = t.args[4]
    t.metadata["num_runs"]          = t.num_runs
    # Create a dictionary storing all the results.
    summary = Dict(
        "data" => data,
        "meta" => t.metadata
    )
    return summary
end

function bulk_test(num_runs)
    tests = []
    # Common arguments across all runs
    place_args = Dict{Symbol,Any}(
        :move_attempts  => 500000,
        :warmer         => Mapper2.Place.DefaultSAWarm(0.95, 1.1, 0.99),
        :cooler         => Mapper2.Place.DefaultSACool(0.99),
    )
    # Test AlexNet on KiloCore 2 - weighted links
    # let
    #     for (A,nl) in Iterators.product((KCStandard, KCNoWeight), 2:4)
    #         arch = build_asap4
    #         # Check architecture variations
    #         arch_args = (nl,A)
    #         tg   = load_taskgraph("alexnet")
    #         args = (arch, arch_args, tg, place_args)
    #         new_test = Test(args, num_runs, Dict{String,Any}())
    #         push!(tests, new_test)
    #     end
    # end
    let
        apps    = ("sort", "ldpc", "aes", "fft")
        archs   = (KCStandard, KCNoWeight)
        for (A,app) in Iterators.product(archs, apps)
            arch = build_generic
            # Check architecture variations
            arch_args = (16,16,4,initialize_dict(16,16,4),A)
            tg   = load_taskgraph(app)
            local_place_args = Dict{Symbol,Any}(
                :move_attempts  => 500000,
                :warmer         => Mapper2.Place.DefaultSAWarm(0.95, 1.1, 0.99),
                :cooler         => Mapper2.Place.DefaultSACool(0.9),
            )
            args = (arch, arch_args, tg, local_place_args)
            new_test = Test(args, num_runs, Dict{String,Any}())
            push!(tests, new_test)
        end
    end
    let
        apps    = ("aes", "fft")
        archs   = (KCStandard, KCNoWeight)
        links   = 2:4
        for (A,nl,app) in Iterators.product(archs, links, apps)
            arch = build_asap3
            # Check architecture variations
            arch_args = (nl,A)
            tg   = load_taskgraph(app)
            args = (arch, arch_args, tg, place_args)
            new_test = Test(args, num_runs, Dict{String,Any}())
            push!(tests, new_test)
        end
    end

    results_array = []
    for t in tests
        results = run(t)
        save(results)
        push!(results_array, results)
    end
    return results_array
end

function save(d)
    # Make a name for the saved dictionary.
    args_string = join(d["meta"]["architecture_args"][1:2],"_")
    name = join([
        d["meta"]["taskgraph"],
        d["meta"]["architecture"],
        args_string,
        "json.gz"],
        "_", ".")
    f = GZip.open(joinpath(PKGDIR, "results", name), "w")
    JSON.print(f, d, 2)
    close(f)
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
