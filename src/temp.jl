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
#=
Dumps a JSON data structure recording the basic mapping details for the Project
Manager to read to do with whatever it wants.
=#
function dump_map(m::Map, filename::String)
    # Build a dictionary for json serialize
    jsn = Dict{String,Any}() 
    jsn["nodes"] = sim_create_node_dict(m.mapping)
    jsn["edges"] = sim_create_edge_vec(m.mapping)
    # Open up the file to save
    f = open(filename, "w")
    # Print to JSON with pretty printing.
    print(f, json(jsn, 2))
    close(f)
end

function sim_create_node_dict(m::Mapping)
    node_dict = Dict{String, Any}()
    # Iterate through the dictionary in the mapping nodes
    for (name, nodemap) in m.nodes
        # Create the dictionary for this node.
        dict = Dict{String,Any}()
        dict["address"] = nodemap.path.address.addr
        node_dict[name] = dict
    end
    return node_dict
end

function sim_create_edge_vec(m::Mapping)
    path_vec = Any[]
    for (i, edgemap) in enumerate(m.edges)
        d = Dict{String,Any}()
        path = Any[]
        for p in edgemap.path
            inner_dict = Dict(
                "type" => typestring(p),
                "path" => string(p)
             )
            push!(path, inner_dict)
        end
        d["path"]           = path
        d["edge_number"]    = i
        # Requires "sources" and "sinks" to be in the mapping metadata.
        d["source"] = first(edgemap.metadata["sources"])
        d["sink"]   = first(edgemap.metadata["sinks"])

        @assert length(edgemap.metadata["sources"]) == 1
        @assert length(edgemap.metadata["sinks"]) == 1
        push!(path_vec, d)
    end
    return path_vec
end
################################################################################
# Helper functions
################################################################################
function create_node_dict(m::Mapping)
    node_dict = Dict{String, Any}()
    # Iterate through the dictionary in the mapping nodes
    for (name, nodemap) in m.nodes
        # Create the dictionary for this node.
        dict = Dict{String,Any}()
        dict["address"]     = nodemap.path.address.I
        dict["component"]   = join(nodemap.path.path.path, ".")
        node_dict[name] = dict
    end
    return node_dict
end

function read_node_dict(m::Mapping, d)
    for (name, value) in d
        # Get the nodemap for this node name
        nodemap = m.nodes[name]
        # Create the address data type
        address = CartesianIndex(Tuple(value["address"]))
        component = ComponentPath(value["component"])
        nodemap.path     = AddressPath(address, component)
    end
    return nothing
end

function create_edge_vec(m::Mapping)
    path_vec = Any[]
    for (i, edgemap) in enumerate(m.edges)
        d = Dict{String,Any}()
        path = Any[]
        for p in edgemap.path
            inner_dict = Dict(
                "type" => typestring(p),
                "path" => string(p)
             )
            push!(path, inner_dict)
        end
        d["path"]           = path
        d["edge_number"]    = i
        push!(path_vec, d)
    end
    return path_vec
end

function read_edge_vec(m::Mapping, path_vec)
    edgemap_vec = Any[]
    for edge in path_vec
        path = Any[]
        for p in edge["path"]
            # split up the string on dots
            split_str = split(p["path"], ".")
            cartesian = first(split_str)

            # Get the coordinates of the cartesian item
            coord_strings = matchall(r"(\d+)(?=[,\)])", cartesian)
            # Build the CartesianIndex
            address = CartesianIndex(parse.(Int64, coord_strings)...)

            if(p["type"] == "Port")
                x = PortPath(split_str[2:end], address)
            elseif(p["type"] == "Link")
                x = LinkPath(split_str[2:end], address)
            end
            push!(path,x) # build the path
        end
        edgemap = EdgeMap(path)
        push!(edgemap_vec, edgemap)
    end
    m.edges = edgemap_vec
    return nothing

end
