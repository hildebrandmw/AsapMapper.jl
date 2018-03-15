struct MemoryLocation{D}
    address         ::Address{D}
    other_addresses ::Vector{Address{D}}
    offsets         ::Vector{Address{D}}
end

function MemoryLocation(a::T, b::Vector{T}, c::Vector{T}) where T <: NTuple{D,<:Integer} where D
    return MemoryLocation{D}(Address(a), Address.(b), Address.(c))
end

function MemoryLocation(a::T, b::T, c::Vector{T}) where T <: NTuple{D,<:Integer} where D
    return MemoryLocation{D}(Address(a), [Address(b)], Address.(c))
end

function MemoryLocation(a::T, c::Vector{T}) where T <: NTuple{D,<:Integer} where D
    return MemoryLocation{D}(Address(a), Address{D}[], Address.(c))
end

function mem_addresses(v::Vector{MemoryLocation{D}}) where D
    a = Set{Address{D}}()
    for i in v
        push!(a, i.address)
        for j in i.other_addresses
            push!(a, j)
        end
    end
    return a
end

function mem_neighbors(v::Vector{MemoryLocation{D}}) where D
    a = Set{Address{D}}()
    for i in v
        base = i.address
        for o in i.offsets
            push!(a, base + o)
        end
    end
    return a
end


function asap_cluster(num_links, A)
    arch = TopLevel{A,2}("asap_cluster")

    # Extra parameters
    num_fifos = 2
    memories = [
                # Memory Cluster 1
                MemoryLocation((8, 8),   (8, 9)  , [(-1,0),(-1,1)]),
                MemoryLocation((8, 10),  (8, 11) , [(-1,0),(-1,1)]),
                MemoryLocation((9, 8),   (9, 9)  , [(1,0),(1,1)]),
                MemoryLocation((9, 10),  (9, 11) , [(1,0),(1,1)]),
                # Memory Cluster 2
                MemoryLocation((8, 24),  (8, 25) , [(-1,0),(-1,1)]),
                MemoryLocation((8, 26),  (8, 27) , [(-1,0),(-1,1)]),
                MemoryLocation((9, 24),  (9, 25) , [(1,0),(1,1)]),
                MemoryLocation((9, 26),  (9, 27) , [(1,0),(1,1)]),
                # Memory Cluster 3
                MemoryLocation((24, 8),  (24, 9) , [(-1,0),(-1,1)]),
                MemoryLocation((24, 10), (24, 11), [(-1,0),(-1,1)]),
                MemoryLocation((25, 8),  (25, 9) , [(1,0),(1,1)]),
                MemoryLocation((25, 10), (25, 11), [(1,0),(1,1)]),
                # Memory Cluster 4
                MemoryLocation((24, 24), (24, 25), [(-1,0),(-1,1)]),
                MemoryLocation((24, 26), (24, 27), [(-1,0),(-1,1)]),
                MemoryLocation((25, 24), (25, 25), [(1,0),(1,1)]),
                MemoryLocation((25, 26), (25, 27), [(1,0),(1,1)]),
        ]



    mem_addrs = mem_addresses(memories)
    mem_neighbor_addrs = mem_neighbors(memories)

    ####################
    # Normal Processor #
    ####################
    processor = build_processor_tile(num_links)
    for r in 2:33, c in 2:33
        addr = Address(r,c)
        # Skip if this is an address occupied by a memory or memory neighbor.
        if in(addr, mem_addrs) || in(addr, mem_neighbor_addrs)
            continue
        end
        add_child(arch, processor, addr)
    end

    ####################
    # Memory Processor #
    ####################
    # Instantiate a memory processor at every address neighboring a memory.
    memory_processor = build_processor_tile(num_links, include_memory = true)
    for mem_neighbor_addr in mem_neighbor_addrs
        add_child(arch, memory_processor, mem_neighbor_addr)
    end

    #################
    # 2 Port Memory #
    #################
    memory = build_memory(2)
    for mem_addr in mem_addrs
        add_child(arch, memory, mem_addr)
    end

    #################
    # Input Handler #
    #################
    input_handler = build_input_handler(1)
    for (r,c) ∈ zip((2,13,15,19), (1, 34, 1, 34))
        add_child(arch, input_handler, Address(r,c))
    end

    ##################
    # Output Handler #
    ##################
    output_handler = build_output_handler(1)
    for (r,c) ∈ zip((2,13,15,19), (34, 1, 34, 1))
        add_child(arch, output_handler, Address(r,c))
    end

    #######################
    # Global Interconnect #
    #######################
    connect_processors(arch, num_links)
    connect_io(arch, num_links)
    connect_memories_cluster(arch, memories)
    return arch
end

function connect_memories_cluster(arch, memories)
    # Create metadata dictionary for the memory links.
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

    ###########################
    # Connect 1 port memories #
    ###########################
    proc_rule = x -> search_metadata!(x, "attributes", "memory_processor", in)
    mem_rule = x -> search_metadata!(x, "attributes", "memory_2port", in)

    for mem in memories
        address = mem.address
        for (i, offset) in enumerate(mem.offsets)
            # Build Request Link.    
            offset_rule = [(-offset, "memory_out", "in[$(i-1)]")]
            connection_rule(arch, offset_rule, proc_rule, mem_rule,
                            metadata = request_metadata, 
                            valid_addresses = (address + offset,))

            # Build response link.
            offset_rule = [(offset, "out[$(i-1)]", "memory_in")]
            connection_rule(arch, offset_rule, mem_rule, proc_rule,
                            metadata = response_metadata, 
                            valid_addresses = (address,))
        end
    end

    return nothing
end
