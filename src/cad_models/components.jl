# Styles - mainly for switching between hexagonal and rectangular layouts.
abstract type Style end

# Style API
links(x::Style) = x.links
iolinks(x::Style) = x.io_links

# For unifying filters for creating source/sink rules.
filter_proc(x) = search_metadata!(x, typekey(), MTypes.proc, in)
filter_io(x) = search_metadata!(
    x, 
    typekey(), 
    [MTypes.proc, MTypes.input, MTypes.output], 
    oneofin
)

filter_memproc(x) = search_metadata!(x, typekey(), MTypes.memoryproc, in)
filter_memory(n) = x -> search_metadata!(x, typekey(), MTypes.memory(n), in)

################################################################################
# Rectangular
################################################################################
struct Rectangular <: Style 
    # Number of interprocessor links
    links :: Int
    io_links :: Int
end

directions(::Rectangular) = ("east", "north", "south", "west")
function procrules(style::Rectangular) 

    offset_skeleton = (
        ( (-1, 0), "north", "south"),
        ( ( 1, 0), "south", "north"),
        ( ( 0, 1), "east",  "west"),
        ( ( 0,-1), "west",  "east"),
    )

    offsets = squash([
        Offset(a, "$(b)_out[$i]", "$(c)_in[$i]") 
        for (a,b,c) in offset_skeleton, i in 0:style.links
    ])

    return ConnectionRule(
        offsets,
        source_filter = filter_proc,
        dest_filter = filter_proc,
    )
end


function iorules(style::Rectangular)

    offset_skeletons = (
        ( ( 0, 1), "east", "west"),
        ( ( 0,-1), "west", "east"),
    )

    input_rules = squash([
        Offset(a, "out[$i]", "$(c)_in[$i]")
        for (a,b,c) in offset_skeletons, i in 0:style.io_links-1
    ])

    output_rules = squash([
        Offset(a, "$(b)_out[$i]", "in[$i]")
        for (a,b,c) in offset_skeletons, i in 0:style.io_links-1
    ])

    return ConnectionRule(
        vcat(input_rules, output_rules),
        source_filter = filter_io,
        dest_filter = filter_io,
    )
end

function memory_request_rules(::Rectangular)

    # 2 port memories
    proc_to_mem2 = ConnectionRule([
            Offset((1,0), "memory_out", "in[0]"),
            Offset((1,-1), "memory_out", "in[1]")
        ],
        source_filter = filter_memproc,
        dest_filter = filter_memory(2),
    )

    # 1 port memories
    proc_to_mem1 = ConnectionRule(
        [Offset((1,0), "memory_out", "in[0]")],
        source_filter = filter_memproc,
        dest_filter = filter_memory(1),

    )
    return (proc_to_mem1, proc_to_mem2)
end

function memory_return_rules(::Rectangular)

    # 2 port memories
    mem2_to_proc = ConnectionRule([
            Offset((-1,0), "out[0]", "memory_in"),
            Offset((-1,1), "out[1]", "memory_in"),
        ],
        source_filter = filter_memory(2),
        dest_filter = filter_memproc,
    )

    # 1 port memories
    mem1_to_proc = ConnectionRule(
        [Offset((-1,0), "out[0]", "memory_in")],
        source_filter = filter_memory(1),
        dest_filter = filter_memproc,
    )

    return (mem2_to_proc, mem1_to_proc)
end


################################################################################
# Hexagonal
################################################################################

struct Hexagonal <: Style 
    links::Int
    io_links::Int
end
# Encode hexagonal directions using angles.
directions(::Hexagonal) = ("30", "90", "150", "210", "270", "330")
function procrules(style::Hexagonal)

    # Rule to apply if the column address is even.
    even_skeleton = (
        ((0, 1),  "30_out",  "210_in"),
        ((-1, 0), "90_out",  "270_in"),
        ((0, -1), "150_out", "330_in"),
        ((1, -1), "210_out",  "30_in"),
        ((1, 0),  "270_out",  "90_in"),
        ((1, 1),  "330_out", "150_in"),
    )
    even_offsets = squash([
        Offset(a, "$b[$i]", "$c[$i]") 
        for (a,b,c) in even_skeleton, i in 0:style.links-1
    ])
    even_rule = ConnectionRule(
        even_offsets, 
        source_filter = filter_proc,
        dest_filter = filter_proc,
        address_filter = x -> iseven(x[2])
    )

    # Rule to apply if the column address is odd.
    odd_skeleton = (
        ((-1, 1),  "30_out",  "210_in"),
        ((-1, 0),  "90_out",  "270_in"),
        ((-1, -1), "150_out", "330_in"),
        (( 0, -1), "210_out",  "30_in"),
        (( 1, 0),  "270_out",  "90_in"),
        (( 0, 1),  "330_out", "150_in"),
    )
    odd_offsets = squash([
        Offset(a, "$b[$i]", "$c[$i]") 
        for (a,b,c) in odd_skeleton, i in 0:style.links-1
    ])
    odd_rule = ConnectionRule(
        odd_offsets, 
        source_filter = filter_proc,
        dest_filter = filter_proc,
        address_filter = x -> isodd(x[2])
    )

    return (even_rule, odd_rule)
