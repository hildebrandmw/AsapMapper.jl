#=
A collection of functions to manage results from experiments.

Idea is to do the following:

    - Categorize results by application. (Can either do application or 
        architecture. Since for now I will be generally comparing how 
        applications differ based on architecture, it makes more sense to me to
        collect results by application.). This will form a top level directory.
    - Further categorize by architecture. May split by architecture function.
=#

function save(d::Dict)
    # Get the application name and architecture constructor name from the 
    # dictionary. 
    app  = d["meta"]["app_name"]
    arch = strip_asap.(d["meta"]["architecture"])
    # Check to see if a directory for this exists yet.
    # Categorize first by application, then by architecture.
    savedir = joinpath(RESULTS_DIR, app, arch)
    !ispath(savedir) && mkpath(savedir)

    # Get the filename for the placement.
    name = makename(d)
    f = GZip.open(joinpath(savedir, name), "w")
    JSON.print(f, d, 2)
    close(f)
end

function makename(d::Dict)
    basename = join(strip_asap.(string.(d["meta"]["architecture_args"])),"_")
    extension = ".json.gz"
    return basename * extension
end

strip_asap(str::String) = replace(str, r"^AsapMapper\.", "")

function rmresults(filter, dry = false)
    for (root, ~, files) in walkdir(RESULTS_DIR), file in files
        filepath = joinpath(root, file)
        # Open the file
        try
            f = GZip.open(filepath, "r")
            j = JSON.parse(f)
            close(f)
            if filter(j)
                print_with_color(:yellow, "Deleting: ", filepath, "\n")
                if !dry
                    rm(filepath)
               end
           end
        catch
            print_with_color(:red, "Error opening: ", filepath, "\n")
        end
    end
end
