#=
Function overloads and custom types for interacting with Mapper2.

Specifically:

    - Defines attributes in the architectural model and how that relates to
        mappability.

    - Custom placement TwoChannel edge that contains a "cost" field for
        annotating important links. Also provides a custom "channel_cost" method
        for this new type of link.

    - Custom routing channel with a cost field.
=#

################################################################################
# Custom architectural definitions for Mapper2
################################################################################

# Shortcuts for convenience
const TN = TaskgraphNode
const TE = TaskgraphEdge

# Mapping criterion
#
# A Component is mappable if it has a right "typekey" in the metadata and
# the corresponding value for that key has length greater than 1. In general,
# the value should be a vector of strings, so this last criteria takes care
# of the instance where a core gets assigned an empty metadata string.
function Mapper2.ismappable(::AbstractKC, c::Component)
    return haskey(c.metadata, typekey()) && length(c.metadata[typekey()]) > 0
end

# Indicate a task is "special" (ie moves will be generated by direct lookup 
# rather than local lookup) if its metadata tag is in the list of 
# "special_attributes" (defined in Metadata.jl)
function Mapper2.isspecial(::AbstractKC, t::TN)
    return in(t.metadata[typekey()], _special_attributes)
end

# Two tasks are considered equivalent if they have the exact same attribute
# metadata. NOTE: These are just strings rather than vectors of strings like 
# with components.
function Mapper2.isequivalent(::AbstractKC, a::TN, b::TN)
    return a.metadata[typekey()] == b.metadata[typekey()]
end

# For a task to be able to map to a component, the attribute of the task must
# be in the list of attributes supplied by the component.
function Mapper2.canmap(::AbstractKC, t::TN, c::Component)
    ismappable(c) || return false
    return in(t.metadata[typekey()], c.metadata[typekey()])
end

function Mapper2.is_source_port(::AbstractKC, p::Port, e::TE)
    port_link_class = p.metadata["link_class"]
    edge_link_class = e.metadata["link_class"]

    return port_link_class == edge_link_class
end

function Mapper2.is_sink_port(::AbstractKC, p::Port, e::TE)
    port_link_class = p.metadata["link_class"]
    edge_link_class = e.metadata["link_class"]

    # Check if this is a circuit_link. If so, preserve the destination index.
    if e.metadata["preserve_dest"] && port_link_class == edge_link_class
        dest_index = get(e.metadata, "dest_index", nothing)
        dest_index == nothing && return true
        return e.metadata["dest_index"] == p.metadata["index"]
    end

    return port_link_class == edge_link_class
end

# Don't perform the "preserve_dest" check
Mapper2.is_sink_port(a::Asap2, p::Port, e::TE) = Mapper2.is_source_port(a,p,e)

function Mapper2.needsrouting(::AbstractKC, edge::TaskgraphEdge)
    return edge.metadata["route_link"]
end

################################################################################
# Placement
################################################################################

# All edges for KC types will be "CostChannel". Even if the profiled_links option
# is not being used, links between memories and memory_processors will still
# be given a higher weight to encourage them to be mapped together.
#
# The main difference here is the "cost" field, which will be multiplied by
# the distance between nodes to emphasize some connections over others.
struct CostChannel <: Mapper2.SA.TwoChannel
    source ::Int64
    sink   ::Int64
    cost   ::Float64
end

# Extend the "channel_cost" function for KC types.
Base.@propagate_inbounds function Mapper2.SA.channel_cost(
        sa::SAStruct{<:AbstractKC}, 
        channel::CostChannel
    )

    src = sa.nodes[channel.source]
    dst = sa.nodes[channel.sink]
    distance = getdistance(sa.distance, src, dst)

    return channel.cost * distance
end

# Constructor for CostChannel. Extracts the "cost" field from the metadata
# of each taskgraph channel type.
function Mapper2.SA.build_channels(::AbstractKC, channel, sources, sinks)
    return map(zip(channel, sources, sinks)) do x
        channel,srcs,snks = x

        # Quick verification that no fanout is happening. This should never
        # happen for normal KiloCore mappings.
        @assert length(srcs) == 1
        @assert length(snks) == 1

        # Since all the source and sink vectors are of length 1, we can get the
        # source and sink simply by taking the first element.
        source = first(srcs)
        sink = first(snks)
        cost = channel.metadata["cost"]
        return CostChannel(source,sink,cost)
    end
end

########################
# Extensions for Asap2 #
########################

# Asap2 has the quirk where longer circuit switched links run slower
#
# The idea is to keep a record of all the links in the mapping in a binary maxheap, and
# attach this maxheap to the auxiliary slot in the SAStruct. We then apply a global penalty
# on the maximum link length, promoting a lower global link length.
#
# I'm not really sure how well this works in practice.
Base.@propagate_inbounds function SA.unsafe_assign(
            sa :: SAStruct{Asap2}, 
            node :: SA.SANode, 
            new_location
        )
    SA.assign(node, new_location)
    # Iterate through input and output channels, update their location in the
    # edge heap.
    for edge in node.outchannels
        # Get the destination node.
        @inbounds dest = sa.nodes[sa.channels[edge].sink]

        # The distance between the two nodes.
        distance = SA.getdistance(sa.distance, new_location, SA.location(dest))
        update!(sa.aux, edge, distance)
    end
    for edge in node.inchannels
        @inbounds src = sa.nodes[sa.channels[edge].source]
        # The distance between the two nodes.
        distance = SA.getdistance(sa.distance, SA.location(src), new_location)
        update!(sa.aux, edge, distance)
    end
    nothing
end


Mapper2.SA.aux_cost(sa_struct::SAStruct{Asap2}) = 512.0 * top(sa_struct.aux)

################################################################################
# Routing
################################################################################

# Custom Channels
struct CostRoutingChannel <: RoutingChannel
    start_vertices   ::Vector{PortVertices}
    stop_vertices    ::Vector{PortVertices}
    cost             ::Float64
end

Base.isless(a::CostRoutingChannel, b::CostRoutingChannel) = a.cost < b.cost

function Mapper2.routing_channel(::AbstractKC, start, stop, edge)
    cost = edge.metadata["cost"]
    return CostRoutingChannel(start, stop, cost)
end
