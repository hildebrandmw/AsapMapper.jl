function asap3(num_links,A)
    arch = TopLevel{A,2}("asap3")

    ####################
    # Normal Processor #
    ####################

    # Get a processor tile and instantiate it.
    processor = build_processor_tile(num_links)
    for r in 2:31, c in 2:33
        add_child(arch, processor, CartesianIndex(r,c))
    end
    for r in 32:33, c in 14:21
        add_child(arch, processor, CartesianIndex(r,c))
    end

	####################
	# Memory Processor #
	####################

	memory_processor = build_processor_tile(num_links, include_memory = true)
	for r = 32, c = 2:13
        add_child(arch, memory_processor, CartesianIndex(r,c))
	end
	for r = 32, c = 22:33
        add_child(arch, memory_processor, CartesianIndex(r,c))
	end

	#################
	# 2 Port Memory #
	#################
    memory_2port = build_memory(2)
	for r = 33, c in (2:2:12)
        add_child(arch, memory_2port, CartesianIndex(r,c))
	end
	for r = 33, c in (22:2:32)
        add_child(arch, memory_2port, CartesianIndex(r,c))
	end

	#################
	# Input Handler #
	#################
	input_handler = build_input_handler(1)
    add_child(arch, input_handler, CartesianIndex(2,1))

	##################
	# Output Handler #
	##################
	output_handler = build_output_handler(1)
    add_child(arch, output_handler, CartesianIndex(2,34))

	connect_processors(arch,num_links)
    connect_io(arch,num_links)
	connect_memories(arch)
	return arch
end
