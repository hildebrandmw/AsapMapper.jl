# Hack to make the AsapMapper directory findable.
push!(LOAD_PATH, @__DIR__)
push!(LOAD_PATH, joinpath(@__DIR__, ".."))

#using ArgParse
using AsapMapper
using Mapper2

function print_help()
    print("""
          usage: mapper.jl [-h] architecture input_file output_file
                 mapper.jl -p pipe

          flags:
            -p: Listen on a named pipe. Keeps Julia alive over multiple mappings.

          positional arguments - usage 1:
            architecture:   The architecture to map to. Can be `asap3` or `asap4`.
            input_file:     Path to the input JSON file.
            output_file:    Path to the output JSON file.

          positional arguments - usage 2:
            pipe: The name of the pipe used for communication.
          """)
end

function multimap(pipe_name)
    try
        pipe = connect(pipe_name)
    catch
        error("Cannot connect to named pipe: $pipe_name.")
    end
    while true
        println("Listening")
        args = readline(pipe)
        # Exit condition
        if args == "exit"
            println(pipe, "goodbye")
            close(pipe)
            return
        end
        # split the args based on spaces.
        split_args = split(args, " ")
        if length(split_args) != 3
            println(pipe, "rejected")
        else
            println(pipe, "accepted")
            try
                architecture    = split_args[1]
                infile          = split_args[2]
                outfile         = split_args[3]
                AsapMapper.place_and_route(architecture, infile, outfile)
                println(pipe, "success")
            catch err
                println(pipe, "error")
            end
        end

    end
end

function main()
    #parse_commandline()
    for arg in ARGS
        if arg == "-h"
            print_help()
            return
        end
    end

    # Check to see if requesting to run in continuous mode
    if first(ARGS) == "-p"
        println("Working in pipe mode")
        pipe_name = ARGS[2]
        multimap(pipe_name)
        return
    end

    architecture = ARGS[1]
    input_file   = ARGS[2]
    output_file  = ARGS[3]

    AsapMapper.place_and_route(architecture, input_file, output_file)
end

main()
