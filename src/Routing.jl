################################################################################
# Types for annotating links in the routing resources graph
################################################################################


################################################################################
# Annotations for creating the links in the Taskgraph.
################################################################################
struct CostTask <: AbstractRoutingTask
    start::Vector{Int64}
    stop::Vector{Int64}
    cost::Float64
    function CostTask(start, stop, taskgraph_edge)
        cost = taskgraph_edge.metadata["weight"]
        return new(start, stop, cost)
    end
end

Base.isless(a::CostTask, b::CostTask) = a.cost < b.cost

Mapper2.routing_task_type(::Type{KCStandard}) = CostTask
