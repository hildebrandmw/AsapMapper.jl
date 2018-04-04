struct PlaceParameters <: Experiment
    arch        ::FunctionCall
    app         ::FunctionCall
    place       ::Vector{FunctionCall}
    route       ::FunctionCall
end

struct ParametersResult{T} <: Result
    data::Vector{SimpleResult{T}}
end

dirstring(::PlaceParameters) = "place_parameters"

function run(ex::PlaceParameters, dir::String = results_dir())
    dir = augment(dir, ex)

    arch = call(ex.arch)
    app  = call(ex.app)
    result = map(ex.place) do pr
        call(pr, arch, app)
        mapping = call(ex.route, arch, app)
        return SimpleResult(ex.arch, ex.app, mapping)
    end
    save(ParametersResult(result), dir)
    save(ex, dir)
end

function testrun()
    path = "/Users/mark/.julia/v0.6/AsapMapper/apps/asap3/mapper_in_2.json"
    arch = FunctionCall(asap3, (2, KCStandard))
    app  = FunctionCall(build_taskgraph, (PMConstructor(path),))

    moves   = [10000, 20000]
    cooling = [0.9, 0.8]

    pnr_base_kwargs = Dict{Symbol,Any}(
        :nplacements => 2,
        :nsample     => 2,
    )

    pnr_kwargs = map(zip(moves, cooling)) do x
        m = x[1]
        c = x[2]

        return merge(pnr_base_kwargs, Dict{Symbol,Any}(
            :move_attempts  => m,
            :cooler         => SA.DefaultSACool(c),
           ))
    end

    place = [FunctionCall(shotgun_placement, (), i) for i in pnr_kwargs]
    route = FunctionCall(low_temp_route, (), pnr_base_kwargs)

    expr = PlaceParameters(arch, app, place, route)
    run(expr)
end
