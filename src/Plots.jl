using StatPlots
gr()
using GZip, JSON

# Helpful Filter Functiong
isapp(d, app)   = d["meta"]["taskgraph"] == app
isnlinks(d, n)  = d["meta"]["architecture_args"][1] == n
ismode(d, mode) = d["meta"]["architecture_args"][2] == "AsapMapper.$mode"

function data_lt(a,b)
    if a["meta"]["architecture_args"][2] < b["meta"]["architecture_args"][2]
        return true
    elseif a["meta"]["architecture_args"][2] == b["meta"]["architecture_args"][2]
        return a["meta"]["architecture_args"][1] < b["meta"]["architecture_args"][1]
    end
    return false
end

function plot_results(filter, field)
    dicts = [] 
    for file in readdir(joinpath(PKGDIR, "results"))
        f = GZip.open(joinpath(PKGDIR, "results", file), "r")
        d = JSON.parse(f)
        close(f)
        if filter(d)
            push!(dicts, d)
        end
    end

    sort!(dicts, lt=data_lt)
    # Plot all the dictionaries
    datasets = []
    series   = String[]
    for d in dicts
        data = [i[field] for i in d["data"]]
        push!(datasets, data)
        # Construct the series name for the set
        arch_type = string(split(d["meta"]["architecture_args"][2], ".")[end])
        num_links = d["meta"]["architecture_args"][1]
        series_name = "$arch_type $num_links"
        push!(series, series_name)
    end
    # Convert the array of arrays into a 2D array
    println(series)
    boxplot(1:length(datasets), datasets,label = series)
end
