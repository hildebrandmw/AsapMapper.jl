#=
An IP implementation of the Router for comparison against the Pathfinder
algorithm implemented in Mapper2.

I have no plans of making a full fledged router for full models like the one in
Mapper2. Instead, this model is going to be specialized for the network style
of KiloCore/KiloCore2 in that it will be an equivalent abstraction of the
circuit switched network, but not contain all of the details for the routing
muxes.

This is because a lot of these details are unnecessary to get a valid route, and
the fewer unnecessary variables we introduce to the IP forumlation, the better
it will perform (given the usual caveats that implies to IPs)

The basic idea is that the layered network of KC will be represented as two
connected mesh grids like the diagram below


                Circuit Layer 0

              o ----- o ----- o
             /       /       /|
            /       /       / |
           o ----- o ----- o  |
          /       /       /   |
         /       /       /    |
        o ----- o ----- o     o Sink Node
        |                     |
        | Source nodes will   |
        | connect both layers |
 Source |                     |
 Node   |                     |
        o     o ----- o ----- o
        |    /       /       /
        |   /       /       /
        |  o ----- o ----- o
        | /       /       /     Circuit Layer 1
        |/       /       /
        o ----- o ----- o

Both layers will not be connected to eachother except at:

1. Source nodes, to model processor's ability to write to any circuit net.
2. Destination nodes if the "preserve_dest" metadata is set to "false".
   Otherwise, only the destination node on the appropriate layer will be marked
   as a suitable destination.

-------------------
Problem Formulation
-------------------

The problem formulation is that of a constrained multi-commodity maximum network
flow. Communication channels from one processor to another are equivalend to
flows through a network, with the start of the flow coming from the vertex
representing the communicating processor and the end of the flow stopping at the
destination processor.

The primary objective is to minimize the total sum of links used to satisfy all
communication channels.

Constraints are:

1. Flow conservation constraints. The flow into a vertex must be equal to the
   flow out of a vertex. This ensures a continuous, non-branching path from
   source to sink and ensures we can't have spontaneous generation of flows.

   The equivalent to this constraint for terminal nodes is that flow out of a
   source must be 1, and flow into a destination must be 1.

2. Capacity constraints. We must ensure that a flow going through any node does
   not exceed 1 to model the physical constraints of the Kilocore communication
   architecture.

------------------------
Objective Interpretation
------------------------
The final objective is the number of global links used in the final circuit
switched network. We will just use this number and not bother trying to route
the actual Map data structure.

-------------
Optimizations
-------------
To reduce model size, mesh generation for source-sink pairs will be limited to
3 or 4 addresses around the bounding box generated by the source-sink pair.
=#

using JuMP
using Gurobi
using DataStructures
using LightGraphs
using ProgressMeter

import Mapper2.Routing
using Mapper2.Helper

# This is not necessarily scalable to an arbitrary number of layers, or
# interconnect topology.
@enum Network layer_0 layer_1 memory_request memory_return

struct AddressCircuit
    address :: Address{2}
    network :: Network
end

address(a::AddressCircuit) = a.address
getnetwork(a::AddressCircuit) = a.network

function iproute(m::Map{A,2}) where {A}
    # Constuct model
    ip_model, struct_time, struct_bytes, _, _ = @timed build_ip_model(m)
    # Solve the model
    status, solve_time, solve_bytes, _, _ = @timed solve(ip_model)

    m.metadata["ip_route_struct_time"] = struct_time
    m.metadata["ip_route_struct_bytes"] = struct_bytes
    m.metadata["ip_route_total_time"] = solve_time
    m.metadata["ip_route_solve_bytes"] = solve_bytes
    m.metadata["ip_route_objective"] = getobjectivevalue(ip_model) 
    m.metadata["ip_route_solve_time"] = getsolvetime(ip_model)

    if status == :Optimal
        m.metadata["ip_optimal"] = true
    else
        m.metadata["ip_opcimal"] = false
    end

    m.metadata["ip_status"] = status

    return m
end

