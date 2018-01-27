# Hack to make the AsapMapper directory findable.
push!(LOAD_PATH, joinpath(pwd(), ".."))
push!(LOAD_PATH, joinpath(pwd(), "..", ".."))

using ArgParse
using AsapMapper

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table s begin
        "architecture"
            help = "Name of the architecture to map to. Can be `asap3` or `asap4`."
            arg_type = String
            required = true
        "input_file"
            help = "Path to the input `profile.bin`."
            arg_type = String
            required = true
        "output_file"
            help = "Path and name of the desired output file."
            arg_type = String
            required = true
    end
    return parse_args(s)
end

function main()
    parsed_args = parse_commandline()

    architecture = parsed_args["architecture"]
    input_file   = parsed_args["input_file"]
    output_file  = parsed_args["output_file"]

    AsapMapper.place_and_route(architecture, input_file, output_file)
end

main()
