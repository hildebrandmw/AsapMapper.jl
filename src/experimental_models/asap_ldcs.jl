function asap_ldcs(num_links, A)
	multiple_copies = true
	arch = TopLevel{A,2}("asap_ldcs")

	# Extra parameters
	num_fifos = 2

	# address for long distance circuit switched link processsors
	ldcs_proc_addrs = [(5,8),(15,8),(5,22),(15,22),(5,10),(5,20),(15,10),(15,20)]

    ####################
    # Normal Processor #
    ####################
    processor = build_processor_tile(num_links)
    for r in 1:24, c in 2:28
		in((r,c), ldcs_proc_addrs) && continue
        if multiple_copies
            add_child(arch, deepcopy(processor), CartesianIndex(r,c))
        else
            add_child(arch, processor, CartesianIndex(r,c))
        end
    end
    for r in 1:20, c in 29
		in((r,c), ldcs_proc_addrs) && continue
        if multiple_copies
            add_child(arch, deepcopy(processor), CartesianIndex(r,c))
        else
            add_child(arch, processor, CartesianIndex(r,c))
        end
    end

	#################################################
    # Long Distance Circuit Switched Link Processor #
    #################################################
    processor = build_ldcs_processor_tile(num_links)
    for ldcs_proc_addr in ldcs_proc_addrs
        if multiple_copies
            add_child(arch, deepcopy(processor), CartesianIndex(ldcs_proc_addr[1],ldcs_proc_addr[2]))
        else
            add_child(arch, processor, CartesianIndex(ldcs_proc_addr[1],ldcs_proc_addr[2]))
        end
    end

    ####################
    # Memory Processor #
    ####################
    memory_processor = build_memory_processor_tile(num_links)
    for r = 25, c = 2:28
        if multiple_copies
            add_child(arch, deepcopy(memory_processor), CartesianIndex(r,c))
        else
            add_child(arch, memory_processor, CartesianIndex(r,c))
        end
    end

    #################
    # 2 Port Memory #
    #################
    memory_2port = build_memory_2port()
    for r = 26, c in (2, 4, 6, 8, 11, 13, 15, 17, 20, 22, 24, 26)
        add_child(arch, memory_2port, CartesianIndex(r,c))
    end

    #################
    # 1 Port Memory #
    #################
    memory_1port = build_memory_1port()
    for r = 26, c in (10, 19)
        add_child(arch, memory_1port, CartesianIndex(r,c))
    end

    #################
    # Input Handler #
    #################
    input_handler = build_input_handler(num_links)
    for r ∈ (1, 13), c = 1
        add_child(arch, input_handler, CartesianIndex(r,c))
    end
    for r ∈ (12, 18), c = 30
        add_child(arch, input_handler, CartesianIndex(r,c))
    end

    ##################
    # Output Handler #
    ##################
    output_handler = build_output_handler(num_links)
    for (r,c) ∈ zip((12,18,1,14), (1, 1, 30, 30))
        add_child(arch, output_handler, CartesianIndex(r,c))
    end

    #######################
    # Global Interconnect #
    #######################
    connect_asap_ldcs_processors(arch, num_links)
    connect_io(arch, num_links)
    connect_memories(arch)
    return arch
end

