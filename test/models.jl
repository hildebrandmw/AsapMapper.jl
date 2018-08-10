# Make sure these build and run without errors
@testset "Testing ASAP 3" begin
    # Build Architecture
    input_file = joinpath(@__DIR__, "mapper_in.json")
    c = AsapMapper.PMConstructor(input_file)
    m = AsapMapper.build_map(c)
    # Placement
    m = AsapMapper.asap_pnr(m)
    AsapMapper.Mapper2.MapperCore.report_routing_stats(m)

    AsapMapper.dump_map(m, "mapper_out.json")
    rm("mapper_out.json")
end

# Make sure these build and run without errors
@testset "Testing ASAP 3 profiled" begin
    # Build Architecture
    input_file = joinpath(@__DIR__, "mapper_in.json")
    c = AsapMapper.PMConstructor(input_file, (use_profiled_links = true,))
    m = AsapMapper.build_map(c)
    # Placement
    m = AsapMapper.asap_pnr(m)
    AsapMapper.Mapper2.MapperCore.report_routing_stats(m)

    AsapMapper.dump_map(m, "mapper_out.json")
    rm("mapper_out.json")
end

@testset "Testing Asap3 Hexagonal" begin
    input_file = joinpath(@__DIR__, "mapper_in.json")
    c = AsapMapper.PMConstructor(
        input_file,
        (architecture = () -> asap3(Hexagonal(2, 1)),)
    )

    m = AsapMapper.build_map(c)
    m = AsapMapper.asap_pnr(m)
    AsapMapper.Mapper2.MapperCore.report_routing_stats(m)
end

@testset "Testing Asap3 Hexagonal Profiled" begin
    input_file = joinpath(@__DIR__, "mapper_in.json")
    c = AsapMapper.PMConstructor(
        input_file,
        (architecture = () -> asap3(Hexagonal(2, 1)), use_profiled_links = true)
    )

    m = AsapMapper.build_map(c)
    m = AsapMapper.asap_pnr(m)
    AsapMapper.Mapper2.MapperCore.report_routing_stats(m)
end
