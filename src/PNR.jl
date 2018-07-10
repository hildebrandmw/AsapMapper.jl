################################################################################
# Custom combined place-and-route
################################################################################
function lowtemp_pnr(m::Map, iterations; place_kwargs...)
    # Do a more low-level treatment of the place and route routine - acquire
    # a SAStruct and use it directly. If routing fails, do a low-temp placement
    # to perturb the location of processors and try routing again.
    #
    # Repeat for the specified number of iterations.
    pstruct = SAStruct(m)
    # First placement - capture the final state.
    state = SA.place(pstruct; place_kwargs...)
    # Record the placement back to the Map.
    Mapper2.SA.record(m, pstruct)

    # Try routing
    m = route(m)
    # If it passes a routing check, return.
    check_routing(m, true) && return m

    @info """
        Initial attempt at routing failed. Trying again.
        """

    for i in 1:iterations
        # Low temperature perturbation.
        SA.place(pstruct;
                 place_kwargs...,
                 supplied_state = state,
                )
        SA.record(m, pstruct)
        # Try routing again.
        m = route(m);
        check_routing(m, true) && return m
    end
    @error "Mapping Failed!"

    return m
end

function basic_place(arch::TopLevel, taskgraph::Taskgraph)
    m = NewMap(arch, taskgraph)
    place(m)
    MapperCore.save(m, "temp.jls")
end

function basic_route(arch::TopLevel, taskgraph::Taskgraph)
    m = NewMap(arch, taskgraph)
    MapperCore.load(m, "temp.jls")
    route(m)
    return m.mapping
end


################################################################################
# Custom Placement Functions
################################################################################
function shotgun_placement(arch     ::TopLevel,
                           taskgraph::Taskgraph;
                           nplacements::Int = 1,
                           nsamples::Int    = 1,
                           kwargs...)

    @info "Total Placements: $(nplacements)"
    # closure for parallel placement 
    p(x) = low_temp_placement(arch, taskgraph, x;
                              nsamples = nsamples,
                              kwargs...)

    # Parallelize placements
    pmap(x -> p(x), 1:nplacements)
end

function low_temp_placement(arch            ::TopLevel,
                            taskgraph       ::Taskgraph,
                            iteration_number::Int;
                            nsamples = 1,
                            place_kwargs...)

    @info "Sublacement iteration $iteration_number"
    # Construct a new Map object
    m = NewMap(arch, taskgraph)
    # Get the placement structure
    pstruct = SAStruct(m)
    # Scope "state" out of the loop to avoid renaming.
    local state
    for i = 1:nsamples
        if i == 1
            state = SA.place(pstruct; place_kwargs...)
        else
            SA.place(pstruct;
                    place_kwargs...,
                    supplied_state = state,
                    warmer = SA.TrueSAWarm()
                )
        end
        Mapper2.SA.record(m, pstruct)

        # serialize to temp/ dir so routing can find it.
        savename    = "$(iteration_number)_$(i)"
        save_path   = joinpath(PKGDIR, "temp", savename)
        Mapper2.MapperCore.save(m, save_path)
    end
end

################################################################################
# Custom Routing Functions
################################################################################
function low_temp_route(arch, taskgraph;
                        nplacements::Int    = 1,
                        nsamples::Int       = 1,
                        route_kwargs...)

    # create closure for parallelism
    r(x) = multisample_routing(arch, taskgraph, x, nsamples)

    results = pmap(x -> r(x), 1:nplacements)
    return results
end

function multisample_routing(arch, taskgraph, iteration_number, nsamples)
    results = Mapping[]
    
    m = NewMap(arch, taskgraph)
    for i in 1:nsamples
        # load serialized placement mapping
        load_path = joinpath(PKGDIR, "temp", "$(iteration_number)_$(i)")
        Mapper2.MapperCore.load(m, load_path)
        try
            m = route(m)
        end
        push!(results, m.mapping)
    end
    return results
end
