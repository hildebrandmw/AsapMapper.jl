struct SimConstructor{T}
    # String or parsed Json
    source :: T
    options :: NamedTuple
end

SimConstructor(source) = SimConstructor(source, NamedTuple())

function addoptions(s::SimConstructor, d) 
    options = parse_options(s.options)
    @show options
    d["mapper_options"] = options
    return d
end


function parse(s::SimConstructor{T}) where T 
    json_dict = Dict{String,Any}(
        "profile" => deepcopy(s.source),
    )
    return addoptions(s, json_dict)
end

function parse(s::SimConstructor{String})
    profile = open(s.source) do f
        JSON.parse(f)
    end
    json_dict = Dict{String,Any}(
        "profile" => profile,
    )
    return addoptions(s, json_dict)
end

function build_map(sc::SimConstructor)
    json_dict = parse(sc)
    toplevel = build_architecture(sc, json_dict)
    taskgraph = build_taskgraph(sc, json_dict)

    # Get options, do some things
    options = json_dict["mapper_options"]
    rule = getrule(options)

    map = Map(rule, toplevel, taskgraph)
    map.options = options

    return map
end

# Assume a callback is given.
build_architecture(s::SimConstructor, json_dict) = json_dict["mapper_options"][:architecture]()

function build_taskgraph(sc::SimConstructor, json_dict::AbstractDict)
    taskgraph = Taskgraph()
    options = json_dict["mapper_options"]

    parse_input!(sc, taskgraph, json_dict)

    # Run some unpacking transforms on the taskgraph.
    ops = (transform_task_types, compute_edge_metadata, apply_link_weights)
    for op in ops
        taskgraph = op(taskgraph, options)
    end
    return taskgraph
end

function parse_input!(::SimConstructor, taskgraph, json_dict::AbstractDict)
    # Iterate through each node in the dictionary. The keys are the names of
    # the nodes.
    #
    # A second pass will unpack edges.
    for (name, measurements) in json_dict["profile"]
        # Make a metadata dictionary that mimics the structure of what the
        # Project_Manager generates - allowing us to use many of the same passes.
        typestring = titlecase(measurements["Get_Type_String()"], wordsep = isequal('_'))

        metadata = Dict{String,Any}(
            "measurements_dict" => measurements,
            "type" => typestring,
        )
        node = TaskgraphNode(name, metadata = metadata)
        add_node(taskgraph, node)
    end

    # Edges - first pass grabs the explicit edges defined in the profile.
    # Assume all are circuit links.
    #
    # Second pass will unpack any attached memories.
    for node in getnodes(taskgraph)
        # Skip memory nodes, we'll assign those later.
        node.metadata["type"] == "Memory" && continue

        measurements = node.metadata["measurements_dict"]
        # Iterate over output buffers. Must be careful with "nulls"
        for link in get(measurements, "output_buffers", ())
            link == nothing && continue

            reader_core = link["reader_core"]

            # Make a metadata.
            metadata = Dict{String,Any}(
                "pm_class" => "Circuit_Link",
                "measurements_dict" => link,
                "route_link" => true,
                "preserve_dest" => false,
            )
            new_edge = TaskgraphEdge(
                node.name, 
                reader_core, 
                metadata = metadata
            )

            add_edge(taskgraph, new_edge)
        end
    end

    for node in getnodes(taskgraph)
        attached_memory = get(
            node.metadata["measurements_dict"], 
            "attached_memory", 
            nothing
        )
        attached_memory == nothing && continue

        # Create an edge to the memory.

        # Proc -> Memory
        metadata = Dict{String,Any}(
            "pm_class" => "Memory_Request_Link",
            "measurements_dict" => Dict{String,Any}(),
            "route_link" => true,
            "preserve_dest" => false,
        )
        new_edge = TaskgraphEdge(node.name, attached_memory, metadata = metadata)
        add_edge(taskgraph, new_edge)

        # Memory -> Proc
        metadata = Dict{String,Any}(
            "pm_class" => "Memory_Response_Link",
            "measurements_dict" => Dict{String,Any}(),
            "route_link" => true,
            "preserve_dest" => false,
        )
        new_edge = TaskgraphEdge(attached_memory, node.name, metadata = metadata)
        add_edge(taskgraph, new_edge)
    end

    return taskgraph
end
