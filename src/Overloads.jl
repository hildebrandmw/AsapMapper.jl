#=
Function overloads and custom types for interacting with Mapper2.

Specifically:

    - Defines attributes in the architectural model and how that relates to
        mappability.

    - Custom placement TwoChannel edge that contains a "cost" field for 
        annotating important links. Also provides a custom "edge_cost" method
        for this new type of link.
=#

################################################################################
# Custom architectural definitions for Mapper2
################################################################################

const TN = TaskgraphNode
const AKC = AbsrractKC

function Mapper2.ismappable(::Type{T}, c::Component) where {T <: AKC}
    return haskey(c.metadata, "attributes") && length(c.metadata["attributes"]) > 0
end

function Mapper2.isspecial(::Type{T}, t::TN) where {T <: AKC}
    return oneofin(t.metadata["required_attributes"], _special_attributes)
end

function Mapper2.isequivalent(::Type{T}, a::TN, b::TN) where {T <: AKC}
    # Return true if the "required_attributes" are equal
    return a.metadata["required_attributes"] == b.metadata["required_attributes"]
end

function Mapper2.canmap(::Type{T}, t::TN, c::Component) where {T <: AKC}
    haskey(c.metadata, "attributes") || return false
    return issubset(t.metadata["required_attributes"], c.metadata["attributes"])
end

################################################################################
# Placement
################################################################################

struct CostEdge <: Mapper2.SA.TwoChannel
    source ::Int64
    sink   ::Int64
    cost   ::Float64
end

function Mapper2.SA.build_channels(::Type{KCStandard}, edges, sources, sinks)
    return map(zip(edges, sources, sinks)) do x
        edge,srcs,snks = x
        @assert length(srcs) == 1
        @assert length(snks) == 1
        source = first(srcs)
        sink = first(snks)
        cost = edge.metadata["weight"]
        return CostEdge(source,sink,cost)
    end
end

# Costed metric functions
function Mapper2.SA.edge_cost(::Type{KCStandard}, sa::SAStruct, edge::CostEdge)
    src = Mapper2.SA.getaddress(sa.nodes[edge.source])
    dst = Mapper2.SA.getaddress(sa.nodes[edge.sink])
    return  edge.cost * sa.distance[src, dst]
end

################################################################################
# Routing
################################################################################

struct CostChannel <: AbstractRoutingChannel
    start   ::Vector{Vector{Int64}}
    stop    ::Vector{Vector{Int64}}
    cost    ::Float64
end

Base.isless(a::CostChannel, b::CostChannel) = a.cost < b.cost

function Mapper2.routing_channel(::Type{KCStandard}, start, stop, edge)
    cost = edge.metadata["weight"]
    return CostChannel(start, stop, cost)
end
