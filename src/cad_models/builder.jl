# There is a lot of dymnaic multiple dispatch going on in this routine, but
# it should generall be OKAY since it is not performance critical.
function build(A,
               name     ::String,
               special  ::Vector,
               fill     ::InstComponent,
               dims     ::NTuple{D,<:Integer}) where D

    arch = TopLevel{A,D}(name)

    # Iterate through all special definitions - instantiating each.
    # Must do this before applying the fill to reserve these addresses.
    for inst_def in special
        instantiate!(arch, inst_def)
    end

    # Instantiate the fill type at all required addresses.
    filled_addresses = Set{Address{D}}()
    for addr in CartesianRange(dims)
        c = build(fill)
        if !isassigned(arch, addr)
            add_child(arch, c, addr)
            push!(filled_addresses, addr)
        end
    end

    # Connect all special types.
    for instdef in special
        for location in instdef.locations
            base = location.base
            for offset in location.offsets
                # Don't try to connect to non-existent addresses
                isassigned(arch, base + offset) || continue
                    
                a = arch.children[base].metadata["inst_component"]
                b = arch.children[base + offset].metadata["inst_component"]

                connect!(arch, a, b, base, offset)
            end
        end
    end



    return arch
end

################################################################################
function instantiate!(arch::TopLevel, inst::InstDef{T,D}) where {T,D}
    IC = inst.def
    # Create the component from the high level definition
    c = build(IC)

    locations = inst.locations
    for l in locations
        add_child(arch, c, l.base)
    end

    # Create an shadow component to avoid instantiating anything else where this
    # component occupies.
    if hasshadow(IC)
        reservation = build(Reserved())
        for l in locations
            for offset in IC.shadow
                add_child(arch,reservation,l.base + offset)
            end
        end
    end

    # Get special neighbor type if any
    if hasneighbor(IC)
        n = build(IC.neighbor)
        for l in locations
            for offset in l.offsets
                add_child(arch, n, l.base + offset)
            end
        end
    end
    return nothing
end

const _proc_src_ports = Dict(
        CartesianIndex(0,1)     => "east",
        CartesianIndex(0,-1)    => "west",
        CartesianIndex(1,0)     => "south",
        CartesianIndex(-1,0)    => "north",
    )

const _proc_dst_ports = Dict(
        CartesianIndex(0,1)     => "west",
        CartesianIndex(0,-1)    => "east",
        CartesianIndex(1,0)     => "north",
        CartesianIndex(-1,0)    => "south",
    )

################################################################################
# Connections.
################################################################################

# Fallback
connect!(arch::TopLevel, a::InstComponent, b::InstComponent, base, offset) = nothing

function connect!(arch::TopLevel, a::InputHandler, b::AsapProc, base, offset)
    linktop = min(a.nlinks, b.nlinks) - 1

    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "circuit_link"
    )

    for i in 0:linktop
        # Create port names
        src = PortPath("out[$i]", base)
        dst = PortPath("$(_proc_dst_ports[offset])_in[$i]", base + offset)
        # set to not throw error if link cannot be created.
        add_link(arch, src, dst, true, metadata = metadata)
    end
    return nothing
end

function connect!(arch::TopLevel, a::AsapProc, b::OutputHandler, base, offset)
    linktop = min(a.nlinks, b.nlinks) - 1

    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "circuit_link"
    )

    for i in 0:linktop
        # Create port names
        src = PortPath("$(_proc_src_ports[offset])_out[$i]", base)
        dst = PortPath("in[$i]", base + offset)
        # set to not throw error if link cannot be created.
        add_link(arch, src, dst, true, metadata = metadata)
    end
    return nothing
end

function connect!(arch::TopLevel, a::Memory, b::AsapProc, base, offset)
    @assert b.memory 

    request_metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "memory_request_link",
   )

    response_metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "memory_response_link",
   )

    # Connect memory -> proc
    for i in 0:a.nports-1
        src = PortPath("out[$i]", base)
        dst = PortPath("memory_in", base + offset)
        # Exit loop if link creation is successful
        if add_link(arch, src, dst, true, metadata = response_metadata)
            break
        end
    end
    # Connect proc -> memory
    for i in 0:a.nports-1
        src = PortPath("memory_out", base + offset)
        dst = PortPath("in[$i]", base)
        # Exit loop if link creation is successful
        if add_link(arch, src, dst, true, metadata = request_metadata)
            break
        end
    end
    return nothing
end

function connect!(arch::TopLevel, a::AsapProc, b::AsapProc, base, offset)
    linktop = min(a.nlinks, b.nlinks) - 1

    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "circuit_link"
    )

    for i in 0:linktop
        # Create port names
        src = PortPath("$(_proc_src_ports[offset])_out[$i]", base)
        dst = PortPath("$(_proc_dst_ports[offset])_in[$i]", base + offset)
        # set to not throw error if link cannot be created.
        add_link(arch, src, dst, true, metadata = metadata)
    end
    return nothing
end
