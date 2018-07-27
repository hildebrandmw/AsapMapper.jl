################################################################################
# COMPLEX BLOCKS
################################################################################
"""
    build_processor_tile(num_links, kwargs)

Build a processor tile.
"""
function build_processor_tile(
              num_links; 
              include_memory = false,
              name = include_memory ? "memory_processor_tile" : "processor_tile", 
              directions = ("east", "north", "west", "south"),
             )

    num_fifos = 2
    # No need to assign metadata to this component.
    comp = Component(name)

    # General metadata for ciruit link routing components.
    cl_metadata = routing_metadata("circuit_link")

    # Add the circuit switched ports
    for dir in directions
        for (suffix,class)  in zip(("_in", "_out"), (Input, Output))
            meta = top_level_port_metadata(dir, class, "circuit_link", num_links)
            port_name = join((dir, suffix))
            add_port(comp, port_name, class, num_links, metadata = meta)
        end
    end

    # Instantiate the processor primitive - do special assignment for ASAP mapping.
    proc_component = build_processor(num_links, include_memory = include_memory)

    add_child(comp, proc_component, "processor")

    # Instantiate the directional routing muxes
    routing_mux = build_mux(length(directions),1)
    for dir in directions
        name = "$(dir)_mux"
        add_child(comp, routing_mux, name, num_links)
    end

    # Instantiate the muxes routing data to the fifos
    # Allocate a mux input for each input on the circuit net.
    num_fifo_inputs = length(directions) * num_links
    fifo_mux = build_mux(num_fifo_inputs, 1, metadata = cl_metadata)
    add_child(comp, fifo_mux, "fifo_mux", num_fifos)

    # Add memory ports and links if necessary.
    if include_memory
        return_link  = routing_metadata("memory_response_link")
        request_link = routing_metadata("memory_request_link")
        add_port(comp, "memory_in", Input, metadata = return_link)
        add_port(comp, "memory_out", Output, metadata = request_link)
        add_link(comp, "processor.memory_out", "memory_out", metadata = request_link)
        add_link(comp, "memory_in", "processor.memory_in", metadata = return_link)
    end

    # Connect outputs of muxes to the tile outputs
    for dir in directions, i = 0:num_links-1
        # Each mux has only one output.
        mux_port    = "$(dir)_mux[$i].out[0]"
        tile_port   = "$(dir)_out[$i]"
        add_link(comp, mux_port, tile_port, metadata = cl_metadata)
    end

    # Circuit switch output links
    for dir in directions, i = 0:num_links-1
        # Make the name for the processor.
        proc_port = "processor.$dir[$i]"
        mux_port = "$(dir)_mux[$i].in[0]"
        add_link(comp, proc_port, mux_port, metadata = cl_metadata)
    end

    # Connect input fifos.
    for i = 0:num_fifos-1
        fifo_port = "fifo_mux[$i].out[0]"
        proc_port = "processor.fifo[$i]"
        add_link(comp, fifo_port, proc_port, metadata = cl_metadata)
    end

    # Connect input ports to inputs of muxes

    # Tracker Structure storing what ports on a mux have been used.
    # Initialize to 1 because the processor is connect to port 0 on all
    # multiplexors.
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
            add_link(comp, source_port, sink_ports, metadata = cl_metadata)
        end
    end
    check(comp)
    return comp
end

################################################################################
#                           processor
################################################################################
function build_processor(num_links;
                         include_memory = false, 
                         num_fifos = 2,
                         directions = ("east", "north", "west", "south")
                        )
    # Build the metadata dictionary for the processor component
    metadata = Dict{String,Any}()

    if include_memory
        comp_metadata = mem_proc_metadata()
        name = "memory_processor"
    else
        comp_metadata = proc_metadata()
        name = "standard_processor"
    end

    component = Component(name, metadata = comp_metadata)
    # fifos
    add_port(component, "fifo", Input, num_fifos, metadata = proc_fifo_metadata(num_fifos))
    # ports. Neet to play some indexing games for the metadata vector to get
    # indices to line up with the Asap4 manual.
    port_metadata = proc_output_metadata(length(directions), num_links)
    # NOTE: Iterators.product iterates over the first element the quickest.
    for (port_index,(str,i)) in enumerate(Iterators.product(directions, 1:num_links))
        add_port(component, "$str[$(i-1)]", Output, metadata = port_metadata[port_index])
    end
    # Add memory ports. Will only be connected in the memory processor tile.
    if include_memory
        add_port(component, "memory_in", Input, metadata = proc_memory_return_metadata())
        add_port(component, "memory_out", Output, metadata = proc_memory_request_metadata())
    end
    # Return the created type
    return component
end