function build_ldcs_processor_tile(num_links,
                              name = "ldcs_processor_tile",
                              include_memory = false;
                              directions = ("east", "north", "south", "west"),
                             )
    num_fifos = 2
    # Create a new component for the processor tile
    # No need to set the primtiive class or metadata because we won't
    # be needing it.
    comp = Component(name)
    # Add the circuit switched ports
    for dir in directions
        for (suffix,class)  in zip(("_in", "_out"), ("input", "output"))
            port_name = join((dir, suffix))
            metadata = make_port_metadata(dir, class, num_links)
            add_port(comp, port_name, class, num_links, metadata = metadata)
        end
    end
    for (suffix,class)  in zip(("_in", "_out"), ("input", "output"))
        port_name = join(("ldcs", suffix))
        metadata = make_port_metadata("ldcs", class, num_links)
        add_port(comp, port_name, class, num_links, metadata = metadata)
    end
    # Instantiate the processor primitive
    add_child(comp, build_processor(num_links, include_memory), "processor")

    # Instantiate the directional routing muxes
    routing_mux = build_mux((length(directions)+1),1)
    for dir in directions
        name = "$(dir)_mux"
        add_child(comp, routing_mux, name, num_links)
    end
	# Instantiate the ldcs routing muxes
    routing_mux = build_mux((length(directions)+1),1)
    add_child(comp, routing_mux, "ldcs_mux", num_links)
    # Instantiate the muxes routing data to the fifos
    num_fifo_entries = (length(directions)+1) * num_links + 1
    add_child(comp, build_mux(num_fifo_entries,1), "fifo_mux", num_fifos)
    # Add memory ports - only memory processor tiles will have the necessary
    # "memory_processor" attribute in the core to allow memory application
    # to be mapped to them.
    # Interconnect - Don't attach metadata and let the routing routine fill in
    # defaults to intra-tile routing.
    if include_memory
        metadata = make_port_metadata()
        add_port(comp, "memory_in", "input", metadata = metadata)
        add_port(comp, "memory_out", "output", metadata = metadata)
        add_link(comp, "processor.memory_out", "memory_out")
        add_link(comp, "memory_in", "processor.memory_in")
    end

    # Connect outputs of muxes to the tile outputs
    for dir in directions, i = 0:num_links-1
        mux_port = "$(dir)_mux[$i].out[0]"
        tile_port = "$(dir)_out[$i]"
        add_link(comp, mux_port, tile_port)
    end

    for i = 0:num_links-1
        mux_port = "ldcs_mux[$i].out[0]"
        tile_port = "ldcs_out[$i]"
        add_link(comp, mux_port, tile_port)
    end

    # Circuit switch output links
    for dir in directions, i = 0:num_links-1
        # Make the name for the processor.
        proc_port = "processor.$dir[$i]"
        mux_port = "$(dir)_mux[$i].in[0]"
        add_link(comp, proc_port, mux_port)
    end

    # Connect input fifos.
    for i = 0:num_fifos-1
        fifo_port = "fifo_mux[$i].out[0]"
        proc_port = "processor.fifo[$i]"
        add_link(comp, fifo_port, proc_port)
    end

    directions = ("east", "north", "south", "west", "ldcs")

    index_tracker = Dict((d,i) => 1 for d in directions, i in 0:num_links)
    # Add entries for the fifo
    for i in 0:num_fifos
        index_tracker[("fifo",i)] = 0
    end
    for dir in directions
        for i in 0:num_links-1
            # Create a source port for the tile input.
            source_port = "$(dir)_in[$i]"
            # Begin adding sink ports.
            # Need one for each mux on this layer and num_fifos for each of
            # the input fifos.
            sink_ports = String[]
            # Go through all fifos that directions that are not the current
            # directions.
            for d in Iterators.filter(x -> x != dir, directions)
                # Get the next free port for this mux.
                key = (d,i)
                index = index_tracker[key]
                mux_port = "$(d)_mux[$i].in[$index]"
                # Add this port to the list of sink ports
                push!(sink_ports, mux_port)
                # increment the index tracker
                index_tracker[key] += 1
            end
            # Add the fifo mux entries.
            for j = 0:num_fifos-1
                key = ("fifo", j)
                index = index_tracker[key]
                fifo_port = "fifo_mux[$j].in[$index]"
                push!(sink_ports, fifo_port)
                index_tracker[key] += 1
            end
            # Add the connection to the component.
            add_link(comp, source_port, sink_ports)
        end
    end

    check(comp)
    return comp
end

function connect_asap_ldcs_processors(tl, num_links)

    vals = ["processor", "input_handler", "output_handler"]
    fn = x -> search_metadata!(x, "attributes", vals, oneofin)
    src_rule = fn
    dst_rule = fn

    # Create offset rules.
    offsets = [CartesianIndex(-1,0),
               CartesianIndex(1,0),
               CartesianIndex(0,1),
               CartesianIndex(0,-1),
			   CartesianIndex(-10,0),
			   CartesianIndex(10,0),
			   CartesianIndex(0,-10),
			   CartesianIndex(0,10),]
    #=
    Create two tuples for the source ports and destination ports. In general,
    if the source link is going out of the north port, the destionation will
    be coming in the south port.
    =#
    src_dirs = ("north", "south", "east", "west", "ldcs", "ldcs", "ldcs", "ldcs")
    dst_dirs = ("south", "north", "west", "east", "ldcs", "ldcs", "ldcs", "ldcs")

    src_ports = [["$(src)_out[$i]" for i in 0:num_links-1] for src in src_dirs]
    dst_ports = [["$(dst)_in[$i]" for i in 0:num_links-1] for dst in dst_dirs]

    offset_rules = []
    for (o,s,d) in zip(offsets, src_ports, dst_ports)
        rules = [(o,i,j) for (i,j) in zip(s,d)]
        append!(offset_rules, rules)
    end
    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"      => 1.0,
        "capacity"  => 1,
        "network"   => ["circuit_switched"]
    )

    connection_rule(tl, offset_rules, src_rule, dst_rule, metadata = metadata)
end