end

function iorules(style::Hexagonal)

    # Connection rule for even columns
    even_skeleton = (
        ( ( 0, 1), "30_out", "210_in"),
        ( ( 1, 1), "330_out", "150_in"),
        ( ( 0,-1), "150_out", "210_in"),
        ( ( 1,-1), "210_out", "30_in"),
    )

    # Processor -> Output_Handler
    even_offsets_1 = squash([
        Offset(a, "$b[$i]", "in[$i]") 
        for (a,b,c) in even_skeleton, i in 0:style.io_links-1
    ])
    # Input Handler -> Processor
    even_offsets_2 = squash([
        Offset(a, "out[$i]", "$c[$i]") 
        for (a,b,c) in even_skeleton, i in 0:style.io_links-1
    ])
    even_rule = ConnectionRule(
        vcat(even_offsets_1, even_offsets_2),
        source_filter = filter_io,
        dest_filter = filter_io,
        address_filter = x -> iseven(x[2])
    )

    # Connection rule for odd columns
    odd_skeleton = (
        ( (-1, 1), "30_out", "210_in"),
        ( ( 0, 1), "330_out", "150_in"),
        ( (-1,-1), "150_out", "210_in"),
        ( ( 0,-1), "210_out", "30_in"),
    )
    # Processor -> Output_Handler
    odd_offsets_1 = squash([
        Offset(a, "$b[$i]", "in[$i]") 
        for (a,b,c) in odd_skeleton, i in 0:style.io_links-1
    ])
    # Input Handler -> Processor
    odd_offsets_2 = squash([
        Offset(a, "out[$i]", "$c[$i]") 
        for (a,b,c) in odd_skeleton, i in 0:style.io_links-1
    ])
    odd_rule = ConnectionRule(
        vcat(odd_offsets_1, odd_offsets_2),
        source_filter = filter_io,
        dest_filter = filter_io,
        address_filter = x -> isodd(x[2])
    )

    return (even_rule, odd_rule)
end

function memory_return_rules(::Hexagonal)
    return ConnectionRule(
        [
            Offset((-1, 0), "out[0]", "memory_in"), 
            Offset((-1, 1), "out[1]", "memory_in")
        ],
        source_filter = filter_memory(2),
        dest_filter = filter_memproc
    )
end

function memory_request_rules(::Hexagonal)
    return ConnectionRule(
        [
            Offset(( 1, 0), "memory_out", "in[0]"), 
            Offset(( 1,-1), "memory_out", "in[1]")
        ],
        source_filter = filter_memproc,
        dest_filter = filter_memory(2)
    )
end

################################################################################
# COMPLEX BLOCKS
################################################################################

