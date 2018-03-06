struct PlacementTest
    arch_constructor    ::Function
    arch_args           ::Vector{Any}
    place_type          ::String
    taskgraph           ::Taskgraph
    place_kwargs        ::Dict{Symbol,Any}
    num_placements      ::Int64
    low_temp_samples    ::Int64
    metadata            ::Dict{String,Any}
end

function run(t::PlacementTest)
    # Make closure for doing the bulk placement.
    f(x) = generate_placement(t.arch_constructor,
                              first(t.arch_args),
                              t.taskgraph,
                              t.place_kwargs,
                              t.low_temp_samples,
                              x)

    @info "Total Placements: $(t.num_placements)"
    # Get the specified number of sample runs.
    pmap(i -> f(i), 1:t.num_placements)

    # Iterate through all the architecture arguments, route each of the
    # placements generated previously
    for (j,arch_arg) in enumerate(t.arch_args)
        @info "Routing $j of $(length(t.arch_args))"
        @info "Number of sub-routes: $(t.num_placements)"
        g(x) = run_routing(t.arch_constructor,
                           arch_arg,
                           t.taskgraph,
                           t.low_temp_samples,
                           x)
        pre_data = pmap(i -> g(i), 1:t.num_placements)
        data = collect(filter(x -> x["success"], pre_data))
        # Collect results
        metadata = Dict(
            "architecture"      => string(t.arch_constructor),
            "architecture_args" => arch_arg,
            "place_type"        => t.place_type,
            "app_name"          => t.taskgraph.name,
            "placement_args"    => t.place_kwargs,
            "num_placements"    => t.num_placements,
            "low_temp_samples"  => t.low_temp_samples
        )

        summary = Dict(
            "data" => data,
            "meta" => metadata,
        )

        save(summary)
    end
end


function route(arch::TopLevel,
               taskgraph::Taskgraph,
               iteration_number;
               nsamples = 1) 

    m = NewMap(arch, taskgraph)

    # Initialize the statistics dictionary to pessimistically assume that
    # routing was not successful. Easy to set this to true after a successful
    # routing.
    stats_dict = Dict{String,Any}(
        "results" => [],
        "success" => false,
     )

    for i in 1:low_temp_runs
        @info "Subrouting $iteration_number: on $i of $nsamples"
        load_path = joinpath(PKGDIR, "temp", "$(iter)_$(i)")
        Mapper2.MapType.load(m, load_path)
        success = false
        try
            m = route(m)
            local_dict = Dict{String,Any}() 
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
            local_dict["global_links"] = global_links
            local_dict["average_length"] = average_length
            local_dict["max_length"] = max_length
            local_dict["weighted_objective"] = weighted_objective
            # Add the local dict to the results array in the stats dict.
            push!(stats_dict["results"], local_dict)
            stats_dict["success"] = true
        end
    end
    return stats_dict
end

# nruns: The number of independent placements to run for each test.
# nsamples: The number of low temperature variations to use.
function bulk_test(nruns, nsamples)
    # Set the logging level for Mapper2 to warning
    @everywhere Mapper2.set_logging(:error)
    @warn "Launching a large bulk run"
    tests = []
    # Common arguments across all runs
    place_kwargs = Dict{Symbol,Any}(
        :move_attempts  => 1000000,
        :warmer         => Mapper2.Place.DefaultSAWarm(0.95, 1.1, 0.99),
        :cooler         => Mapper2.Place.AcceleratingSACool(0.999, 0.001, 0.9),
    )

    app_names = ("alexnet", "sort", "ldpc", "aes", "fft")
    taskgraphs = Dict(i => load_taskgraph(i) for i in app_names)
    strategies = (KCStandard, KCNoWeight)

    tests_to_run = (asap4_tests,)
    #tests_to_run = (asap3_tests, generic1_tests, generic2_tests)

    # Generate tests
    for f in tests_to_run
        f(tests, strategies, nruns, nsamples, taskgraphs, place_kwargs)
    end

    @info "Running a total of $(length(tests)) tests"

    # Run tests
    for (i,t) in enumerate(tests)
        @info "Running test $i of $(length(tests))"
        run(t)
    end
    return nothing
end
