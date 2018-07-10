function asap_colmem(num_links, A, dim::Tuple{Int64,Int64}, mem_cols, vert_spacing)
    arch = TopLevel{A,2}("asap_colmem")

    # Extra parameters
    num_fifos = 2
    row = dim[1]
    col = dim[2]

    # generate memory locations according to num of mem cols and vertical spacing
    hori_spacing = floor((col-2)/(mem_cols))
    mem_rows = floor(row/(vert_spacing+2))
    memories = Array{MemoryLocation{2},1}()
    offsets = [(0,-1),(0,1)]
    prev_col = 0
    for r = 1:mem_rows
        for c = 1:mem_cols
            if (prev_col == (Int64((hori_spacing*c+1))-2)) && (prev_col != 0)
                error("$mem_cols memory columns cannot fit inside row:
                       $row and column: $col architecture.")
            end
            address = (Int64((vert_spacing+2)*r), Int64((hori_spacing*c+2)))
            other_addresses = (Int64(((vert_spacing+2)*r)+1),
                               Int64((hori_spacing*c+2)))
            m = MemoryLocation(address, other_addresses, offsets)
            push!(memories,m)
            prev_col = Int64((hori_spacing*c+1))
        end
    end

    mem_addrs = mem_addresses(memories)
    mems = mem_locations(memories)
    mem_neighbor_addrs = mem_neighbors(memories)

    ####################
    # Normal Processor #
    ####################
    processor = build_processor_tile(num_links)
    for r in 2:row+1, c in 2:col+1
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
    for mem_addr in mems
        add_child(arch, memory, mem_addr)
    end

    handler_spacing = floor(row/4)
    handler_row = (Int64(handler_spacing), Int64(handler_spacing*2),
                   Int64(handler_spacing*3), Int64(handler_spacing*4))
    #################
    # Input Handler #
    #################
    input_handler = build_input_handler(1)
    for (r,c) ∈ zip(handler_row, (1, col+2, 1, col+2))
        add_child(arch, input_handler, Address(r,c))
    end

    ##################
    # Output Handler #
    ##################
    output_handler = build_output_handler(1)
    for (r,c) ∈ zip(handler_row, (col+2, 1, col+2, 1))
        add_child(arch, output_handler, Address(r,c))
    end

    connect_processors(arch, num_links)
    connect_io(arch, num_links)
    connect_memories_colmem(arch, memories)
    connect_processors_colmem(arch, num_links)

    return arch
end

function connect_memories_colmem(arch, memories)
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

function connect_processors_colmem(tl, num_links)
    fn = x -> search_metadata!(x, "attributes", "processor", in)
    src_rule = fn
    dst_rule = fn

    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "circuit_link"
    )

    offsets = [CartesianIndex(0,2), CartesianIndex(0,-2)]
    src_dirs = ("east", "west")
    dst_dirs = ("west", "east")
    src_ports = [["$(src)_out[$i]" for i in 0:num_links-1] for src in src_dirs]
    dst_ports = [["$(dst)_in[$i]" for i in 0:num_links-1] for dst in dst_dirs]

    offset_rules = []
    for (o,s,d) in zip(offsets, src_ports, dst_ports)
        rules = [(o,i,j) for (i,j) in zip(s,d)]
        append!(offset_rules, rules)
    end

    connection_rule(tl, offset_rules, src_rule, dst_rule, metadata = metadata)
end
