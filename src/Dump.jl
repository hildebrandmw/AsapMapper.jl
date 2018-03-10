function dump_map(m::Map, filename::String)
    jsn = skeleton_dump(m)
    populate_routes!(jsn, m)

    json_dict = Dict("task_structure" => collect(values(jsn)))

    #jsn = Dict(k => dictify(v) for (k,v) in predump)
    f = open(filename, "w")
    print(f, json(json_dict, 2)) 
    close(f)
    return nothing
end

create_dict(d::Dict, k, v) = haskey(d, k) || (d[k] = v())

################################################################################
struct RoutingTuple
    class           ::String
    source_task     ::_name_types
    source_inde     ::_index_types
    dest_tas        ::_name_types
    dest_index      ::_index_types
end

abstract type MapDump end
struct MapDumpNode <: MapDump
    name            ::String
    address         ::Tuple
    leaf_node_dict  ::Dict{String,Any}
end

MapDumpNode(name, addr::Tuple) = MapDumpNode(name, addr, Dict{String,Any}())
MapDumpNode(name, addr::CartesianIndex) = MapDumpNode(name, addr.I, Dict{String,Any}())


struct MapDumpRoute <: MapDump
    network_id      ::Any
    source_task     ::Any
    source_index    ::Any
    dest_task       ::Any
    dest_index      ::Any
    offset_list     ::Vector
end

JSON.lower(m::MapDump) = Dict(string(f) => getfield(m,f) for f in fieldnames(typeof(m)))
JSON.lower(::Missing) = "missing"

"""
    skeleton_dump(m::Map)

Create entries in the final dictionary with just the task-name keys and the
address value populated.
"""
function skeleton_dump(m::Map)
    dict = Dict{String,MapDumpNode}()
    # Iterate through the dictionary in the mapping nodes
    for (name, address_path) in m.mapping.nodes
        node = getnode(m.taskgraph, name)
        get(node.metadata, "nodump", false) && continue
        
        addr = Mapper2.MapperCore.getaddress(address_path)
        addr = addr - CartesianIndex(2,2)

        dumpnode = MapDumpNode(name, addr)
        dict[name] = MapDumpNode(dumpnode)
    end
    return dict
end

function add_route!(n::MapDumpNode, 
                    route, 
                    class::String, 
                    dir::String, 
                    route_field::Symbol)

    leaf_dict = n.leaf_node_dict

    create_dict(leaf_dict, class, Dict{String,Any})
    class_dict = leaf_dict[class]

    create_dict(class_dict, dir, Dict{_index_types,Any}) 
    direction_dict = class_dict[dir]

    index = getfield(route, route_field)
    create_dict(direction_dict, index, Dict{String,Any})
    direction_dict[index] = route
end

function populate_routes!(jsn,m)
    routings = extract_routings(m)
    for (rtuple, route) in routings
        class = rtuple.class
        # Record the source index
        source_task = route.source_task
        source_node = jsn[source_task]

        add_route!(source_node, route, class, "output", :source_index)

        dest_task = route.dest_task
        dest_node = jsn[dest_task]
        add_route!(dest_node, route, class, "input", :dest_index)
    end
    return nothing
end

function extract_routings(m)
    routings = Dict{RoutingTuple,Any}()
    for (edge, graph) in zip(m.taskgraph.edges, m.mapping.edges)
        # Pessimistic length check.
        if length(getsources(edge)) != 1 || length(getsinks(edge)) != 1
            error("Taskgraph has fanout nodes.")
        end

        # Build the route tuple
        source_task = first(getsources(edge)) 
        dest_task   = first(getsinks(edge))
        # Quick sanity check
        offset_list = make_offset_list(graph)

        source_index = edge.metadata["source_index"]
        dest_index   = edge.metadata["dest_index"]

        class = edge.metadata["class"]
        key = RoutingTuple(class, source_task, source_index, dest_task, dest_index)

        # Kind of gross method for getting the network id.
        src_port_path = first(Mapper2.Helper.source_vertices(graph))
        network_id = get(m.architecture[src_port_path].metadata,"network_id",missing)

        index = edge.metadata["source_index"]
        # Save result
        routings[key] = MapDumpRoute(
            network_id,
            source_task,
            source_index,
            dest_task,
            dest_index,
            offset_list
        )
    end
    return routings
end

function make_offset_list(g)
    path = CartesianIndex{2}[]
    for p in pathwalk(g)
        # Get the address from the path
        addr = Mapper2.MapperCore.getaddress(p)
        # eliminate zero addresses
        iszero(addr) && continue
        if !in(addr,path)
            push!(path, addr)
        end
    end

    offset_list = [(path[i+1] - path[i]).I for i in 1:length(path)-1]
    return offset_list
end