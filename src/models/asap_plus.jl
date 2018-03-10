function asap_plus(num_links, A)
    multiple_copies = true
    arch = TopLevel{A,2}("asap_plus")

    # Extra parameters
    num_fifos = 2
    mem_dict = Dict([(16,5),(17,5)] => [(15,5),(18,5)],
                    [(16,10),(17,10)] => [(15,10),(18,10)],
                    [(16,15),(17,15)] => [(15,15),(18,15)],
                    [(16,20),(17,20)] => [(15,20),(18,20)],
                    [(16,25),(17,25)] => [(15,25),(18,25)],
                    [(16,30),(17,30)] => [(15,30),(18,30)],
                    [(4,17),(4,18)] => [(4,16),(4,19)],
                    [(9,17),(9,18)] => [(9,16),(9,19)],
                    [(14,17),(14,18)] => [(14,16),(14,19)],
                    [(19,17),(19,18)] => [(19,16),(19,19)],
                    [(24,17),(24,18)] => [(24,16),(24,19)],
                    [(29,17),(29,18)] => [(29,16),(29,19)])

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
    connect_memories_plus(arch)
    return arch
end

function connect_memories_plus(tl)
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
                   (CartesianIndex(1,0), "out[0]", "memory_in"),
                   (CartesianIndex(0,-1), "out[0]", "memory_in"),
                   (CartesianIndex(0,1), "out[0]", "memory_in"),]
    connection_rule(tl, offset_rule, mem1_rule, proc_rule, metadata = metadata)

    offset_rule = [(CartesianIndex(1,0), "memory_out", "in[0]"),
                   (CartesianIndex(-1,0), "memory_out", "in[0]"),
                   (CartesianIndex(0,1), "out[0]", "memory_in"),
                   (CartesianIndex(0,-1), "out[0]", "memory_in"),]
    connection_rule(tl, offset_rule, proc_rule, mem1_rule, metadata = metadata)

    return nothing
end
