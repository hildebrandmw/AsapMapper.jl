function asap4(num_links, A)
    multiple_copies = true
    arch = TopLevel{A,2}("asap4")

    # Extra parameters
    num_fifos = 2

    ####################
    # Normal Processor #
    ####################
    processor = build_processor_tile(num_links)
    for r in 2:25, c in 2:28
        if multiple_copies
            add_child(arch, deepcopy(processor), CartesianIndex(r,c))
        else
            add_child(arch, processor, CartesianIndex(r,c))
        end
    end
    for r in 2:21, c in 29
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
    for r = 26, c = 2:28
        if multiple_copies
            add_child(arch, deepcopy(memory_processor), CartesianIndex(r,c))
        else
            add_child(arch, memory_processor, CartesianIndex(r,c))
        end
    end

    #################
    # 2 Port Memory #
    #################
    memory_2port = build_memory_2port()
    for r = 27, c in (2, 4, 6, 8, 11, 13, 15, 17, 20, 22, 24, 26)
        add_child(arch, memory_2port, CartesianIndex(r,c))
    end

    #################
    # 1 Port Memory #
    #################
    memory_1port = build_memory_1port()
    for r = 27, c in (10, 19)
        add_child(arch, memory_1port, CartesianIndex(r,c))
    end

    #################
    # Input Handler #
    #################
    input_handler = build_input_handler(num_links)
    for (r,c) ∈ zip((2,13,15,19), (1, 30, 1, 30))
        add_child(arch, input_handler, CartesianIndex(r,c))
    end
    ##################
    # Output Handler #
    ##################
    output_handler = build_output_handler(num_links)
    for (r,c) ∈ zip((2,13,15,19), (30, 1, 30, 1))
        add_child(arch, output_handler, CartesianIndex(r,c))
    end

    #######################
    # Global Interconnect #
    #######################
    connect_processors(arch, num_links)
    connect_io(arch, num_links)
    connect_memories(arch)
    return arch
end

function connect_processors(tl, num_links)

    vals = ["processor", "input_handler", "output_handler"]
    fn = x -> search_metadata!(x, "attributes", vals, oneofin)
    src_rule = fn
    dst_rule = fn

    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"      => 1.0,
        "capacity"  => 1,
        "network"   => ["circuit_switched"]
    )

    # Create offset rules.
    offsets = [CartesianIndex(-1,0), 
               CartesianIndex(1,0), 
               CartesianIndex(0,1), 
               CartesianIndex(0,-1)]
    #=
    Create two tuples for the source ports and destination ports. In general,
    if the source link is going out of the north port, the destionation will
    be coming in the south port.
    =#
    src_dirs = ("north", "south", "east", "west")
    dst_dirs = ("south", "north", "west", "east")

    src_ports = [["$(src)_out[$i]" for i in 0:num_links-1] for src in src_dirs]
    dst_ports = [["$(dst)_in[$i]" for i in 0:num_links-1] for dst in dst_dirs]

    offset_rules = []
    for (o,s,d) in zip(offsets, src_ports, dst_ports)
        rules = [(o,i,j) for (i,j) in zip(s,d)]
        append!(offset_rules, rules)
    end
    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"      => 1.0,
        "capacity"  => 1,
        "network"   => ["circuit_switched"]
    )

    connection_rule(tl, offset_rules, src_rule, dst_rule, metadata = metadata)
end

function connect_io(tl, num_links)

    vals = ["processor", "input_handler", "output_handler"]
    fn = x -> search_metadata!(x, "attributes", vals, oneofin)
    src_rule = fn
    dst_rule = fn

    src_dirs = ("east","west")
    dst_dirs = ("west","east")
    # Links can go both directions, so make the offsets an array
    offsets = [CartesianIndex(0,1), CartesianIndex(0,-1)]

    offset_rules = []
    for offset in offsets
        for (src,dst) in zip(src_dirs, dst_dirs)
            src_ports = ["out[$i]" for i in 0:num_links-1]
            append!(src_ports, ["$(src)_out[$i]" for i in 0:num_links-1])

            dst_ports = ["$(dst)_in[$i]" for i in 0:num_links-1]
            append!(dst_ports, ["in[$i]" for i in 0:num_links-1])
            
            new_rule = [(offset, s, d) for (s,d) in zip(src_ports, dst_ports)]
            append!(offset_rules, new_rule)
        end
    end
    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"      => 1.0,
        "capacity"  => 1,
        "network"   => ["circuit_switched"]
    )
    # Launch the function call!
    connection_rule(tl, offset_rules, src_rule, dst_rule, metadata = metadata)
    return nothing
end

function connect_memories(tl)
    # Create metadata dictionary for the memory links.
    metadata = Dict(
        "cost"      => 1.0,
        "capacity"  => 1,
        "network"   => ["memory"],
   )
    ########################### 
    # Connect 2 port memories #
    ########################### 

    proc_rule = x -> search_metadata!(x, "attributes", "memory_processor", in)
    mem2_rule  = x -> search_metadata!(x, "attributes", "memory_2port", in)


    offset_rules = [
        (CartesianIndex(-1,0), "out[0]", "memory_in"),
        (CartesianIndex(-1,1), "out[1]", "memory_in"),
    ]
    connection_rule(tl, offset_rules, mem2_rule, proc_rule, metadata = metadata)

    offset_rules = [
        (CartesianIndex(1,0), "memory_out", "in[0]"),
        (CartesianIndex(1,-1), "memory_out", "in[1]")
    ]

    connection_rule(tl, offset_rules, proc_rule, mem2_rule, metadata = metadata)

    ########################### 
    # Connect 1 port memories #
    ########################### 
    mem1_rule = x -> search_metadata!(x, "attributes", "memory_1port", in)

    offset_rule = [(CartesianIndex(-1,0), "out[0]", "memory_in")]
    connection_rule(tl, offset_rule, mem1_rule, proc_rule, metadata = metadata)

    offset_rule = [(CartesianIndex(1,0), "memory_out", "in[0]")]
    connection_rule(tl, offset_rule, proc_rule, mem1_rule, metadata = metadata)

    return nothing
end
