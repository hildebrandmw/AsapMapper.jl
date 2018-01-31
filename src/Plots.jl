using StatPlots
gr()
#pyplot()
using GZip, JSON

# Helpful Filter Functiong
isapp(d, app)   = d["meta"]["taskgraph"] == app
isnlinks(d, n)  = d["meta"]["architecture_args"][1] == n
ismode(d, mode) = d["meta"]["architecture_args"][2] == "AsapMapper.$mode"

function make_print_name(d::Dict)
    arch  = strip_asap(d["meta"]["architecture"])
    arch_args = d["meta"]["architecture_args"]
    # Gather the arguments that are strings
    string_args = [i for i in arch_args if typeof(i) <: String]
    non_string_args = [i for i in arch_args if !(typeof(i) <: String)]
    # Concatenate the two together
    ordered             = vcat(string_args, non_string_args)
    arch_arg_strings    = strip_asap.(string.(ordered))
    arch_args           = join(arch_arg_strings, "_")
    name                = join((arch, arch_args), " ")
    return name
end

function data_lt(a,b)
    a_name = make_print_name(a)
    b_name = make_print_name(b)
    return a_name < b_name
end

function plot_results(filter, field, legend = :topright)
    dicts = [] 
    # Walk through all results files, reading the dictionary. Apply the filter
    # to the dictionary. If it passes, add the dictionary to the `dicts` array
    # for downstream plotting.
    for (root, ~, files) in walkdir(RESULTS_DIR), file in files
        filepath = joinpath(root, file)
        try
            f = GZip.open(filepath, "r")
            j = JSON.parse(f)
            close(f)
            if filter(j)
                push!(dicts, j)
                println("Using: ", filepath)
            end
        catch
            print_with_color(:red, "Error opening: ", filepath, "\n")
        end
    end

    sort!(dicts, lt=data_lt)
    # Plot all the dictionaries
    datasets = []
    series   = String[]
    first = true
    for (i,d) in enumerate(dicts)
        data = [i[field] for i in d["data"]]
        push!(datasets, data)
        # Construct the series name for the set
        series_name = make_print_name(d)
        push!(series, series_name)
    end
    # Convert the array of arrays into a 2D array
    println(series)
    boxplot(1:length(datasets), datasets, 
            label = series,
            legendfont = font(4, "Courier"),
            legend = legend,
           )
end