function build_ip_model(m::Map{A,2}) where A
    # Build the network data type.
    network = build_network(m)

    # Instantiate an empty IP model
    ip_model = Model(solver = GurobiSolver(Threads=1))

    # To create variables for JuMP, we need to do it all in one shot. So, we
    # must iterate over the network to get all the variables
    # (nodes in the network) that we need.
    vertices_for_taskgraph_edge = Vector{Int}[]

    # Amount to grow the bounding box around the extrema of the source-sink
    # pair. This helps keep the number of generated variables down without
    # hurting routing. Keep somewhere between 2 and 4.
    box_growth = 3

    # Collection of vertices used for each edge in the taskgraph.
    vertex_collection = Vector{Int}[]
    # Indices of start and stop nodes for each edge of the graph.
    source_collection = Vector{Int}[]
    sink_collection   = Vector{Int}[]

    num_edges = Mapper2.num_edges(m.taskgraph)

    for (edge_index, taskgraph_edge) in enumerate(getedges(m.taskgraph))
        # Get the source and destination tasks, as well as the addresses
        # for these tasks.
        #
        # Since there are no taskgraphs with fanout, just get the first
        # of the sources/sinks as there should only be 1.
        source_name = first(getsources(taskgraph_edge))
        sink_name = first(getsinks(taskgraph_edge))

        source_address = getaddress(m, source_name)
        sink_address = getaddress(m, sink_name)

        source_task = getnode(m.taskgraph, source_name)
        sink_task = getnode(m.taskgraph, sink_name)

        # Create a bounding box for this address
        box = BoundingBox(source_address, sink_address, box_growth)

        # Get the network for this edge.

        # If the sink is a memory, this uses the "memory_request" link
        if ismemory(sink_task)
            links = [memory_request]

        # Otherwise if the source is a memory, it is a "memory_return" link.
        # Note that there should be no links where both the sources and the
        # sinks are memories.
        elseif ismemory(source_task)
            links = [memory_return]

        # Default - use the circuit links.
        else
            links = [layer_0, layer_1]
        end

        # Get the source and sink vertices for this layer.
        local_source = getvertices(network, source_address, links)
        local_sink = getvertices(network, sink_address, links)
        push!(source_collection, local_source)
        push!(sink_collection, local_sink)

        # Now, collect all vertices that are within the bounding box 
        local_vertices = Int[]
        for addr in addresses(box)
            append!(local_vertices, getvertices(network, addr, links))
        end
        push!(vertex_collection, local_vertices)
    end


    # We are now ready to generate the IP model.
    @variable(ip_model, 
        x[i = 1:num_edges, 
          j = vertex_collection[i], 
          k = outneighbors(network, j);
          in(k, vertex_collection[i])
        ], Bin)

    @objective(ip_model, Min, sum(x))

    # Add flow constraints. For start and stop edges, make sure the 
    # outgoing/incoming sum is 1.
    #
    # Must also ensure that flow out of a sink node and into a source node are
    # zero to avoid out->in loops.
    #
    # For all other edges, incoming flow must equal outgoing flow.
    
    for i in 1:num_edges
        valid_vertices = vertex_collection[i]
        @constraint(ip_model, sum(x[i, j, k] for j in source_collection[i], k in outneighbors(network, j) if k in valid_vertices) == 1)
        @constraint(ip_model, sum(x[i, k, j] for j in source_collection[i], k in inneighbors(network, j) if k in valid_vertices) == 0)

        @constraint(ip_model, sum(x[i, j, k] for j in sink_collection[i], k in outneighbors(network, j) if k in valid_vertices) == 0)
        @constraint(ip_model, sum(x[i, k, j] for j in sink_collection[i], k in inneighbors(network, j) if k in valid_vertices) == 1)

        for vertex in valid_vertices
            # Skip source and sink vertices
            (vertex in source_collection[i] || vertex in sink_collection[i]) && continue

            # Flow in and flow out must be equal.
            @constraint(ip_model, 
                sum(x[i,vertex,k] for k in outneighbors(network, vertex) if k in valid_vertices) -
                sum(x[i,k,vertex] for k in  inneighbors(network, vertex) if k in valid_vertices) == 0)
        end
    end

    # Add capacity constraints.
    for edge in edges(network)
        source = src(edge)
        dest   = dst(edge)

        # Collect all channels that have this edge.
        indices = Int[]
        for i in 1:num_edges
            if source in vertex_collection[i] && dest in vertex_collection[i]
                push!(indices, i)
            end
        end

        # Add capacity constraint.
        @constraint(ip_model, sum(x[i, source, dest] for i in indices) <= 1)
    end

    return ip_model
end

