@testset "Testing Database" begin
    @testset "Testing Suffix" begin
        d = ["hello", "bad", "nothing", "blank"]
        @test AsapMapper.append_suffix(d, "hello") == "hello_1"
        d = ["bad", "nothing", "blank"]
        @test AsapMapper.append_suffix(d, "hello") == "hello_1"
        d = ["hello", "hello_2", "hello_10", "bob"]
        @test AsapMapper.append_suffix(d, "hello") == "hello_11"
        d = ["hello", "hello_2", "hello_pathological", "bob"]
        @test AsapMapper.append_suffix(d, "hello") == "hello_3"
    end
end
