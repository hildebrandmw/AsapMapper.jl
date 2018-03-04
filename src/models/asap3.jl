function asap3(num_links,A)
    make_copies = false
    arch = TopLevel{A,2}("asap3")

    ####################
    # Normal Processor #
    ####################

    # Get a processor tile and instantiate it.
    processor = build_processor_tile(num_links)
    for r in 1:30, c in 2:33
        if make_copies
            add_child(arch, deepcopy(processor), CartesianIndex(r,c))
        else
            add_child(arch, processor, CartesianIndex(r,c))
        end
    end
    for r in 31:32, c in 14:21
        if make_copies
            add_child(arch, deepcopy(processor), CartesianIndex(r,c))
        else
            add_child(arch, processor, CartesianIndex(r,c))
        end
    end

	####################
	# Memory Processor #
	####################

	memory_processor = build_memory_processor_tile(num_links)
	for r = 31, c = 2:13
        if make_copies
            add_child(arch, deepcopy(memory_processor), CartesianIndex(r,c))
        else
            add_child(arch, memory_processor, CartesianIndex(r,c))
        end
	end
	for r = 31, c = 22:33
        if make_copies
            add_child(arch, deepcopy(memory_processor), CartesianIndex(r,c))
        else
            add_child(arch, memory_processor, CartesianIndex(r,c))
        end
	end

	#################
	# 2 Port Memory #
	#################
	memory_2port = build_memory_2port()
	for r = 32, c in (2:2:12)
        add_child(arch, memory_2port, CartesianIndex(r,c))
	end
	for r = 32, c in (22:2:32)
        add_child(arch, memory_2port, CartesianIndex(r,c))
	end

	#################
	# Input Handler #
	#################
	input_handler = build_input_handler(num_links)
    add_child(arch, input_handler, CartesianIndex(1,1))

	##################
	# Output Handler #
	##################
	output_handler = build_output_handler(num_links)
    add_child(arch, output_handler, CartesianIndex(1,34))

	connect_processors(arch,num_links)
    connect_io(arch,num_links)
	connect_memories(arch)
	return arch
end
