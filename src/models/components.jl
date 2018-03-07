#=
A collection of core components to be used in the Asap3, Asap4, and generic
architectures.
=#
splatify(a::Tuple) = (splatify(a[1])..., splatify(a[2:end])...)
splatify(a::Tuple{}) = ()
splatify(a) = (a,)

struct Splatter{I}
    iter::I 
end

Base.start(s::Splatter) = start(s.iter)
function Base.next(s::Splatter, state) 
    (ns, nextstate) = next(s.iter, state)
    return (splatify(ns), nextstate)
end
Base.done(s::Splatter, state) = done(s.iter, state)


# annotate metadata

function make_port_metadata(direction, class, num_links)

    x_spacing = 0.4/num_links
    y_spacing = 0.4/num_links

    if direction in ("east", "west")
        if class == "input" 
            if direction == "east"
                x_offset = 1.0
                y_offset = 0.05
            else
                x_offset = 0.0
                y_offset = 0.55
            end
        else
            if direction == "east"
                x_offset = 1.0
                y_offset = 0.55
            else
                x_offset = 0.0
                y_offset = 0.05
            end
        end
        return [Dict("x" => x_offset, "y" => y_offset + i * y_spacing) 
                    for i in 0:num_links-1]
    elseif direction in ("north", "south")
        if class == "input" 
            if direction == "north"
                x_offset = 0.05
                y_offset = 0.0
            else
                x_offset = 0.55
                y_offset = 1.0
            end
        else
            if direction == "north"
                x_offset = 0.55
                y_offset = 0.0
            else
                x_offset = 0.05
                y_offset = 1.0
            end
        end
        return [Dict("x" => x_offset + i * x_spacing, "y" => y_offset) 
                    for i in 0:num_links-1]
    else
        return [make_port_metadata() for _ in 1:num_links]
    end
end

make_port_metadata() = Dict("x" => 0.5, "y" => 0.5)
make_port_metadata(num_links) = [make_port_metadata() for _ in 1:num_links]

##################
# COMPLEX BLOCKS #
##################
function build_processor_tile(num_links, 
                              name = "processor_tile", 
                              include_memory = false;
                              directions = ("east", "north", "south", "west"),
                             )
    # Working towards parameterizing this. For now, just leave this at two
    # because the "processor" components aren't parameterized for the number
    # of ports. This should be easy to fix though.
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
    # Instantiate the processor primitive
    add_child(comp, build_processor(num_links, include_memory), "processor")

    # Instantiate the directional routing muxes
    routing_mux = build_mux(length(directions),1)
    for dir in directions
        name = "$(dir)_mux"
        add_child(comp, routing_mux, name, num_links)
    end
    # Instantiate the muxes routing data to the fifos
    num_fifo_entries = length(directions) * num_links + 1
    add_child(comp, build_mux(num_fifo_entries,1), "fifo_mux", num_fifos)
    # Add memory ports - only memory processor tiles will have the necessary
    # "memory_processor" attribute in the core to allow memory application
    # to be mapped to them.
    if include_memory
        metadata = make_port_metadata()
        add_port(comp, "memory_in", "input", metadata = metadata)
        add_port(comp, "memory_out", "output", metadata = metadata)
        add_link(comp, "processor.memory_out", "memory_out")
        add_link(comp, "memory_in", "processor.memory_in")
    end

    # Interconnect - Don't attach metadata and let the routing routine fill in
    # defaults to intra-tile routing.

    # Connect outputs of muxes to the tile outputs
    for dir in directions, i = 0:num_links-1
        mux_port = "$(dir)_mux[$i].out[0]"
        tile_port = "$(dir)_out[$i]"
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
            add_link(comp, source_port, sink_ports)
        end
    end
    check(comp)
    return comp
end

function build_memory_processor_tile(num_links)
    # Get a normal processor and add the memory ports to it.
    tile = build_processor_tile(num_links,
                                "memory_processor", 
                                true, 
                               )
    # Need to add the memory processor attribute the processor.
    push!(tile.children["processor"].metadata["attributes"], "memory_processor")
    check(tile)
    return tile
end

# PRIMITIVE BLOCKS
##############################
#        PROCESSOR
##############################
"""
    build_processor(num_links)

Build a simple processor.
"""
function build_processor(num_links,include_memory = false)
    # Build the metadata dictionary for the processor component
    metadata = Dict{String,Any}()
    metadata["attributes"] = ["processor"]
    if include_memory
        name = "memory_processor"
    else
        name = "standard_processor"
    end
    component = Component(name, primitive = "", metadata = metadata)
    # Add the input fifos
    add_port(component, "fifo", "input", 2)
    # Add the output ports
    for str in ("north", "east", "south", "west")
        add_port(component, str, "output", num_links)
    end
    # Add the dynamic circuit switched network
    add_port(component, "dynamic", "output")
    # Add memory ports. Will only be connected in the memory processor tile.
    if include_memory
        add_port(component, "memory_in", "input")
        add_port(component, "memory_out", "output")
    end
    # Return the created type
    return component
end

function build_hex_processor(num_links, include_memory = false)
    num_fifos = 2 
    metadata = Dict{String,Any}(
        "attributes" => ["processor"]
    )
    name = include_memory ? "memory_processor" : "standard_processor"
    # Build the skeleton component.
    component = Component(name, primitive = "", metadata = metadata)
    # input fifos
    add_port(component, "fifo", "input", 2)
    # Add output ports. Label them by their degrees counter-clockwise from 
    # horizontal.
    for port in string.(30:60:330)
        add_port(component, port, "output", num_links)
    end
    if include_memory
        add_port(component, "memory_in", "input")
        add_port(component, "memory_out", "output")
    end
    return component
end

##############################
#      1 PORT MEMORY
##############################
function build_memory_1port()
    # Build the metadata dictionary for the processor component
    metadata = Dict{String,Any}()
    metadata["attributes"] = ["memory_1port"]
    component = Component("memory_1port", primitive = "", metadata = metadata)
    # Add the input and output ports
    port_metadata = make_port_metadata()
    add_port(component, "in[0]", "input", metadata = port_metadata)
    add_port(component, "out[0]", "output", metadata = port_metadata)
    # Return the created type
    return component
end

##############################
#      2 PORT MEMORY         #
##############################
function build_memory_2port()
    # Build the metadata dictionary for the processor component
    metadata = Dict{String,Any}()
    metadata["attributes"] = ["memory_1port", "memory_2port"]
    component = Component("memory_2port", primitive = "", metadata = metadata)
    # Add the input and output ports
    port_metadata = make_port_metadata()
    add_port(component, "in", "input", 2, metadata = port_metadata)
    add_port(component, "out", "output", 2, metadata = port_metadata)
    # Return the created type
    return component
end

##############################
#       INPUT HANDLER        #
##############################
function build_input_handler(num_links)
    # Build the metadata dictionary for the input handler
    metadata = Dict{String,Any}()
    metadata["attributes"] = ["input_handler"]
    component = Component("input_handler", primitive = "", metadata = metadata)
    # Add the input and output ports
    add_port(component, "out", "output", num_links, metadata = make_port_metadata())
    # Return the created type
    return component
end

##############################
#       OUTPUT HANDLER       #
##############################
function build_output_handler(num_links)
    # Build the metadata dictionary for the input handler
    metadata = Dict{String,Any}()
    metadata["attributes"] = ["output_handler"]
    component = Component("output_handler", primitive = "", metadata = metadata)
    # Add the input and output ports
    port_metadata = make_port_metadata()
    add_port(component, "in", "input", num_links, metadata = port_metadata)
    # Return the created type
    return component
end
