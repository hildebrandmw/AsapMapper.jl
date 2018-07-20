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
