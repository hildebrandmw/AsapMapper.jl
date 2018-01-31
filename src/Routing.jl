################################################################################
# Types for annotating links in the routing resources graph
################################################################################


################################################################################
# Annotations for creating the links in the Taskgraph.
################################################################################
struct CostChannel <: AbstractRoutingChannel
    start::Vector{Int64}
    stop::Vector{Int64}
    cost::Float64
    function CostChannel(start, stop, taskgraph_edge)
        cost = taskgraph_edge.metadata["weight"]
        return new(start, stop, cost)
    end
end

Base.isless(a::CostChannel, b::CostChannel) = a.cost < b.cost

Mapper2.routing_channel_type(::Type{KCStandard}) = CostChannel
