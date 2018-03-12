# Make sure these build and run without errors
@testset "Testing ASAP 4" begin
    # Build Architecture
    input_file = joinpath(@__DIR__, "mapper_in_asap4.json")
    c = AsapMapper.PMConstructor("asap4",input_file)
    m = AsapMapper.build_map(c)
    # Placement
    m = AsapMapper.place(m, move_attempts = 50000)
    # Route
    m = AsapMapper.route(m)
    Mapper2.MapperCore.report_routing_stats(m)

    AsapMapper.dump_map(m, "mapper_out.json")
    rm("mapper_out.json")
end

@testset "Testing ASAP 3" begin
    # Create Taskgraph Constructor
    input_file = joinpath(@__DIR__, "mapper_in_asap3.json")
    c = AsapMapper.PMConstructor("asap3",input_file)
    m = AsapMapper.build_map(c)

    # Placement
    m = AsapMapper.place(m, move_attempts = 50000)
    # Route
    m = AsapMapper.route(m)
    Mapper2.MapperCore.report_routing_stats(m)

    AsapMapper.dump_map(m, "mapper_out.json")
    rm("mapper_out.json")
end