"""
    build_processor_tile(num_links, kwargs)

Build a processor tile.
"""
function build_processor_tile(
        style; 
        include_memory = false,
        name = include_memory ? "memory_processor_tile" : "processor_tile", 
    )

    num_fifos = 2
    num_links = links(style)
    # No need to assign metadata to this component.
    component = Component(name)

    # General metadata for ciruit link routing components.
    cl_metadata = routing_metadata("circuit_link")

    # Add the circuit switched ports
    for dir in directions(style)
        for (suffix,class)  in zip(("_in", "_out"), (Input, Output))
            meta = top_level_port_metadata(dir, class, "circuit_link", num_links)
            port_name = join((dir, suffix))
            add_port(component, port_name, class, num_links, metadata = meta)
        end
    end

    # Instantiate the processor primitive - do special assignment for ASAP mapping.
    proc_component = build_processor(style, include_memory = include_memory)

    add_child(component, proc_component, "processor")

    # Instantiate the directional routing muxes
    routing_mux = build_mux(length(directions(style)),1)
    for dir in directions(style)
        name = "$(dir)_mux"
        add_child(component, routing_mux, name, num_links)
    end

    # Instantiate the muxes routing data to the fifos
    # Allocate a mux input for each input on the circuit net.
    num_fifo_inputs = length(directions(style)) * num_links
    fifo_mux = build_mux(num_fifo_inputs, 1, metadata = cl_metadata)
    add_child(component, fifo_mux, "fifo_mux", num_fifos)

    # Add memory ports and links if necessary.
    if include_memory
        return_link  = routing_metadata("memory_response_link")
        request_link = routing_metadata("memory_request_link")
        add_port(component, "memory_in", Input, metadata = return_link)
        add_port(component, "memory_out", Output, metadata = request_link)
        add_link(component, "processor.memory_out", "memory_out", metadata = request_link)
        add_link(component, "memory_in", "processor.memory_in", metadata = return_link)
    end

    # Connect outputs of muxes to the tile outputs
    for dir in directions(style), i = 0:num_links-1
        # Each mux has only one output.
        mux_port    = "$(dir)_mux[$i].out[0]"
        tile_port   = "$(dir)_out[$i]"
        add_link(component, mux_port, tile_port, metadata = cl_metadata)
    end

    # Circuit switch output links
    for dir in directions(style), i = 0:num_links-1
        # Make the name for the processor.
        proc_port = "processor.$dir[$i]"
        mux_port = "$(dir)_mux[$i].in[0]"
        add_link(component, proc_port, mux_port, metadata = cl_metadata)
    end

    # Connect input fifos.
    for i = 0:num_fifos-1
        fifo_port = "fifo_mux[$i].out[0]"
        proc_port = "processor.fifo[$i]"
        add_link(component, fifo_port, proc_port, metadata = cl_metadata)
    end

    # Connect input ports to inputs of muxes

    # Tracker Structure storing what ports on a mux have been used.
    # Initialize to 1 because the processor is connect to port 0 on all
    # multiplexors.
    index_tracker = Dict((d,i) => 1 for d in directions(style), i in 0:num_links)
    # Add entries for the fifo
    for i in 0:num_fifos
        index_tracker[("fifo",i)] = 0
    end
    for dir in directions(style)
        for i in 0:num_links-1
            # Create a source port for the tile input.
            source_port = "$(dir)_in[$i]" 
            # Begin adding sink ports.
            # Need one for each mux on this layer and num_fifos for each of
            # the input fifos.
            sink_ports = String[]
            # Go through all fifos that directions that are not the current
            # directions.
            for d in Iterators.filter(!isequal(dir), directions(style))
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
            add_link(component, source_port, sink_ports, metadata = cl_metadata)
        end
    end
    check(component)
    return component
end

################################################################################
#                           processor
################################################################################
function build_processor(
        style;
        include_memory = false, 
        num_fifos = 2,
    )
    num_links = links(style)
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
    port_metadata = proc_output_metadata(length(directions(style)), num_links)
    # NOTE: Iterators.product iterates over the first element the quickest.
    for (port_index,(str,i)) in enumerate(Iterators.product(directions(style), 1:num_links))
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
build_input_handler(style::Style) = build_input_handler(iolinks(style))
function build_input_handler(num_links::Integer)
    component = Component("input_handler", metadata = input_handler_metadata())
    add_port(
        component, 
        "out", 
        Output, 
        num_links, 
        metadata = input_handler_port_metadata(num_links)
    )

    return component
end

##############################
#       OUTPUT HANDLER       #
##############################
build_output_handler(style::Style) = build_output_handler(iolinks(style))
function build_output_handler(num_links::Integer)
    component = Component("output_handler", metadata = output_handler_metadata())
    add_port(
        component, 
        "in", 
        Input, 
        num_links, 
        metadata = output_handler_port_metadata(num_links)
    )

    return component
end

################################################################################
# Functions for connecting processors, IO, and memories together
################################################################################
squash(x) = reshape(x, :)
function connect_processors(toplevel, style)

    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "circuit_link"
    )

    for rule in procrules(style)
        connection_rule(toplevel, rule, metadata = metadata)
    end
    return nothing
end

function connect_io(toplevel, style)

    # Build metadata dictionary for capacity and cost
    metadata = Dict(
        "cost"          => 1.0,
        "capacity"      => 1,
        "link_class"    => "link_class"
    )

    for rule in iorules(style)
        connection_rule(toplevel, rule, metadata = metadata)
    end
    return nothing
end

function connect_memories(toplevel, style)
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

    for rule in memory_request_rules(style)
        connection_rule(toplevel, rule, metadata = request_metadata)
    end

    for rule in memory_return_rules(style)
        connection_rule(toplevel, rule, metadata = return_metadata)
    end

    return nothing
end
