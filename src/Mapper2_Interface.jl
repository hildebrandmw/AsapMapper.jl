#=
Function overloads and custom types for interacting with Mapper2.

Specifically:

    - Defines attributes in the architectural model and how that relates to
        mappability.

    - Custom placement TwoChannel edge that contains a "cost" field for
        annotating important links. Also provides a custom "edge_cost" method
        for this new type of link.

    - Custom routing channel with a cost field.
=#

################################################################################
# Custom architectural definitions for Mapper2
################################################################################

const TN = TaskgraphNode
const TE = TaskgraphEdge

function Mapper2.ismappable(::Type{<:KC}, c::Component)
    return haskey(c.metadata, typekey()) && length(c.metadata[typekey()]) > 0
end

function Mapper2.isspecial(::Type{<:KC}, t::TN)
    return in(t.metadata[typekey()], _special_attributes)
end

function Mapper2.isequivalent(::Type{<:KC}, a::TN, b::TN)
    # Return true if the "mapper_type" are equal
    return a.metadata[typekey()] == b.metadata[typekey()]
end

function Mapper2.canmap(::Type{<:KC}, t::TN, c::Component)
    haskey(c.metadata, typekey()) || return false
    return in(t.metadata[typekey()], c.metadata[typekey()])
end

function Mapper2.is_source_port(::Type{<:KC}, p::Port, e::TE)
    port_link_class = p.metadata["link_class"]
    edge_link_class = e.metadata["link_class"]

    return port_link_class == edge_link_class
end

function Mapper2.is_sink_port(::Type{<:KC}, p::Port, e::TE)
    port_link_class = p.metadata["link_class"]
    edge_link_class = e.metadata["link_class"]

    # Check if this is a circuit_link. If so, preserve the destination index.
    if (e.metadata["preserve_dest"] && port_link_class == edge_link_class)
        return e.metadata["dest_index"] == p.metadata["index"]
    end

    return port_link_class == edge_link_class
end

function Mapper2.needsrouting(::Type{<:KC}, edge::TaskgraphEdge)
    return edge.metadata["route_link"]
end

################################################################################
# Placement
################################################################################
mutable struct RankedNode{T} <: Mapper2.SA.Node
    location    ::T
    out_edges   ::Vector{Int64}
    in_edges    ::Vector{Int64}
    # Normalized rank and derivative
    rank            ::Float64
    maxheap_handle  ::Int64
end

function SA.move(sa::SAStruct{KC{true}}, index, spot)
    node = sa.nodes[index]
    sa.grid[SA.location(node)] = 0
    SA.assign(node, spot)
    sa.grid[SA.location(node)] = index

    # Get the rank for the core at the location of the node.
    component_rank = sa.address_data[SA.location(node)]
    ratio = node.rank / component_rank

    update!(sa.aux.ratio_max_heap, node.maxheap_handle, ratio)
end

"""
    swap(sa::SAStruct, node1, node2)

Swap two nodes in the placement structure.
"""
function SA.swap(sa::SAStruct{KC{true}}, node1, node2)
    # Get references to these objects to make life easier.
    n1 = sa.nodes[node1]
    n2 = sa.nodes[node2]
    # Swap address/component assignments
    s = SA.location(n1)
    t = SA.location(n2)

    SA.assign(n1, t)
    SA.assign(n2, s)
    # Swap grid.
    sa.grid[t] = node1
    sa.grid[s] = node2

    n1_ratio = n1.rank / sa.address_data[SA.location(n1)]
    n2_ratio = n2.rank / sa.address_data[SA.location(n2)]

    update!(sa.aux.ratio_max_heap, n1.maxheap_handle, n1_ratio)
    update!(sa.aux.ratio_max_heap, n2.maxheap_handle, n2_ratio)

    return nothing
end



struct CostEdge <: Mapper2.SA.TwoChannel
    source ::Int64
    sink   ::Int64
    cost   ::Float64
end

function Mapper2.SA.build_node(::Type{<:KC{true}}, n::TaskgraphNode, x)
    rank = getrank(n).normalized_rank
    handle = n.metadata["heap_handle"]
    # Initialize all nodes to think they are the max ratio. Code for first move
    # operation will figure out which one is really the maximum.
    return RankedNode(x, Int64[], Int64[], rank, handle)
end


function Mapper2.SA.build_address_data(::Type{<:KC{true}}, c::Component)
    rank = getrank(c).normalized_rank
    return rank
end

function Mapper2.SA.build_channels(::Type{<:KC}, edges, sources, sinks)
    return map(zip(edges, sources, sinks)) do x
        edge,srcs,snks = x
        @assert length(srcs) == 1
        @assert length(snks) == 1
        source = first(srcs)
        sink = first(snks)
        cost = edge.metadata["cost"]
        return CostEdge(source,sink,cost)
    end
end

# Costed metric functions
function Mapper2.SA.edge_cost(::Type{<:KC}, sa::SAStruct, edge::CostEdge)
    src = getaddress(sa.nodes[edge.source])
    dst = getaddress(sa.nodes[edge.sink])
    return  edge.cost * sa.distance[src, dst]
end

function Mapper2.SA.aux_cost(::Type{<:KC{true}}, sa::SAStruct)
    return sa.aux.task_penalty_multiplier * top(sa.aux.ratio_max_heap)
end


################################################################################
# Routing
################################################################################

# Custom Channels
struct CostChannel <: AbstractRoutingChannel
    start_vertices   ::Vector{Vector{Int64}}
    stop_vertices    ::Vector{Vector{Int64}}
    cost             ::Float64
end

Base.isless(a::CostChannel, b::CostChannel) = a.cost < b.cost

function Mapper2.routing_channel(::Type{<:KC}, start, stop, edge)
    cost = edge.metadata["cost"]
    return CostChannel(start, stop, cost)
end
