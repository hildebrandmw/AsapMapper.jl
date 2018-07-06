function asap3_hex(num_links, A)
    # Start with a new component - clarify that it is 2 dimensional
    arch = TopLevel{A,2}("asap3_hex")

    #############
    # Processor #
    #############
    processor = build_processor_tile(num_links, ishex = true)
    # Instantiate
    for r = 1:30, c = 2:33
       add_child(arch, processor, Address(r,c))
    end
    for r = 31:32, c = 14:21
       add_child(arch, processor, Address(r,c))
    end

    ####################
    # Memory Processor #
    ####################
    memory_processor = build_memory_processor_tile(num_links, ishex = true)

    for r = 31, c = chain(2:13, 22:33)
        add_child(arch, memory_processor, Address(r,c))
	end

    ############
    # Memories #
    ############
	memory_2port = build_memory_2port()
    for r = 32, c in chain(3:2:13, 23:2:33)
        add_child(arch, memory_2port, Address(r,c))
	end

	#################
	# Input Handler #
	#################
	input_handler = build_input_handler(num_links)
    add_child(arch, input_handler, Address(1,1))

	##################
	# Output Handler #
	##################
	output_handler = build_output_handler(num_links)
    add_child(arch, output_handler, Address(1,34))

    connect_hex_processors(arch, num_links)
    connect_hex_io(arch, num_links)
    connect_hex_memory(arch)
    return arch
end

function connect_hex_processors(t, num_links)

    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"      => 1.0,
        "capacity"  => 1,
        "network"   => ["circuit_switched"]
    )
    # Set up source and destination rules
    src_key = "attributes"
    src_val = ["processor"]
    src_fn  = oneofin
    src_rule = PortRule(src_key, src_val, src_fn)
    dst_rule = src_rule

    # Apply different rules for even and odd columns

    # Even Columns
    offsets = Address.([(0,1),(-1,0),(0,-1),(1,-1),(1,0),(1,1)])
    src_dirs = ( "30",  "90", "150", "210", "270", "330")
    dst_dirs = ("210", "270", "330",  "30",  "90", "150")
    offset_rules = OffsetRule[]
    for (offset, src, dst) in zip(offsets, src_dirs, dst_dirs)
        src_ports = ["$(src)_out[$i]" for i in 0:num_links-1]
        dst_ports = ["$(dst)_in[$i]" for i in 0:num_links-1]
        # Create the offset rule and add it to the collection
        new_rule = OffsetRule([offset], src_ports, dst_ports)
        push!(offset_rules, new_rule)
    end
    even_addresses = Iterators.filter(x -> iseven(x[2]), addresses(t))
    println("Connecting Even Column Processors")
    connection_rule(t, 
                    offset_rules, 
                    src_rule, 
                    dst_rule,
                    valid_addresses = even_addresses,
                    metadata = metadata)
    # Odd Colunns
    offsets = Address.([(-1,1),(-1,0),(-1,-1),(0,-1),(1,0),(0,1)])
    offset_rules = OffsetRule[]
    for (offset, src, dst) in zip(offsets, src_dirs, dst_dirs)
        src_ports = ["$(src)_out[$i]" for i in 0:num_links-1]
        dst_ports = ["$(dst)_in[$i]" for i in 0:num_links-1]
        # Create the offset rule and add it to the collection
        new_rule = OffsetRule([offset], src_ports, dst_ports)
        push!(offset_rules, new_rule)
    end
    odd_addresses = Iterators.filter(x -> isodd(x[2]), addresses(t))
    println("Connecting Odd Column Processors")
    connection_rule(t, 
                    offset_rules, 
                    src_rule, 
                    dst_rule,
                    valid_addresses = odd_addresses,
                    metadata = metadata)
end

function connect_hex_io(t, num_links)
    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"      => 1.0,
        "capacity"  => 1,
        "network"   => ["circuit_switched"]
    )
    # Set up source and destination rules
    src_key = "attributes"
    src_val = ["processor", "input_handler", "output_handler"]
    src_fn  = oneofin
    src_rule = PortRule(src_key, src_val, src_fn)
    dst_rule = src_rule
    
    src_dirs = ( "30", "330", "150", "210")
    dst_dirs = ("210", "150", "330",  "30")

    even_offsets = Address.([(0,1),(1,1),(0,-1),(1,-1)])
    odd_offsets  = Address.([(-1,1),(0,1),(-1,-1),(0,-1)])
    offset_iter  = (even_offsets, odd_offsets)
    fn_iter      = (iseven, isodd)
    for (offsets,fn) in zip(offset_iter, fn_iter)
        println(offsets)
        println(string(fn))
        offset_rules = OffsetRule[]
        for (offset, src, dst) in zip(offsets, src_dirs, dst_dirs)
            src_ports = ["out[$i]" for i in 0:num_links-1]
            append!(src_ports, ["$(src)_out[$i]" for i in 0:num_links-1])

            dst_ports = ["$(dst)_in[$i]" for i in 0:num_links-1]
            append!(dst_ports, ["in[$i]" for i in 0:num_links-1])
            
            new_rule = OffsetRule([offset], src_ports, dst_ports)
            push!(offset_rules, new_rule)
        end
        valid_addresses = Iterators.filter(x -> fn(x[2]), addresses(t))
        connection_rule(t,
                        offset_rules,
                        src_rule,
                        dst_rule,
                        valid_addresses = valid_addresses,
                        metadata = metadata,
                       )
    end
    return nothing
end

function connect_hex_memory(t)
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
    push!(offset_rules, OffsetRule(Address(-1,-1), "out[0]", "memory_in"))
    push!(offset_rules, OffsetRule(Address(-1,0), "out[1]", "memory_in"))
    connection_rule(t, offset_rules, mem_rule, proc_rule, metadata = metadata)
    # Make connections from memory-processors to memories.
    offset_rules = OffsetRule[]
    push!(offset_rules, OffsetRule(Address(1,1), "memory_out", "in[0]"))
    push!(offset_rules, OffsetRule(Address(1,0), "memory_out", "in[1]"))
    connection_rule(t, offset_rules, proc_rule, mem_rule, metadata = metadata)

end
