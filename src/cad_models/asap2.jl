function asap2(style)
    arch = TopLevel{2}("asap2")

    processor = build_processor_tile(style) 
    for r in 0:11, c in 0:12
        add_child(arch, processor, Address(r,c))
    end
    # Add the two processors on the bottom that are not memory processors.
    # Do not include "viterbi", "fft", or "motion estimation" for now.
    add_child(arch, processor, Address(12, 4))
    add_child(arch, processor, Address(12, 9))

    # Add the memory processors.
    memory_processor = build_processor_tile(style, include_memory = true)
    for r in 12, c in (2, 3, 5, 6, 7, 8)
        add_child(arch, memory_processor, Address(r, c))
    end

    # Add the memories. Use left corner as address.
    memory = build_memory(2)
    for r in 13, c in (2, 5, 7)
        add_child(arch, memory, Address(r, c))
    end

    input_handler = build_input_handler(12) 
    add_child(arch, input_handler, Address(0,-1))

    output_handler = build_output_handler(12)
    add_child(arch, output_handler, Address(0,13))

    connect_processors(arch, style)
    connect_memories(arch, style)
    connect_io_asap2(arch)

    return arch
end

function connect_io_asap2(arch)

    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "link_class"
    )

    # Connect input manually
    for i in 0:11
        src_address = Address(0,-1)
        dst_address = Address(i,0)
        src_name = getname(arch, src_address)
        dst_name = getname(arch, dst_address)

        src_port = Path{Port}(src_name, "out[$i]")
        dst_port = Path{Port}(dst_name, "west_in[0]")
        add_link(arch, src_port, dst_port, metadata = metadata)
    end

    # Connect output manually
    for i in 0:11
        src_address = Address(i,12)
        dst_address = Address(0,13)
        src_name = getname(arch, src_address)
        dst_name = getname(arch, dst_address)

        src_port = Path{Port}(src_name, "east_out[0]")
        dst_port = Path{Port}(dst_name, "in[$i]")
        add_link(arch, src_port, dst_port, metadata = metadata)
    end
end
