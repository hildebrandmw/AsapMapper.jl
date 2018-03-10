function asap_cluster(num_links, A)
    multiple_copies = true
    arch = TopLevel{A,2}("asap_cluster")

    # Extra parameters
    num_fifos = 2
    mem_dict = Dict([(9, 8), (9, 9)]        => [(10, 8), (10, 9)],
                    [(25, 26), (25, 27)]    => [(26, 26), (26, 27)],
                    [(24, 10), (24, 11)]    => [(23, 10), (23, 11)],
                    [(8, 26), (8, 27)]      => [(7, 26), (7, 27)],
                    [(24, 8), (24, 9)]      => [(23, 8), (23, 9)],
                    [(25, 8), (25, 9)]      => [(26, 8), (26, 9)],
                    [(9, 26), (9, 27)]      => [(10, 26), (10, 27)],
                    [(9, 24), (9, 25)]      => [(10, 24), (10, 25)],
                    [(9, 10), (9, 11)]      => [(10, 10), (10, 11)],
                    [(8, 10), (8, 11)]      => [(7, 10), (7, 11)],
                    [(8, 24), (8, 25)]      => [(7, 24), (7, 25)],
                    [(24, 24), (24, 25)]    => [(23, 24), (23, 25)],
                    [(25, 24), (25, 25)]    => [(26, 24), (26, 25)],
                    [(24, 26), (24, 27)]    => [(23, 26), (23, 27)],
                    [(25, 10), (25, 11)]    => [(26, 10), (26, 11)],
                    [(8, 8), (8, 9)]        => [(7, 8), (7, 9)])

    mem_addrs = Array{Tuple{Int64,Int64},1}()
    mem_neighbor_addrs = Array{Tuple{Int64,Int64},1}()
    for (keys,values) in mem_dict
        for key in keys
            push!(mem_addrs,key)
        end
        for value in values
            push!(mem_neighbor_addrs,value)
        end
    end

    ####################
    # Normal Processor #
    ####################
    processor = build_processor_tile(num_links)
    for r in 1:32, c in 2:33
        in((r,c),mem_addrs) && continue
        in((r,c),mem_neighbor_addrs) && continue
        if multiple_copies
            add_child(arch, deepcopy(processor), CartesianIndex(r,c))
        else
            add_child(arch, processor, CartesianIndex(r,c))
        end
    end

    ####################
    # Memory Processor #
    ####################
    memory_processor = build_memory_processor_tile(num_links)
    for mem_neighbor_addr in mem_neighbor_addrs
        if multiple_copies
            add_child(arch, deepcopy(memory_processor),
                    CartesianIndex(mem_neighbor_addr[1],mem_neighbor_addr[2]))
        else
            add_child(arch, memory_processor,
                    CartesianIndex(mem_neighbor_addr[1],mem_neighbor_addr[2]))
        end
    end

    #################
    # 1 Port Memory #
    #################
    memory_1port = build_memory_1port()
    for mem_addr in mem_addrs
        add_child(arch, memory_1port, CartesianIndex(mem_addr[1],mem_addr[2]))
    end

    #################
    # Input Handler #
    #################
    input_handler = build_input_handler(num_links)
    for r ∈ (1, 13), c = 1
        add_child(arch, input_handler, CartesianIndex(r,c))
    end
    for r ∈ (12, 18), c = 34
        add_child(arch, input_handler, CartesianIndex(r,c))
    end

    ##################
    # Output Handler #
    ##################
    output_handler = build_output_handler(num_links)
    for (r,c) ∈ zip((12,18,1,14), (1, 1, 34, 34))
        add_child(arch, output_handler, CartesianIndex(r,c))
    end

    #######################
    # Global Interconnect #
    #######################
    connect_processors(arch, num_links)
    connect_io(arch, num_links)
    connect_memories_cluster(arch)
    return arch
end

function connect_memories_cluster(tl)
    # Create metadata dictionary for the memory links.
    metadata = Dict(
        "cost"      => 1.0,
        "capacity"  => 1,
        "network"   => ["memory"],
   )

    ###########################
    # Connect 1 port memories #
    ###########################
    proc_rule = x -> search_metadata!(x, "attributes", "memory_processor", in)
    mem1_rule = x -> search_metadata!(x, "attributes", "memory_1port", in)

    offset_rule = [(CartesianIndex(-1,0), "out[0]", "memory_in"),
                   (CartesianIndex(1,0), "out[0]", "memory_in")]
    connection_rule(tl, offset_rule, mem1_rule, proc_rule, metadata = metadata)

    offset_rule = [(CartesianIndex(1,0), "memory_out", "in[0]"),
                   (CartesianIndex(-1,0), "memory_out", "in[0]")]
    connection_rule(tl, offset_rule, proc_rule, mem1_rule, metadata = metadata)

    return nothing
end
