# Model of "Asap3" for VPR. Only big difference is that memories occupy the
# whole bottom row, instead of an isthmus of processors.

function asap3_vpr(style = Rectangular(2,1))
    arch = TopLevel{2}("asap3_vpr")

    ####################
    # Normal Processor #
    ####################

    # Get a processor tile and instantiate it.
    processor = build_processor_tile(style)
    for r in 0:29, c in 0:31
        add_child(arch, processor, CartesianIndex(r,c))
    end

	####################
	# Memory Processor #
	####################
	memory_processor = build_processor_tile(style, include_memory = true)
	for r = 30, c = 0:31
        add_child(arch, memory_processor, CartesianIndex(r,c))
	end

	#################
	# 2 Port Memory #
	#################
    memory_2port = build_memory(2)
	for r = 31, c in (0:2:30)
        add_child(arch, memory_2port, CartesianIndex(r,c))
	end

	#################
	# Input Handler #
	#################
	input_handler = build_input_handler(style)
    add_child(arch, input_handler, CartesianIndex(0,-1))

	##################
	# Output Handler #
	##################
	output_handler = build_output_handler(style)
    add_child(arch, output_handler, CartesianIndex(0,32))

	connect_processors(arch, style)
    connect_io(arch, style)
	connect_memories(arch, style)
	return arch
end
