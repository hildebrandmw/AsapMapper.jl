function asap3_hex(A, num_links)
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
    src_val = ["processor", "input_handler", "output_handler"]
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
    connection_rule(t, 
                    offset_rules, 
                    src_rule, 
                    dst_rule,
                    valid_addresses = even_addresses,
                    metadata = metadata)
    # Odd Colunns
    offsets = Address.([(-1,1),(-1,0),(-1,-1),(0,-1),(1,0),(0,1)])
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
    odd_addresses = Iterators.filter(x -> isodd(x[2]), addresses(t))
    connection_rule(t, 
                    offset_rules, 
                    src_rule, 
                    dst_rule,
                    valid_addresses = odd_addresses,
                    metadata = metadata)
end