function build_memory(nports = 2)
    component = Component("memory_$(nports)port", metadata = mem_nport_metadata(nports))

    # Instantiate ports
    add_port(component, "in", Input, nports, metadata = mem_memory_request_metadata(nports))
    add_port(component, "out", Output, nports, metadata = mem_memory_return_metadata(nports))

    return component
end


##############################
#       INPUT HANDLER        #
##############################
function build_input_handler(num_links)
    component = Component("input_handler", metadata = input_handler_metadata())
    add_port(component, "out", Output, num_links, metadata = input_handler_port_metadata(num_links))

    return component
end

##############################
#       OUTPUT HANDLER       #
##############################
function build_output_handler(num_links)
    component = Component("output_handler", metadata = output_handler_metadata())
    add_port(component, "in", Input, num_links, metadata = output_handler_port_metadata(num_links))

    return component
end

################################################################################
# Deprecations
################################################################################
@deprecate build_memory_1port() build_memory(1)
@deprecate build_memory_2port() build_memory(2)
@deprecate build_memory_processor_tile(num_links) build_processor_tile(num_links, include_memory = true)

################################################################################
# Functions for connecting processors, IO, and memories together
################################################################################
squash(x) = reshape(x, :)
function connect_processors(tl, num_links)
    fn = x -> search_metadata!(x, typekey(), MTypes.proc, in)

    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "circuit_link"
    )

    offset_skeleton = (
        ( (-1, 0), "north", "south"),
        ( ( 1, 0), "south", "north"),
        ( ( 0, 1), "east",  "west"),
        ( ( 0,-1), "west",  "east"),
    )

    offsets = squash([
        Offset(a, "$(b)_out[$i]", "$(c)_in[$i]") 
        for (a,b,c) in offset_skeleton, i in 0:num_links
    ])

    rule = ConnectionRule(
        offsets,
        source_filter = fn,
        dest_filter = fn,
    )

    connection_rule(tl, offsets, metadata = metadata)

end

function connect_io(tl, num_links)

    vals = [MTypes.proc, MTypes.input, MTypes.output]
    fn = x -> search_metadata!(x, typekey(), vals, oneofin)

    offset_skeletons = (
        ( ( 0, 1), "east", "west"),
        ( ( 0,-1), "west", "east"),
    )

    input_rules = squash([
        Offset(a, "out[$i]", "$(c)_in[$i]")
        for (a,b,c) in offset_skeletons, i in 0:num_links-1
    ])

    output_rules = squash([
        Offset(a, "$(b)_out[$i]", "in[$i]")
        for (a,b,c) in offset_skeletons, i in 0:num_links-1
    ])

    rule = ConnectionRule(
        vcat(input_rules, output_rules),
        source_filter = fn,
        dest_filter = fn,
    )

    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "link_class"
    )

    connection_rule(tl, rule, metadata = metadata)
    return nothing
end

function connect_memories(tl)
    # Create metadata dictionary for the memory links.
    request_metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "memory_request_link",
   )

    return_metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "memory_response_link",
   )
    ########################### 
    # Connect 2 port memories #
    ########################### 

    proc_rule = x -> search_metadata!(x, typekey(), MTypes.memoryproc, in)
    mem2_rule  = x -> search_metadata!(x, typekey(), MTypes.memory(2), in)
    mem1_rule = x -> search_metadata!(x, typekey(), MTypes.memory(1), in)


    mem2_to_proc = ConnectionRule([
            Offset((-1,0), "out[0]", "memory_in"),
            Offset((-1,1), "out[1]", "memory_in"),
        ],
        source_filter = mem2_rule,
        dest_filter = proc_rule,
    )
    connection_rule(tl, mem2_to_proc, metadata = return_metadata)

    proc_to_mem2 = ConnectionRule([
            Offset((1,0), "memory_out", "in[0]"),
            Offset((1,-1), "memory_out", "in[1]")
        ],
        source_filter = proc_rule,
        dest_filter = mem2_rule,
    )
    connection_rule(tl, proc_to_mem2, metadata = request_metadata)

    ########################### 
    # Connect 1 port memories #
    ########################### 

    mem1_to_proc = ConnectionRule(
        [Offset((-1,0), "out[0]", "memory_in")],
        source_filter = mem1_rule,
        dest_filter = proc_rule,
    )
    connection_rule(tl, mem1_to_proc, metadata = return_metadata)

    proc_to_mem1 = ConnectionRule(
        [Offset((1,0), "memory_out", "in[0]")],
        source_filter = proc_rule,
        dest_filter = mem1_rule,

    )
    connection_rule(tl, proc_to_mem1, metadata = return_metadata)

    return nothing
end
