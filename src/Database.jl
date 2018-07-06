# Path to where the database of Mappings lives.
taskgraphdb() = joinpath(DBDIR, "taskgraphs.jdb")

# Path to the file that generates taskgraphs.
taskgraph_generator() = joinpath(PKGDIR, "..", "..", "ProcArraySim", 
                                 "Asap3", "Mapping_Tests", "python", 
                                 "GenMappingFile.py")

function loadtaskgraph(app, args)
    # Initialize the database if it hasn't been created yet.
    if ispath(taskgraphdb())
        db = JuliaDB.load(taskgraphdb())
    else
        db = getmapping(app, args)
        # Save this as the base DB
        JuliaDB.save(db, taskgraphdb())
    end

    # Check if this application is in the database by filtering with the
    # arguments.
    filtered_data = filter(x -> x[:app] == app && argfilter(x, args), db)

    # Check if this application exists in the database. If it doesn't, request
    # an input file and merge it with the existing database.
    if length(filtered_data) == 0
        println("Getting New Data")
        new_data = getmapping(app, args)
        db = supermerge(db, new_data)
        # Save the modified changes.
        JuliaDB.save(db, taskgraphdb())

        # Set the newly generated data as the filtered data
        filtered_data = new_data
    end

    # Do a length check.
    # TODO: Return a more helpful error message if multiple matches are found.
    if length(filtered_data) > 1
        error()
    else
        return first(select(filtered_data, :mapper_in))
    end
end


function argfilter(x, args)
    for arg in args
        x[dbkey(arg)] == dbvalue(arg) || return false
    end
    return true
end

"""
    getmapping(app, args)

Launch the Mapping File generator for the app and the given arguments.
Return a Table with the arguments and parsed mapper_in.json.

Args may either be:
* A single string: entry in database will be marked as `true`.
* A Pair{String,Any}: entry in data base will have a column name for the
    first item in the pair and value taken as the second item.
"""
function getmapping(app, args)
    run_mapper_input_generator(app, args)

    # Make sure that the "mapper_in.json" file exists.
    mapper_file = "mapper_in.json"
    @assert ispath(mapper_file)

    # Parse the input file and delete it.
    mapper_in = open(mapper_file) do f
        JSON.parse(f)
    end
    rm(mapper_file)

    # Create a JuliaDB table for this mapping.
    data::Vector{Any} = [[dbvalue(arg)] for arg in args]
    columns = [Symbol(dbkey(arg)) for arg in args]

    # Add columns/data for the application and for the parsed JSON input file.
    push!(data, [app])
    push!(columns, :app)

    push!(data, [mapper_in])
    push!(columns, :mapper_in)

    return table(data..., names=columns)
end

function run_mapper_input_generator(app, args)
    argstrings::Vector{String} = String[]
    for arg in args
        append!(argstrings, argstring(arg))
    end
    # Run the Mapping Generator. 
    run(`python3 $(taskgraph_generator()) $app $argstrings`)
end

argstring(x::Pair) = ["$(first(x))", "$(last(x))"]
argstring(x) = ["$x"]

dbkey(x::Pair) = Symbol(first(x))
dbvalue(x::Pair) = last(x)
dbkey(x) = Symbol(x)
dbvalue(x) = true


# Super merge function for JuliaDB Tables. Since we don't know beforehand what
# exactly all of the columns of a Table will be needed for to hold all possible
# parameters, I want a merge function that, if trying to merge two tables
# with different columns, will automatically extend both tables to have the 
# union of the columns, add NA values to these extended columns, and then do
# a normal merge.
#
# This is probably not how databases are supposed to be used, but all of the
# data manipulation going on here should be quite small compared to normal 
# database sizes so I'm not too worried about things getting horribly slow.
function supermerge(A :: NextTable, B :: NextTable)
    # Get the column names for the two tables.
    Acolumns = keys(columns(A)) 
    Bcolumns = keys(columns(B))

    # Get the columns that have to be added to each table so they will both have
    # the same column names.
    new_Acolumns = setdiff(Bcolumns, Acolumns)
    new_Bcolumns = setdiff(Acolumns, Bcolumns)

    # Add the new columns if needed.
    A′ = addcolumns(A, new_Acolumns)
    B′ = addcolumns(B, new_Bcolumns)
    return merge(A′, B′)
end

# Add the given columsn to table `t`. Fill the rows for these columns with NA.
function addcolumns(t :: NextTable, newcols :: Vector{Symbol})
    # If no new columns are being added, don't do anything.
    length(newcols) == 0 && return t

    # Build a Vector{Pair{Symbol,Any}} to splat into the "pushcol" function of
    # JuliaDB
    cols = [col => fill(NA, length(t)) for col in newcols]
    return pushcol(t, cols...)
end


