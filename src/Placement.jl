function Mapper2.ismappable(::Type{T}, c::Component) where {T <: AbstractKC}
    return haskey(c.metadata, "attributes") && length(c.metadata["attributes"]) > 0
end

function Mapper2.isspecial(::Type{T}, t::TaskgraphNode) where {T <: AbstractKC}
    return oneofin(t.metadata["required_attributes"], _special_attributes)
end

function Mapper2.isequivalent(::Type{T}, a::TaskgraphNode, b::TaskgraphNode) where {T <: AbstractKC}
    # Return true if the "required_attributes" are equal
    return a.metadata["required_attributes"] == b.metadata["required_attributes"]
end

function Mapper2.canmap(::Type{T}, t::TaskgraphNode, c::Component) where {T <: AbstractKC}
    haskey(c.metadata, "attributes") || return false
    return issubset(t.metadata["required_attributes"], c.metadata["attributes"])
end

################################################################################
# Methods for architectures with link weights
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
