function asap4_tests(tests, 
                     strategies, 
                     num_runs,
                     nsamples,
                     taskgraphs::Dict, 
                     place_kwargs::Dict)

    apps = ("alexnet",)
    for A in strategies
        arch = asap4
        for app in apps
            arch_args = [(nl,A) for nl in 2:6]
            taskgraph = taskgraphs[app]
            new_test  = PlacementTest(arch,
                                      arch_args,
                                      string(A),
                                      taskgraph,
                                      place_kwargs,
                                      num_runs,
                                      nsamples,
                                      Dict{String,Any}(),
                                     )
            push!(tests, new_test)
        end
    end
end

function asap3_tests(tests, 
                     strategies, 
                     num_runs,
                     nsamples,
                     taskgraphs::Dict, 
                     place_kwargs::Dict)

    apps    = ("aes", "fft", "sort", "ldpc")
    for (A,app) in Iterators.product(strategies, apps)
        arch = asap3
        # Check architecture variations
        arch_args = [(nlinks,A) for nlinks in 2:6]
        tg   = taskgraphs[app]

        new_test = PlacementTest(arch,
                                 arch_args,
                                 string(A),
                                 tg,
                                 place_kwargs,
                                 num_runs,
                                 nsamples,
                                 Dict{String,Any}(),
                                )

        push!(tests, new_test)
    end
end

function generic1_tests(tests, 
                     strategies, 
                     num_runs,
                     nsamples,
                     taskgraphs::Dict, 
                     place_kwargs::Dict)

    apps    = ("aes", "fft", "sort", "ldpc")
    for (A,app) in Iterators.product(strategies, apps)
        arch = generic
        # Check architecture variations
        arch_args = [(16,16,4,12,A,nl) for nl in 2:4]
        tg   = taskgraphs[app]

        new_test = PlacementTest(arch,
                                 arch_args,
                                 string(A),
                                 tg,
                                 place_kwargs,
                                 num_runs,
                                 nsamples,
                                 Dict{String,Any}(),
                                )

        push!(tests, new_test)
    end
end

function generic2_tests(tests, 
                     strategies, 
                     num_runs,
                     nsamples,
                     taskgraphs::Dict, 
                     place_kwargs::Dict)
    apps    = ("sort",)
    for (A,app) in Iterators.product(strategies, apps)
        arch = generic
        # Check architecture variations
        arch_args = [(10,10,10,0,A,nl) for nl in 2:4]
        tg   = taskgraphs[app]

        new_test = PlacementTest(arch,
                                 arch_args,
                                 string(A),
                                 tg,
                                 place_kwargs,
                                 num_runs,
                                 nsamples,
                                 Dict{String,Any}(),
                                )

        push!(tests, new_test)
    end
end

function asap3_hex_tests(tests, 
                     strategies, 
                     num_runs,
                     taskgraphs::Dict, 
                     place_kwargs::Dict)

    apps    = ("aes", "fft", "sort", "ldpc")
    for (A,app) in Iterators.product(strategies, apps)
        arch = asap3_hex
        # Check architecture variations
        arch_args = [(nlinks,A) for nlinks in 2:4]
        tg   = taskgraphs[app]

        new_test = PlacementTest(arch,
                                 arch_args,
                                 string(A),
                                 tg,
                                 place_kwargs,
                                 num_runs,
                                 Dict{String,Any}(),
                                )

        push!(tests, new_test)
    end
end
