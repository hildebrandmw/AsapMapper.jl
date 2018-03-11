################################################################################
# COMPLEX BLOCKS
################################################################################
function build_processor_tile(num_links; 
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
        for (suffix,class)  in zip(("_in", "_out"), ("input", "output"))
            port_name = join((dir, suffix))
            add_port(comp, port_name, class, num_links, metadata = cl_metadata)
        end
    end
    # Instantiate the processor primitive
    proc_component = build_processor(num_links, include_memory = include_memory)
    add_child(comp, proc_component, "processor")

    # Instantiate the directional routing muxes
    routing_mux = build_mux(length(directions),1)
    for dir in directions
        name = "$(dir)_mux"
        add_child(comp, routing_mux, name, num_links, metadata = cl_metadata)
    end
    # Instantiate the muxes routing data to the fifos
    num_fifo_entries = length(directions) * num_links + 1
    fifo_mux = build_mux(num_fifo_entries, 1, metadata = cl_metadata)
    add_child(comp, fifo_mux, "fifo_mux", num_fifos)
    # Add memory ports - only memory processor tiles will have the necessary
    # "memory_processor" attribute in the core to allow memory application
    # to be mapped to them.
    if include_memory
        add_port(comp, "memory_in", "input", metadata = routing_metadata("memory_return_link"))
        add_port(comp, "memory_out", "output", metadata = routing_metadata("memory_request_link"))
        add_link(comp, "processor.memory_out", "memory_out", metadata = routing_metadata("memory_return_link"))
        add_link(comp, "memory_in", "processor.memory_in", metadata = routing_metadata("memory_request_link"))
    end

    # Interconnect - Don't attach metadata and let the routing routine fill in
    # defaults to intra-tile routing.

    # Connect outputs of muxes to the tile outputs
    for dir in directions, i = 0:num_links-1
        mux_port = "$(dir)_mux[$i].out[0]"
        tile_port = "$(dir)_out[$i]"
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

# PRIMITIVE BLOCKS
##############################
#        PROCESSOR
##############################

"""
    build_processor(num_links)

Build a simple processor.
"""
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
    add_port(component, "fifo", "input", num_fifos, metadata = proc_fifo_metadata(num_fifos))
    # ports. Neet to play some indexing games for the metadata vector to get
    # indices to line up with the Asap4 manual.
    port_metadata = proc_output_metadata(num_links * length(directions))
    for (i,str) in enumerate(directions)
        index = (i-1)*length(directions) + 1
        add_port(component, str, "output", num_links, metadata = port_metadata[index])
    end
    # Add memory ports. Will only be connected in the memory processor tile.
    if include_memory
        add_port(component, "memory_in", "input", metadata = proc_memory_return_metadata())
        add_port(component, "memory_out", "output", metadata = proc_memory_request_metadata())
    end
    # Return the created type
    return component
end

function build_memory(nports = 2)
    component = Component("memory_$(nports)port", metadata = mem_nport_metadata(nports))

    # Instantiate ports
    add_port(component, "in", "input", nports, metadata = mem_memory_request_metadata(nports))
    add_port(component, "out", "output", nports, metadata = mem_memory_return_metadata(nports))

    return component
end


##############################
#       INPUT HANDLER        #
##############################
function build_input_handler(num_links)
    component = Component("input_handler", metadata = input_handler_metadata())
    add_port(component, "out", "output", num_links, metadata = input_handler_port_metadata(num_links))

    return component
end

##############################
#       OUTPUT HANDLER       #
##############################
function build_output_handler(num_links)
    component = Component("output_handler", metadata = output_handler_metadata())
    add_port(component, "in", "input", num_links, metadata = output_handler_port_metadata(num_links))

    return component
end

################################################################################
# Deprecations
################################################################################
@deprecate build_memory_1port() build_memory(1)
@deprecate build_memory_2port() build_memory(2)
@deprecate build_memory_processor_tile(num_links) build_processor_tile(num_links, include_memory = true)
