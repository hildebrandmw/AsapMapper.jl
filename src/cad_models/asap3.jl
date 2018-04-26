function asap3(num_links,A)
    arch = TopLevel{A,2}("asap3")

    ####################
    # Normal Processor #
    ####################

    # Get a processor tile and instantiate it.
    processor = build_processor_tile(num_links)
    for r in 0:29, c in 0:31
        add_child(arch, processor, CartesianIndex(r,c))
    end
    for r in 30:31, c in 12:19
        add_child(arch, processor, CartesianIndex(r,c))
    end

	####################
	# Memory Processor #
	####################

	memory_processor = build_processor_tile(num_links, include_memory = true)
	for r = 30, c = 0:11
        add_child(arch, memory_processor, CartesianIndex(r,c))
	end
	for r = 30, c = 20:31
        add_child(arch, memory_processor, CartesianIndex(r,c))
	end

	#################
	# 2 Port Memory #
	#################
    memory_2port = build_memory(2)
	for r = 31, c in (0:2:10)
        add_child(arch, memory_2port, CartesianIndex(r,c))
	end
	for r = 31, c in (20:2:30)
        add_child(arch, memory_2port, CartesianIndex(r,c))
	end

	#################
	# Input Handler #
	#################
	input_handler = build_input_handler(1)
    add_child(arch, input_handler, CartesianIndex(0,-1))

	##################
	# Output Handler #
	##################
	output_handler = build_output_handler(1)
    add_child(arch, output_handler, CartesianIndex(0,32))

	connect_processors(arch,num_links)
    connect_io(arch,num_links)
	connect_memories(arch)
	return arch
end
