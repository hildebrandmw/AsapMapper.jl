function asap4(num_links, A)
    multiple_copies = true
    # Start with a new component - clarify that it is 2 dimensional
    arch = TopLevel{A,2}("asap4")

    num_fifos = 2
    ####################
    # Normal Processor #
    ####################
    # Get a processor tile to instantiate.
    processor = build_processor_tile(num_links)
    # Instantiate it at the required addresses
    for r in 1:24, c in 2:28
        if multiple_copies
            add_child(arch, deepcopy(processor), Address(r,c))
        else
            add_child(arch, processor, Address(r,c))
        end
    end
    for r in 1:20, c in 29
        if multiple_copies
            add_child(arch, deepcopy(processor), Address(r,c))
        else
            add_child(arch, processor, Address(r,c))
        end
    end

    ####################
    # Memory Processor #
    ####################
    memory_processor = build_memory_processor_tile(num_links)
    for r = 25, c = 2:28
        if multiple_copies
            add_child(arch, deepcopy(memory_processor), Address(r,c))
        else
            add_child(arch, memory_processor, Address(r,c))
        end
    end
    #################
    # 2 Port Memory #
    #################
    memory_2port = build_memory_2port()
    for r = 26, c in (2, 4, 6, 8, 11, 13, 15, 17, 20, 22, 24, 26)
        add_child(arch, memory_2port, Address(r,c))
    end
    #################
    # 1 Port Memory #
    #################
    memory_1port = build_memory_1port()
    for r = 26, c in (10, 19)
        add_child(arch, memory_1port, Address(r,c))
    end
    #################
    # Input Handler #
    #################
    input_handler = build_input_handler(num_links)
    for r ∈ (1, 13), c = 1
        add_child(arch, input_handler, Address(r,c))
    end
    for r ∈ (12, 18), c = 30
        add_child(arch, input_handler, Address(r,c))
    end
    ##################
    # Output Handler #
    ##################
    output_handler = build_output_handler(num_links)
    for (r,c) ∈ zip((12,18,1,14), (1, 1, 30, 30))
        add_child(arch, output_handler, Address(r,c))
    end

    #######################
    # Global Interconnect #
    #######################
    connect_processors(arch, num_links)
    connect_memories(arch)
    return arch
end

function connect_processors(tl, num_links)
    # General rule - we're looking for the attribute "processor" to be somewhere
    # in the component stack. If so, we'll try to connect all of the circuit
    # switched ports.
    src_key = "attributes"
    src_val = ["processor", "input_handler", "output_handler"]
    src_fn = oneofin
    src_rule = PortRule(src_key, src_val, src_fn)
    dst_rule = src_rule
    # Create offset rules.
    # Offsets are just unit steps in four directions.
    offsets = [Address(-1,0), Address(1,0), Address(0,1), Address(0,-1)]
    #=
    Create two tuples for the source ports and destination ports. In general,
    if the source link is going out of the north port, the destionation will
    be coming in the south port.
    =#
    src_dirs = ("north", "south", "east", "west")
    dst_dirs = ("south", "north", "west", "east")
    offset_rules = OffsetRule[]
    for (offset, src, dst) in zip(offsets, src_dirs, dst_dirs)
        src_ports = ["$(src)_out[$i]" for i in 0:num_links-1]
        dst_ports = ["$(dst)_in[$i]" for i in 0:num_links-1]
        # Create the offset rule and add it to the collection
        new_rule = OffsetRule([offset], src_ports, dst_ports)
        push!(offset_rules, new_rule)
    end
    # Create offset rules for the input and output handlers.
    # Input and output handlers only appear on the left and right hand sides
    # of the array, so only need the "east" and "west" directions.
    src_dirs = ("east","west")
    dst_dirs = ("west","east")
    # Links can go both directions, so make the offsets an array
    offsets = [Address(0,1), Address(0,-1)]
    for (offset, src, dst) in zip(offsets, src_dirs, dst_dirs)
        src_ports = ["out[$i]" for i in 0:num_links-1]
        append!(src_ports, ["$(src)_out[$i]" for i in 0:num_links-1])

        dst_ports = ["$(dst)_in[$i]" for i in 0:num_links-1]
        append!(dst_ports, ["in[$i]" for i in 0:num_links-1])
        
        new_rule = OffsetRule([offset], src_ports, dst_ports)
        push!(offset_rules, new_rule)
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
    # Create rule for the memory processors
    proc_key = "attributes"
    proc_val = "memory_processor"
    proc_fn = in
    proc_rule = PortRule(proc_key, proc_val, proc_fn)
    # Create rule for the 2-port memories.
    mem_key = "attributes"
    mem_val = "memory_2port"
    mem_fn  = in
    mem_rule = PortRule(mem_key, mem_val, mem_fn)
    # Make connections from memory to memory-processors
    offset_rules = OffsetRule[]
    push!(offset_rules, OffsetRule(Address(-1,0), "out[0]", "memory_in"))
    push!(offset_rules, OffsetRule(Address(-1,1), "out[1]", "memory_in"))
    connection_rule(tl, offset_rules, mem_rule, proc_rule, metadata = metadata)
    # Make connections from memory-processors to memories.
    offset_rules = OffsetRule[]
    push!(offset_rules, OffsetRule(Address(1,0), "memory_out", "in[0]"))
    push!(offset_rules, OffsetRule(Address(1,-1), "memory_out", "in[1]"))
    connection_rule(tl, offset_rules, proc_rule, mem_rule, metadata = metadata)

    ########################### 
    # Connect 1 port memories #
    ########################### 
    # Change the memory attribute requirement to a 1 port memory.
    mem_val = "memory_1port"
    mem_rule = PortRule(mem_key, mem_val, mem_fn)
    # Make connections from memory to memory-processors
    offset_rules = OffsetRule[]
    push!(offset_rules, OffsetRule(Address(-1,0), "out[0]", "memory_in"))
    connection_rule(tl, offset_rules, mem_rule, proc_rule, metadata = metadata)
    # Make connections from memory-processors to memories.
    offset_rules = OffsetRule[]
    push!(offset_rules, OffsetRule(Address(1,0), "memory_out", "in[0]"))
    connection_rule(tl, offset_rules, proc_rule, mem_rule, metadata = metadata)

    return nothing
end
