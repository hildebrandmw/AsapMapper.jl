# Convert a JSON array of run data into a JuliaDB Table
function asdataframe(data :: Vector{<:Any})
    # Create a set of keys for all the runs. Since each run data should be 
    # generated from the same run, all the keys should be the same.
    #
    # Get the first dictionary for the initial keys and do a quick check for
    # this invariant.
    allkeys = sort(collect(keys(first(data))))

    for d in data
        @assert sort(collect(keys(d))) == allkeys
    end

    # Now, gather column data.
    columns = Dict{Symbol,Any}()
    for key in allkeys
        columns[Symbol(key)] = [d[key] for d in data]
    end

    return DataFrame(columns...)
end

# Add an experimental run to the NDSparse dataset
function astable(data :: Dict; kwargs...)
    allkeys = sort(collect(keys(data)))

    columns = []
    for key in allkeys
        # Wrap everything in a single length vector so the constructor for
        # "table" is happy.
        if key == "data"
            push!(columns, [asdataframe(data[key])])
        else
            push!(columns, [data[key]])
        end
    end

    # Get kwargs to columns
    for (k,v) in kwargs
        push!(allkeys, k)
        push!(columns, [v])
    end

    # Create a dataframe
    return table(columns..., names = Symbol.(allkeys))
end

function convert_to_table(data :: Vector{<:Any}; kwargs...)
    # Iterate over each element, converting it to a dataframe. 
    tables = [astable(d; kwargs...) for d in data]

    # Merge all of the data frames together.
    return reduce(merge, tables)
end
