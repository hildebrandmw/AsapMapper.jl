function asap2(num_links, A)
    arch = TopLevel{A,2}("asap2")

    processor = build_processor_tile(num_links) 
    for r in 0:11, c in 0:12
        add_child(arch, processor, CartesianIndex(r,c))
    end
    for r in 12, c in 2:9
        add_child(arch, processor, CartesianIndex(r,c))
    end

    input_handler = build_input_handler(12) 
    add_child(arch, input_handler, CartesianIndex(0,-1))

    output_handler = build_output_handler(12)
    add_child(arch, output_handler, CartesianIndex(0,13))

    connect_processors(arch, num_links)
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
        src_address = CartesianIndex(0,-1)
        dst_address = CartesianIndex(i,0)
        src_name = getname(arch, src_address)
        dst_name = getname(arch, dst_address)

        src_port = Path{Port}(src_name, "out[$i]")
        dst_port = Path{Port}(dst_name, "west_in[0]")
        add_link(arch, src_port, dst_port, metadata = metadata)
    end

    # Connect output manually
    for i in 0:11
        src_address = CartesianIndex(i,12)
        dst_address = CartesianIndex(0,13)
        src_name = getname(arch, src_address)
        dst_name = getname(arch, dst_address)

        src_port = Path{Port}(src_name, "east_out[0]")
        dst_port = Path{Port}(dst_name, "in[$i]")
        add_link(arch, src_port, dst_port, metadata = metadata)
    end
end
