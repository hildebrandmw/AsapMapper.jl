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

          If no arguments are given, running this script only configures the
          Julia run-time to be aware of the AsapMapper and Mapper2 packages.
          """)
end

function main()
    # print help message.
    for arg in ARGS
        if arg == "-h"
            print_help()
            return nothing
        end
    end

    # unpack arguments.
    input_file   = ARGS[1]
    output_file  = ARGS[2]

    AsapMapper.place_and_route(input_file, output_file)
    return nothing
end

# Only run the main function if arguments are provided.
if length(ARGS) > 0
    main()
end
