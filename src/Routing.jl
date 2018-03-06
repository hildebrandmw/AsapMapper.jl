function low_temp_route(arch, taskgraph;
                        nplacements::Int    = 1,
                        nsamples::Int       = 1,
                        route_kwargs...)

    # create closure for parallelism
    r(x) = multisample_routing(arch, taskgraph, x, nsamples)

    results = pmap(x -> r(x) for x in 1:nplacements)
    return results
end

function multisample_routing(arch, taskgraph, iteration_number, nsamples)
    results = Mapping[]
    
    m = NewMap(arch, taskgraph)
    for i in 1:nsamples
        # load serialized placement mapping
        load_path = joinpath(PKGDIR, "temp", "$(iter)_$(i)")
        Mapper2.MapType.load(m, load_path)
        try
            m = route(m)
        end
        push!(results, m.mapping)
    end
    return results
end