function build_network(m::Map{A,2}) where A
    # First, build a light graph for the network given above.
    network = SimpleNetwork()

    # Iterate through all addresses. Add circuit and memory nodes as necessary.
    for addr in addresses(m.architecture)
        # Get the component at this address, and then get the mappable component
        # child of this component.
        component = m.architecture[addr]
        mappables = collect(Iterators.filter(ismappable, component[p] for p in walk_children(component)))
        @assert length(mappables) == 1

        mappable_component = first(mappables)

        # Create vertices for this component
        if isinput(mappable_component) || isoutput(mappable_component)
            # Add just one vertex because the input/output handlers only connect
            # to circuit net 0
            #
            # Since we just added a vertex, the index of that vertex is simply
            # the number of vertices.
            add_vertex!(network, addr, layer_0)
        elseif ismemoryproc(mappable_component)
            # Add both layers for memory processor as well as memory request and
            # and memory return nodes.
            add_vertex!(network, addr, layer_0)
            add_vertex!(network, addr, layer_1)
            add_vertex!(network, addr, memory_return)
            add_vertex!(network, addr, memory_request)
        elseif isproc(mappable_component)
            # Just add the two circuit layers
            add_vertex!(network, addr, layer_0)
            add_vertex!(network, addr, layer_1)
        elseif ismemory(mappable_component)
            # Add the two memory networks
            add_vertex!(network, addr, memory_return)
            add_vertex!(network, addr, memory_request)
        else
            error("Unrecognized component type")
        end
    end

    # Now, extract adjacency information to start connecting nodes together
    connected_components = MapperCore.connected_components(m.architecture)
    for (source,destinations) in connected_components
        for dest in destinations
            add_edge!(network, source, dest)
        end
    end

    return network
end

################################################################################
# Abstraction of the network for convenience purposes.

struct SimpleNetwork
    graph               :: LightGraphs.SimpleGraphs.SimpleDiGraph{Int64}
    vertex_data         :: Dict{Int, AddressCircuit}
    address_to_vertex   :: Dict{Address{2}, Vector{Int}}
end


SimpleNetwork() = SimpleNetwork(
    DiGraph(),
    Dict{Int, AddressCircuit}(),
    Dict{Address{2},Vector{Int}}()
)

getdata(n::SimpleNetwork, i::Int) = n.vertex_data[i]
getvertices(n::SimpleNetwork, a::Address{2}) = get(n.address_to_vertex, a, Int[])

function getvertices(n::SimpleNetwork, a::Address{2}, networks)
    return collect(Iterators.filter(
        x -> getdata(n, x).network in networks,
        i for i in getvertices(n, a)
    ))
end


function LightGraphs.add_vertex!(n::SimpleNetwork, address::Address{2}, network)
    add_vertex!(n.graph)
    n.vertex_data[nv(n.graph)] = AddressCircuit(address, network)

    # Register a vertex at this address.
    if haskey(n.address_to_vertex, address)
        push!(n.address_to_vertex[address], nv(n.graph))
    else
        n.address_to_vertex[address] = [nv(n.graph)]
    end
    return nothing
end

function LightGraphs.add_edge!(n::SimpleNetwork, source::Address, dest::Address)
    # Get the lists of nodes at the source and destination vertices.
    source_vertices = n.address_to_vertex[source]
    dest_vertices   = n.address_to_vertex[dest]

    # Add edges from source to destination by matching circuit types.
    # Note that for things like memory links, this will generate a few extra
    # variables that aren't strictly needed, but this is minimal and won't
    # affect the final routing.
    for sv in source_vertices
        source_data = n.vertex_data[sv]
        for dv in dest_vertices
            dest_data = n.vertex_data[dv]
            if getnetwork(source_data) == getnetwork(dest_data)
                add_edge!(n.graph, sv, dv)
            end
        end
    end
end

# Simple forwards.
LightGraphs.nv(n::SimpleNetwork) = nv(n.graph)
LightGraphs.ne(n::SimpleNetwork) = ne(n.graph)
LightGraphs.outneighbors(n::SimpleNetwork, i) = outneighbors(n.graph, i)
LightGraphs.inneighbors(n::SimpleNetwork, i) = inneighbors(n.graph, i)
LightGraphs.edges(n::SimpleNetwork) = edges(n.graph)

################################################################################
struct BoundingBox{D}
    bounds::NTuple{D,UnitRange{Int}}
end

function BoundingBox(a::Address{D}, b::Address{D}, growth = 0) where D
    return BoundingBox(Tuple(map(1:D) do i
        minval, maxval = minmax(a.I[i], b.I[i])
        return (minval - growth):(maxval + growth)
    end))
end

Mapper2.addresses(b::BoundingBox) = (CartesianIndex(i) for i in Iterators.product(b.bounds...))

function BoundingBox(min::NTuple{D}, max::NTuple{D}) where D
    return BoundingBox(Tuple(min[i]:max[i] for i in 1:D))
end

function Base.in(addr::Address{D}, box::BoundingBox{D}) where D
    for i in 1:D
        in(addr.I[i], box.bounds[i]) || return false
    end
    return true
end