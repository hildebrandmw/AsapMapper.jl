# Hack to make the AsapMapper directory findable.
push!(LOAD_PATH, @__DIR__)
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

#using ArgParse
using AsapMapper
using Mapper2

function print_help()
    print("""
          usage: mapper.jl [-h] architecture input_file output_file

          positional arguments:
            architecture:   The architecture to map to. Can be `asap3` or `asap4`.
            input_file:     Path to the input JSON file.
            output_file:    Path tot the output JSON file.
          """)
end

function main()
    #parse_commandline()
    for arg in ARGS
        if arg == "-h"
            print_help()
            return
        end
    end

    architecture = ARGS[1]
    input_file   = ARGS[2]
    output_file  = ARGS[3]

    AsapMapper.place_and_route(architecture, input_file, output_file)
end

main()
