function dump_map(m::Map, filename::AbstractString)
    jsn = skeleton_dump(m)
    populate_routes!(jsn, m)

    json_dict = Dict{String,Any}("task_structure" => collect(values(jsn)))

    record_info!(json_dict, m)
    f = open(filename, "w")
    print(f, json(json_dict, 2)) 
    close(f)
    return nothing
end

create_dict(d::Dict, k, v) = haskey(d, k) || (d[k] = v())

"""
    record_info!(json_dict, m::Map)

Record various info that may be helpful to the Project Manager.
"""
function record_info!(json_dict, m::Map)
    create_dict(json_dict, "info", Dict{String,Any})
    # Call the "check_routing" function and give it the "quiet" parameter to
    # keep get rid of redundant prints.
    json_dict["info"]["routing_success"] = Mapper2.check_routing(m, true)
end

################################################################################
struct RoutingTuple
    class           ::String
    source_task     ::_name_types
    source_index    ::_index_types
    dest_task       ::_name_types
    dest_index      ::_index_types
end

abstract type MapDump end
struct MapDumpNode <: MapDump
    name            ::String
    address         ::Tuple
    core_name       ::Union{String,Void}
    core_type       ::Union{String,Void}
    leaf_node_dict  ::Dict{String,Any}
end

# Constructor supplying empty endiding dictionary
function MapDumpNode(name, address::T, core_name, core_type) where T
    return MapDumpNode(
        name,
        T <: CartesianIndex ? address.I : address,
        core_name,
        core_type,
        Dict{String,Any}()
    )
end

struct MapDumpRoute <: MapDump
    network_id      ::Union{Int,Void}
    new_source_index::_index_types
    new_dest_index  ::_index_types
    source_task     ::_name_types
    source_index    ::_index_types
    dest_task       ::_name_types
    dest_index      ::_index_types
    offset_list     ::Vector
end

JSON.lower(m::MapDump) = Dict(string(f) => getfield(m,f) for f in fieldnames(typeof(m)))

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
        
        addr = Mapper2.MapperCore.getaddress(m.architecture,address_path)

        component = m.architecture[address_path]
        core_name = component.metadata["pm_name"]
        core_type = component.metadata["pm_type"]

        dict[name] = MapDumpNode(name, addr, core_name, core_type)
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
    arch = m.architecture
    routings = Dict{RoutingTuple,Any}()
    for (edge, graph) in zip(m.taskgraph.edges, m.mapping.edges)
        # Build the route tuple
        source_task = first(getsources(edge)) 
        dest_task   = first(getsinks(edge))
        offset_list = make_offset_list(arch, graph)

        source_index = edge.metadata["source_index"]
        dest_index   = edge.metadata["dest_index"]

        class = edge.metadata["pm_class"]

        # Get source and destination ports to extract;
        # - network_id
        # - new_source_index
        # - new_dest_index
        src_port_path = first(source_vertices(graph))
        dst_port_path = first(sink_vertices(graph))

        src_metadata = arch[src_port_path].metadata
        network_id = get(src_metadata,"network_id",nothing)
        new_source_index = src_metadata["index"]

        dst_metadata = arch[dst_port_path].metadata
        new_dest_index = dst_metadata["index"]

        index = edge.metadata["source_index"]

        key = RoutingTuple(class, source_task, source_index, dest_task, dest_index)
        routings[key] = MapDumpRoute(
            network_id,
            new_source_index,
            new_dest_index,
            source_task,
            source_index,
            dest_task,
            dest_index,
            offset_list
        )
    end
    return routings
end

function make_offset_list(arch, g)
    path = CartesianIndex{2}[]
    for p in linearize(g)
        # Skip global links since addresses they don't have an address
        isgloballink(p) && continue
        # Get the address from the path
        addr = Mapper2.MapperCore.getaddress(arch, p)
        if !in(addr,path)
            push!(path, addr)
        end
    end

    offset_list = [(path[i+1] - path[i]).I for i in 1:length(path)-1]
    return offset_list
end
