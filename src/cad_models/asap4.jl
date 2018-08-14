function asap4(style)
    arch = TopLevel{2}("asap4")

    # Extra parameters
    num_fifos = 2

    ####################
    # Normal Processor #
    ####################
    processor = build_processor_tile(style)
    for r in 0:23, c in 0:26
        add_child(arch, processor, CartesianIndex(r,c))
    end
    for r in 0:19, c in 27
        add_child(arch, processor, CartesianIndex(r,c))
    end

    ####################
    # Memory Processor #
    ####################
    memory_processor = build_processor_tile(style, include_memory = true)
    for r = 24, c = 0:26
        add_child(arch, memory_processor, CartesianIndex(r,c))
    end

    #################
    # 2 Port Memory #
    #################
    memory_2port = build_memory(2)
    for r = 25, c in (0, 2, 4, 6, 9, 11, 13, 15, 18, 20, 22, 24)
        add_child(arch, memory_2port, CartesianIndex(r,c))
    end

    #################
    # 1 Port Memory #
    #################
    memory_1port = build_memory(1)
    for r = 25, c in (8, 17)
        add_child(arch, memory_1port, CartesianIndex(r,c))
    end

    #################
    # Input Handler #
    #################
    input_handler = build_input_handler(1)
    for (r,c) ∈ zip((0,11,13,17), (-1, 28, -1, 28))
        add_child(arch, input_handler, CartesianIndex(r,c))
    end
    ##################
    # Output Handler #
    ##################
    output_handler = build_output_handler(1)
    for (r,c) ∈ zip((0,11,13,17), (28, -1, 28, -1))
        add_child(arch, output_handler, CartesianIndex(r,c))
    end

    #######################
    # Global Interconnect #
    #######################
    connect_processors(arch, style)
    connect_io(arch, style)
    connect_memories(arch, style)
    return arch
end
