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

cartesian(s::Style, x::Address) = cartesian(s, Tuple(x))
cartesian(s::Style, x::Tuple) = cartesian(s, x...)

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

# Port annotations
function port_boundaries(::Rectangular, orientation) 
    coords = Dict(
        "east" => ((1,0), (1,1)),
        "south" => ((1,1), (0,1)),
        "west" => ((0,0), (0,1)),
        "north" => ((1,0), (0,0)),
    )

    return coords[orientation]
end

function initial_offset(::Rectangular, orientation, direction)
    # Select where to start between the start and stop coordinates depending
    # on the direction selected
    starts = Dict(
        ( "north", Output ) => 0.55,
        ( "east" , Output ) => 0.55,
        ( "south", Input ) => 0.55,
        ( "west" , Input ) => 0.55,

        ( "north", Input ) => 0.05,
        ( "east" , Input ) => 0.05,
        ( "south", Output ) => 0.05,
        ( "west" , Output ) => 0.05,
    )

    return starts[(orientation, direction)]
end

boxx(x, width) = [x, x + width, x + width, x, x]
boxy(y, height) = [y, y, y + height, y + height, y]

cartesian(::Rectangular, x, y) = (1.5*x, 1.5*y)
polygon(::Rectangular, x, y) = (boxx(x, 1), boxy(y, 1))

################################################################################
# Hexagonal
################################################################################

struct Hexagonal <: Style 
    links::Int
    io_links::Int
end

#=
          ____          ____
         /    \        /    \
        /      \      /      \
   ____/  (0,1) \____/ (0,3)  \
  /    \        /    \        /
 /      \      /      \      /
/ (0,0)  \____/ (0,2)  \____/
\        /    \        /    \
 \      /      \      /      \
  \____/ (1,1)  \____/ (1,3)  \
  /    \        /    \        /
 /      \      /      \      /
/ (1,0)  \____/ (1,2)  \____/
\        /    \        /
 \      /      \      /
  \____/        \____/
=#

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

# Port orientations
#directions(::Hexagonal) = ("30", "90", "150", "210", "270", "330")
sq() = sqrt(3) / 2
function port_boundaries(::Hexagonal, orientation) 
    coords = Dict(
        "30"  => ((   1,      0), ( 1/2, -sq())),
        "90"  => (( 1/2,  -sq()), (-1/2, -sq())),
        "150" => ((-1/2,  -sq()), (  -1,     0)),

        "210" => ((-1/2,   sq()), (   -1,    0)),
        "270" => (( 1/2,   sq()), (-1/2,  sq())),
        "330" => ((   1,      0), ( 1/2,  sq())),
    )

    return coords[orientation]
end





function initial_offset(::Hexagonal, orientation, direction)
    # Select where to start between the start and stop coordinates depending
    # on the direction selected
    starts = Dict(
        ( "30",  Output ) => 0.55,
        ( "90" , Output ) => 0.55,
        ( "150", Output ) => 0.55,
        ( "210",  Input ) => 0.55,
        ( "270" , Input ) => 0.55,
        ( "330" , Input ) => 0.55,

        ( "30",  Input ) => 0.05,
        ( "90" , Input ) => 0.05,
        ( "150", Input ) => 0.05,
        ( "210",  Output ) => 0.05,
        ( "270" , Output ) => 0.05,
        ( "330" , Output ) => 0.05,
    )

    return starts[(orientation, direction)]
end

function cartesian(::Hexagonal, x, y) 
    # Determine if this is an odd or even column
    x_out = 2.5 * x
    y_out = 2.5 * y

    if isodd(y) 
        x_out = x_out - 1.25
    end

    return (x_out, y_out)
end


hexx(x) = [x+1, x + 1/2, x - 1/2, x - 1, x - 1/2, x + 1/2, x+1]
hexy(y) = [y, y + sq(), y + sq(), y, y - sq(), y - sq(), y]

polygon(::Hexagonal, x, y) = (hexx(x), hexy(y))
