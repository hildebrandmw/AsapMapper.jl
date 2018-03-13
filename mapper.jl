# Hack to make the AsapMapper directory findable.
push!(LOAD_PATH, @__DIR__)
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

using AsapMapper
using Mapper2

function print_help()
    print("""
          usage: mapper.jl [-h] architecture input_file output_file
                 mapper.jl 

          positional arguments:
            architecture:   The architecture to map to. Can be `asap3` or `asap4`.
            input_file:     Path to the input JSON file.
            output_file:    Path to the output JSON file.

          If no arguemnts are given, main routine aborts early - just imports 
          the AsapMapper and Mapper packages.
          """)
end

function main()
    # Short abort
    length(ARGS) == 0 && return nothing
    # print help message.
    for arg in ARGS
        if arg == "-h"
            print_help()
            return nothing
        end
    end

    # unpack arguments.
    architecture = ARGS[1]
    input_file   = ARGS[2]
    output_file  = ARGS[3]

    AsapMapper.place_and_route(architecture, input_file, output_file)
    return nothing
end

# Run the main function.
main()
