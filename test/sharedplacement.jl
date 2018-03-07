function testrun(dir)
    arch        = asap4 
    arch_args   = [(2,KCStandard),
                   (3,KCStandard)]
    arch_kwargs = [Dict{String,Any}(),Dict{String,Any}()]

    app     = FunctionCall(load_taskgraph, ("alexnet",))

    pnr_kwargs = Dict(
        :nplacements => 2,
        :nsamples    => 2
     )
    place   = FunctionCall(AsapMapper.shotgun_placement, (), pnr_kwargs)
    route   = FunctionCall(AsapMapper.low_temp_route, (), pnr_kwargs)

    expr = SharedPlacement(arch, arch_args, arch_kwargs, app, place, route)
    AsapMapper.run(expr, dir)
end

@testset "Testing Shared Placement" begin
    dir = "bubbagump"
    testrun(dir)

    @test ispath("$dir/shared_placement_1")
    @test ispath("$dir/shared_placement_1/data_1.jls.gz")
    @test ispath("$dir/shared_placement_1/data_2.jls.gz")
    @test ispath("$dir/shared_placement_1/expr_1.jls.gz")

    # Try opening up the experiment.
    f = GZip.open("$dir/shared_placement_1/expr_1.jls.gz")
    expr = deserialize(f)
    close(f)

    @test expr.arch == asap4
    @test expr.app.f == load_taskgraph
    @test expr.app.args == ("alexnet",)

    f = GZip.open("$dir/shared_placement_1/data_2.jls.gz")
    x = deserialize(f)
    close(f)

    m = Mapper2.NewMap(call(x.arch), call(x.app))
    m.mapping = first(first(x.mappings))

    @test Mapper2.check_routing(m)
    Mapper2.MapperCore.report_routing_stats(m)
    rm(dir, recursive = true)
end
