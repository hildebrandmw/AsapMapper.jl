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
