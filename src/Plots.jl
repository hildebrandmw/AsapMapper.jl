using StatPlots
gr()
#pyplot()
using GZip, JSON

# Helpful Filter Functiong
isapp(d, app)   = d["meta"]["app_name"] == app
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
        catch e
            @warn """
                Error opening $filepath

                $e
                """
        end
    end

    sort!(dicts, lt=data_lt)
    # Plot all the dictionaries
    datasets = []
    series   = String[]
    first = true
    for (i,d) in enumerate(dicts)
        data = [minimum(j[field] for j in i["results"]) for i in d["data"]]
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

################################################################################
# Post routing plotting.
################################################################################

function plot_route(m, spacing, b)
    # spacing = separation distance between tiles
    # b = length of a tile

    a = m.architecture # get the architecture to index the path
    edges = m.mapping.edges # includes edges from taskgraph

    p = Plots.plot(legend = :none)
    draw_tiles(a, spacing, b) # plot all the tiles in the architecture

    bigx = Vector{Array{Float64,1}}() # preallocate arrays to store global ports
    bigy = Vector{Array{Float64,1}}()
    sym = Symbol[]

    count = 0
    for edge in edges
        x = Float64[]
        y = Float64[]

        symbol_count = 0
        for port in edge.path
            address = port.path.address

            x_offset = address.addr[2]*(spacing+b)
            y_offset = address.addr[1]*(spacing+b) # apply spacing and b offsets
            if isglobalport(port)
                x_offset += a[port].metadata["x"]*b # apply metadata offsets
                y_offset += a[port].metadata["y"]*b
                push!(x, x_offset) # push into local edge array
                push!(y, y_offset)
                count += 1
                symbol_count += 1
            end
        end

        # sort the arrows distances according to num hops
        if symbol_count == 2
            push!(sym,:blue)
        elseif symbol_count >= 3 && symbol_count <= 5
            push!(sym,:black)
        else
            push!(sym,:red)
        end
        push!(bigx,x) # push local edge arrays into global array
        push!(bigy,y)
    end

    # I'm not sure why this has to be defined for this to work, but apparently
    # it does.
    #
    # Using "sym" as a column vector does not apply colors correctly, and
    # transpose does not work because "transpose" is not defined for symbols.
    #
    # We could overwrite the base "transpose" as "Base.transpose(s::Symbol) = s"
    # but this is gross, so we do this.
    linecolor = reshape(sym, (1,:))

    Plots.plot!(bigx, bigy, 
                linecolor = linecolor,
                linewidth = 1,
                arrow = arrow(b/30,b/30),
                yflip = true,
               )

    gui()
    #savefig("test.png")
end

function draw_tiles(arch, spacing, b)

    x = Array{Float64,1}()
    y = Array{Float64,1}()

    for key in keys(arch.children)
        push!(x,key.addr[2]*(spacing+b))
        push!(y,key.addr[1]*(spacing+b))
    end # iterate through the children in TopLevel to obtain all the addresses

    draw_square(x, y, b) # call function to draw shape for the tile

end

function draw_square(x, y, b)

    x1 = zeros(Float64, 2, length(x)*4) # 2 dimension arrays used for plotting squares
    y1 = zeros(Float64, 2, length(y)*4)

    for i = 1:length(x)

        x1[:,(i-1)*4+1] = [x[i],x[i]+b]
        x1[:,(i-1)*4+2] = [x[i]+b,x[i]+b]
        x1[:,(i-1)*4+3] = [x[i]+b,x[i]]
        x1[:,(i-1)*4+4] = [x[i],x[i]]

        y1[:,(i-1)*4+1] = [y[i],y[i]]
        y1[:,(i-1)*4+2] = [y[i],y[i]+b]
        y1[:,(i-1)*4+3] = [y[i]+b,y[i]+b]
        y1[:,(i-1)*4+4] = [y[i]+b,y[i]]

    end
    Plots.plot!(x1, y1, color = :black, linewidth = 1)

end
