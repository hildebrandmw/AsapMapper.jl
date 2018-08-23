@testset "Testing Asap2" begin
    input_file = joinpath(@__DIR__, "aes.json")
    c = AsapMapper.PMConstructor(
        input_file,
        (
            architecture = "Array_Asap2",
            ruleset = AsapMapper.Asap2(),
        )
    )

    m = AsapMapper.build_map(c)
    m = AsapMapper.asap_pnr(m, move_attempts = 2000)
    AsapMapper.Mapper2.MapperCore.report_routing_stats(m)
end
