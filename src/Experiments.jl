# Set of applications to test.
apps() = (
    # AES flavors
    ("AES_v1", ["-lanes" => 1, "-sim_off", "-gui_off"]),
    ("AES_v1", ["-lanes" => 2, "-sim_off", "-gui_off"]),
    ("AES_v1", ["-lanes" => 3, "-sim_off", "-gui_off"]),
    ("AES_v1", ["-lanes" => 4, "-sim_off", "-gui_off"]),
    ("AES_v1", ["-lanes" => 5, "-sim_off", "-gui_off"]),
    ("AES_v1", ["-lanes" => 6, "-sim_off", "-gui_off"]),
    ("AES_v1", ["-lanes" => 7, "-sim_off", "-gui_off"]),

    # FFT v5
    ("FFT_v5", ["-sim_off", "-gui_off"]),

    # FFT_v3
    ("FFT_v3", ["-lanes" => 1, "-sim_off", "-gui_off"]),
    ("FFT_v3", ["-lanes" => 2, "-sim_off", "-gui_off"]),
    ("FFT_v3", ["-lanes" => 3, "-sim_off", "-gui_off"]),
    ("FFT_v3", ["-lanes" => 4, "-sim_off", "-gui_off"]),
    ("FFT_v3", ["-lanes" => 5, "-sim_off", "-gui_off"]),
    ("FFT_v3", ["-lanes" => 6, "-sim_off", "-gui_off"]),
    ("FFT_v3", ["-lanes" => 7, "-sim_off", "-gui_off"]),

    # Sorting
    ("Main_Snakesort", ["-num_sorters"=>400, "-sim_off", "-gui_off"]),
    ("Main_Rowsort", ["-num_rows"=>20, "-num_sorters_per_row"=>40, "-sim_off", "-gui_off"]),
)

function loadapps()
    for (app, args) in apps()
        loadtaskgraph(app, args)
    end
end

function initapps()
    for (app, args) in apps()
        initgen(app, args)
    end
end



# Vary move attempts and move limiter.
# Move attempts to try: 10000, 20000, 50000, 100000, 200000
# Limit: try .20, .30, .40, .44, .50
function experiment_1(input_file)
    # Build the PM Constructor from the input file name.
    pm_constructor = PMConstructor(input_file)

    move_attempts = [20000, 50000, 100000, 200000]
    limits        = [0.20, 0.30, 0.40, 0.44, 0.50]
    movegens      = [:search, :cached]
    results = []

    for (moves, limit, movegen) in Iterators.product(move_attempts, limits, movegens)
        # Instantiate the move generator to use.
        if movegen == :search
            move_generator = SA.SearchMoveGenerator()
        else
            move_generator = SA.CachedMoveGenerator{CartesianIndex{2}}()
        end

        # Make a kwargs dict to pass to placement.

        kwargs_dict = Dict(
            :move_attempts  => moves,
            :limiter        => SA.DefaultSALimit(limit),
            :movegen       => move_generator,
        )

        # Run place and route.
        metadata_vector = multi_pnr_with_ip_route(pm_constructor, 10, kwargs_dict)

        # Create a result dictionary and append it to the "results"
        result_dict = Dict(
            "data"              => metadata_vector,
            "move_attempts"     => moves,
            "limit_ratio"       => limit,
            "move_generator"    => movegen
        )

        push!(results, result_dict)

        # Create a name for this file and save it.
        open("results_$input_file", "w") do f
            JSON.print(f, results, 2)
        end
    end

    open("done.txt", "w") do f
        print(f, "Yay!")
    end

end


function pnr(c::PMConstructor, kwargs_dict)
    m = build_map(c)
    m = place(m; kwargs_dict...)
    m = route(m)
    return m
end

function multi_pnr_with_ip_route(c::PMConstructor, num_maps::Int, kwargs_dict)
    # Do the normal placement and routing in parallel.
    maps = pmap(x -> pnr(c, kwargs_dict), 1:num_maps)

    # Do IP routing serially to avoids problems with Gurobi interfering with
    # itself.
    # for m in maps
    #     iproute(m)
    # end

    # Just return the metadata dicts. Should have time, memory-allocations,
    # and objective values stored.
    return [m.metadata for m in maps]
end
