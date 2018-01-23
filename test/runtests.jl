using AsapMapper
using Base.Test

macro tc(e)
    return quote
        s = true
        try
            $(esc(e))
        catch err
            print_with_color(:red,err,"\n")
            s = false
        end
        @test s
    end
end

@testset "Testing Whole Flow" begin
    # Build Architecture
    arch = AsapMapper.build_asap4(4, AsapMapper.KCStandard)
    # Create Taskgraph Constructor
    sdc = AsapMapper.CachedSimDump("alexnet")
    taskgraph = AsapMapper.build_taskgraph(sdc)
    taskgraph = AsapMapper.apply_transforms(taskgraph, sdc)

    local m
    @tc m = AsapMapper.NewMap(arch,taskgraph)
    # Placement
    @tc m = AsapMapper.place(m, move_attempts = 10000)
    # Route
    @tc m = AsapMapper.route(m)
end
