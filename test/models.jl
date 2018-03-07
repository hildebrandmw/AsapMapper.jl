@testset "Testing Port Offsets" begin
    archs = []
    push!(archs, AsapMapper.asap3(2, AsapMapper.KCStandard))
    push!(archs, AsapMapper.asap3(3, AsapMapper.KCStandard))
    push!(archs, AsapMapper.asap4(2, AsapMapper.KCStandard))
    push!(archs, AsapMapper.asap4(3, AsapMapper.KCStandard))
    for arch in archs
        total_count = 0
        pass_count = 0
        for c in values(arch.children)
            for p in values(c.ports)
                total_count += 2
                if haskey(p.metadata, "x")
                    pass_count += 1
                end
                if haskey(p.metadata, "y")
                    pass_count += 1
                end
            end
        end
        @test pass_count == total_count
    end
end

# Makes sure these build and run without errors

@testset "Testing ASAP 4" begin
    # Build Architecture
    arch = AsapMapper.asap4(2, AsapMapper.KCStandard)
    # Create Taskgraph Constructor
    sdc = AsapMapper.CachedSimDump("alexnet")
    taskgraph = AsapMapper.build_taskgraph(sdc)
    taskgraph = AsapMapper.apply_transforms(taskgraph, sdc)

    m = AsapMapper.NewMap(arch,taskgraph)
    # Placement
    m = AsapMapper.place(m, move_attempts = 10000)
    # Route
    m = AsapMapper.route(m)
    Mapper2.MapperCore.report_routing_stats(m)
end

@testset "Testing ASAP 3" begin
    # Build Architecture
    arch = AsapMapper.asap3(2, AsapMapper.KCStandard)
    # Create Taskgraph Constructor
    sdc = AsapMapper.CachedSimDump("fft")
    taskgraph = AsapMapper.build_taskgraph(sdc)
    taskgraph = AsapMapper.apply_transforms(taskgraph, sdc)

    m = AsapMapper.NewMap(arch,taskgraph)
    # Placement
    m = AsapMapper.place(m, move_attempts = 10000)
    # Route
    m = AsapMapper.route(m)
    Mapper2.MapperCore.report_routing_stats(m)
end
