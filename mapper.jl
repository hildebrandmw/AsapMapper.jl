# Hack to make the AsapMapper directory findable.
push!(LOAD_PATH, @__DIR__)
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

# Check if running in parallel mode. If not, just use the normal "using" import
# to make Mapper packages visible. Otherwise, use @everywhere to ensure all
# workers see the Mapper packages.
if nprocs() == 1
    using AsapMapper
    using Mapper2
else
    println("Starting Mapper in parallel mode with $(nworkers()) workers")
    @everywhere using AsapMapper
    @everywhere using Mapper2
end

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

# NOTE: This is probably no-longer needed.
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
#if length(ARGS) > 0
#    main()
#end
