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
