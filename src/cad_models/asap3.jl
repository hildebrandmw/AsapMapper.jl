function asap3(style = Rectangular(2,1))
    toplevel = TopLevel{2}("asap3")

    ####################
    # Normal Processor #
    ####################

    # Get a processor tile and instantiate it.
    processor = build_processor_tile(style)
    for r in 0:29, c in 0:31
        add_child(toplevel, processor, CartesianIndex(r,c))
    end
    for r in 30:31, c in 12:19
        add_child(toplevel, processor, CartesianIndex(r,c))
    end

	####################
	# Memory Processor #
	####################

	memory_processor = build_processor_tile(style, include_memory = true)
	for r = 30, c = 0:11
        add_child(toplevel, memory_processor, CartesianIndex(r,c))
	end
	for r = 30, c = 20:31
        add_child(toplevel, memory_processor, CartesianIndex(r,c))
	end

	#################
	# 2 Port Memory #
	#################
    memory_2port = build_memory(2)
	for r = 31, c in (0:2:10)
        add_child(toplevel, memory_2port, CartesianIndex(r,c))
	end
	for r = 31, c in (20:2:30)
        add_child(toplevel, memory_2port, CartesianIndex(r,c))
	end

	#################
	# Input Handler #
	#################
	input_handler = build_input_handler(style)
    add_child(toplevel, input_handler, CartesianIndex(0,-1))

	##################
	# Output Handler #
	##################
	output_handler = build_output_handler(style)
    add_child(toplevel, output_handler, CartesianIndex(0,32))

	connect_processors(toplevel, style)
    connect_io(toplevel, style)
	connect_memories(toplevel, style)
	return toplevel
end
