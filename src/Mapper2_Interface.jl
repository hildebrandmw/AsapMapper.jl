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
    return haskey(c.metadata, "attributes") && length(c.metadata["attributes"]) > 0
end

function Mapper2.isspecial(::Type{<:KC}, t::TN)
    return in(t.metadata["mapper_type"], _special_attributes)
end

function Mapper2.isequivalent(::Type{<:KC}, a::TN, b::TN)
    # Return true if the "mapper_type" are equal
    return a.metadata["mapper_type"] == b.metadata["mapper_type"]
end

function Mapper2.canmap(::Type{<:KC}, t::TN, c::Component)
    haskey(c.metadata, "attributes") || return false
    return in(t.metadata["mapper_type"], c.metadata["attributes"])
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

################################################################################
# Placement
################################################################################
mutable struct FreqNode{T} <: Mapper2.SA.Node
    location    ::T
    out_edges   ::Vector{Int64}
    in_edges    ::Vector{Int64}
    # Normalized Frequency
    freq_bin    ::Float64
end

struct CostEdge <: Mapper2.SA.TwoChannel
    source ::Int64
    sink   ::Int64
    cost   ::Float64
end

function Mapper2.SA.build_node(::Type{<:KC{T,true}}, n::TaskgraphNode, x) where T
    freq_bin = n.metadata["frequency_bin"]
    return FreqNode(x, Int64[], Int64[], freq_bin)
end

function Mapper2.SA.build_address_data(::Type{<:KC{T,true}}, c::Component) where T
    freq_bin = c.metadata["frequency_bin"]
    return freq_bin
end

function Mapper2.SA.build_channels(::Type{<:KC{true}}, edges, sources, sinks)
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
function Mapper2.SA.edge_cost(::Type{<:KC{true}}, sa::SAStruct, edge::CostEdge)
    src = getaddress(sa.nodes[edge.source])
    dst = getaddress(sa.nodes[edge.sink])
    return  edge.cost * sa.distance[src, dst]
end

################################################################################
# Routing
################################################################################

# Custom Channels
struct CostChannel <: AbstractRoutingChannel
    start   ::Vector{Vector{Int64}}
    stop    ::Vector{Vector{Int64}}
    cost    ::Float64
end

Base.isless(a::CostChannel, b::CostChannel) = a.cost < b.cost

function Mapper2.routing_channel(::Type{<:KC{true}}, start, stop, edge)
    cost = edge.metadata["cost"]
    return CostChannel(start, stop, cost)
end
