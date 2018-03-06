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

    @testset "Testing Name Creation" begin
        db = "test.jld2"
        create_name = AsapMapper.create_name
        @test create_name("test", db) = "test"
        @test create_name("test/many/paths", db) == "test/many/paths"

        # Add some paths to the database file for name conflict detection
        # Final structure:
        #=
        |- tony
        |- test
            |--- a
            |--- a_10
            |--- a_bad
            |--- b
                 |-- ex_1
                 |-- ex_2

        =#
            
        jldopen(db, "a+") do file
            JLD2.Group(file, "tony")
            JLD2.Group(file, "test/b/ex_1")
            JLD2.Group(file, "test/b/ex_2")
            JLD2.Group(file, "test/a")
            JLD2.Group(file, "test/a_10")
            JLD2.Group(file, "test/a_bad")
        end

        @test create_name("bob", db) == "bob"
        @test create_name("test", db) == "test_1"
        @test create_name("test/a", db) == "test/a_11"
        @test create_name("test/a_bad", db) == "test/a_bad_1"
        @test create_name("test/b/ex") == "test/b/ex"
        @test create_name("test/b/nothing") == "test/b/nothing"

        # Cleanup
        rm(db)
    end
end
