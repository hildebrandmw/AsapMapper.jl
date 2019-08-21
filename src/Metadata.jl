################################################################################
# Components - Processors, Memory, IO Handlers
################################################################################

# Task classes are used to control which tasks are mapped to which cores.
# each core has fulfill one or more task classes. Each task will be assigned a
# class and will be mapped to a core that supports that task.
"All task classes currently recognized by the Mapper."
const _mapper_task_classes = Set([
      "processor",
      "memory_processor",
      "input_handler",
      "output_handler",
      "memory_1port",
      "memory_2port",
    ])

# Function to unify mapper types cleanly between tasks and cores.
memory_meta(ports::Int) = "memory_$(ports)port"
ismemory(s::String) = startswith(s, "memory") && endswith(s, "port")
ismemory(x) = false

# Global NamedTuple for dealing with attributes.
const MTypes = (
    proc        = "processor",
    memoryproc  = "memory_processor",
    input       = "input_handler",
    output      = "output_handler",
    memory      = memory_meta,
)

typekey() = "mapper_type"

ismappable(c::AbstractComponent)    = haskey(c.metadata, typekey())

isproc(c::AbstractComponent)        = ismappable(c) && in(MTypes.proc, c.metadata[typekey()])
ismemoryproc(c::AbstractComponent)  = ismappable(c) && in(MTypes.memoryproc, c.metadata[typekey()])
isinput(c::AbstractComponent)       = ismappable(c) && in(MTypes.input, c.metadata[typekey()])
isoutput(c::AbstractComponent)      = ismappable(c) && in(MTypes.output, c.metadata[typekey()])
islowpower(c::AbstractComponent)     = ismappable(c) && in(MTypes.lowpower, c.metadata[typekey()])
ishighperformance(c::AbstractComponent) = ismappable(c) && in(MTypes.highperformance, c.metadata[typekey()])

function ismemory(c::AbstractComponent)
    ismappable(c) || return false
    for i in c.metadata[typekey()]
        if ismemory(i)
            return true
        end
    end
    return false
end

################################################################################
# Assignment of metadata to Components.
################################################################################
proc_metadata() = Dict{String,Any}(typekey() => [MTypes.proc])
mem_proc_metadata() = Dict{String,Any}(typekey() => [MTypes.proc, MTypes.memoryproc])

function mem_nport_metadata(nports::Int)
    attrs = [MTypes.memory(i) for i in 1:nports]
    return Dict{String,Any}(
        typekey() => attrs,
        # Options for plotting
        "shadow_offset" => [Address(0,i) for i in 1:nports-1],
        "fill"          => "memory"
    )
end

input_handler_metadata() = Dict{String,Any}(typekey() => [MTypes.input])
output_handler_metadata() = Dict{String,Any}(typekey() => [MTypes.output])

add_lowpower(c::Component) = push!(c.metadata[typekey()], MTypes.lowpower)
add_highperformance(c::Component) = push!(c.metadata[typekey()], MTypes.highperformance)

################################################################################
# Metadata for Taskgraph Nodes
################################################################################

const TN = TaskgraphNode
# Setting task -> core requirements.
make_input!(t::TN)       = (t.metadata[typekey()] = MTypes.input)
make_output!(t::TN)      = (t.metadata[typekey()] = MTypes.output)
make_proc!(t::TN)        = (t.metadata[typekey()] = MTypes.proc)
make_memoryproc!(t::TN)  = (t.metadata[typekey()] = MTypes.memoryproc)
make_memory!(t::TN, ports::Integer) = t.metadata[typekey()] = MTypes.memory(ports)

# Getting task -> core requirements.
ismappable(t::TN)   = true
isinput(t::TN)      = t.metadata[typekey()] == MTypes.input
isoutput(t::TN)     = t.metadata[typekey()] == MTypes.output
isproc(t::TN)       = t.metadata[typekey()] == MTypes.proc
ismemoryproc(t::TN) = t.metadata[typekey()] == MTypes.memoryproc
ismemory(t::TN)     = ismemory(t.metadata[typekey()])

################################################################################
# Routing Resources
################################################################################

"Routng link types currently implemented in the Mapper."
const _mapper_link_classes = Set([
        "circuit_link",
        "memory_request_link",
        "memory_response_link",
    ])

# Generic function for making a metadata dictionary for ports/links where only
# the link-class is needed.
function routing_metadata(link_class)
    if !in(link_class, _mapper_link_classes)
        throw(KeyError(link_class))
    end

    return Dict{String,Any}(
        "link_class" => link_class,
    )
end

# Processor component metadata.
function proc_output_metadata(ndirs, nlayers)
    metadata_vec = map(1:(ndirs * nlayers)) do i
        return Dict{String,Any}(
            "link_class"    => "circuit_link",
            "index"         => i-1,
            "network_id"    => div(i-1, ndirs),
        )
    end
    return metadata_vec
end

function proc_fifo_metadata(nfifos)
    metadata_vec = map(1:nfifos) do i
        return Dict{String,Any}(
            "link_class" => "circuit_link",
            "index" => i-1
        )
    end
    return metadata_vec
end

function proc_memory_request_metadata()
    return Dict{String,Any}(
        "link_class" => "memory_request_link",
        "index" => 0
    )
end

function proc_memory_return_metadata()
    return Dict{String,Any}(
        "link_class" => "memory_response_link",
        "index" => 0
    )
end

# Memories
function mem_memory_request_metadata(nports)
    metadata_vec = map(1:nports) do i
        return Dict{String,Any}(
            "link_class" => "memory_request_link",
            "index" => i-1,
        )
    end
    return metadata_vec
end

function mem_memory_return_metadata(nports)
    metadata_vec = map(1:nports) do i
        return Dict{String,Any}(
            "link_class" => "memory_response_link",
            "index" => i-1,
        )
    end
    return metadata_vec
end

# io handlers
function input_handler_port_metadata(nlinks)
    metadata_vec = map(1:nlinks) do i
        return Dict{String,Any}(
            "link_class" => "circuit_link",
            "index" => i-1,
        )
    end
end

function output_handler_port_metadata(nlinks)
    metadata_vec = map(1:nlinks) do i
        return Dict{String,Any}(
            "link_class" => "circuit_link",
            "index" => i-1,
        )
    end
    return metadata_vec
end

interpolate(x0, y0, x1, y1, t) = (x0, y0) .+ (t .* (x1 - x0, y1 - y0))
interpolate(x::Tuple, y::Tuple, t) = interpolate(x..., y..., t)

################################################################################
# Metadata for top level ports - used for pretty post-route plotting.
function top_level_port_metadata(style, orientation, direction, class, num_links)
    # Get a base dictionary for this port class.
    base = routing_metadata(class)
    # Parameters controlling offset generation.
    spacing = 0.4/num_links

    a, b = port_boundaries(style, orientation)
    start = initial_offset(style, orientation, direction)

    offset_dicts = map(0:num_links - 1) do i
        x, y = interpolate(a, b, start + spacing * i)
        d = Dict(
            "x" => x,
            "y" => y,
        )
        return merge(d, base)
    end

    return offset_dicts
end

