function asap3_exp(nlinks, A)
    fill = AsapProc(nlinks)
    dims = (32, 32)

    special = []

    # Input handlers
    ih = InputHandler(nlinks)
    ih_locations = TileLocation{2}((2,1), (0,1))
    push!(special, InstDef(ih, [ih_locations]))

    # Output Handler
    oh = OutputHandler(nlinks)
    oh_locations = TileLocation{2}((2,32), (0,-1))
    push!(special, InstDef(oh, [oh_locations]))

    # Memories - inform that there is a processor neighbor.
    mem = Memory(2, AsapProc(nlinks, memory = true))
    mem_locs = [TileLocation{2}((33,c),[(-1,0),(-1,1)]) for c in chain(2:2:12, 22:2:32)]
    push!(special, InstDef(mem, mem_locs))

    build(A, "asap3", special, fill, dims)
end

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
