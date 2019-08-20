################################################################################
# Rectangular
################################################################################
abstract type AbstractRectangular <: Style end

#####
##### General rectangular methods
#####
boxx(x, width) = [x, x + width, x + width, x, x]
boxy(y, height) = [y, y, y + height, y + height, y]

cartesian(::AbstractRectangular, x, y) = (1.5*x, 1.5*y)
polygon(::AbstractRectangular, x, y) = (boxx(x, 1), boxy(y, 1))

function iorules(style::AbstractRectangular)

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

function memory_request_rules(::AbstractRectangular)

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

function memory_return_rules(::AbstractRectangular)

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

#####
##### Standard Rectangular
#####
struct Rectangular <: AbstractRectangular 
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

#####
##### 8-4 rectangular
#####

# Neighbors are still in the four cardinal directions, but now there are long distance
# links also that hop over neighbors
struct Rectangular84 <: AbstractRectangular 
    # Number of interprocessor links
    links :: Int
    io_links :: Int
end

# Have two types of links in each direction - one for 1 hop links and another for 2 hop links
directions(::Rectangular84) = [
    "east", 
    "east_far",
    "north", 
    "north_far", 
    "south", 
    "south_far", 
    "west",
    "west_far",
]
function procrules(style::Rectangular84) 

    offset_skeleton = (
        ( (-1, 0), "north", "south"),
        ( ( 1, 0), "south", "north"),
        ( ( 0, 1), "east",  "west"),
        ( ( 0,-1), "west",  "east"),
        ( (-2, 0), "north_far", "south_far"),
        ( ( 2, 0), "south_far", "north_far"),
        ( ( 0, 2), "east_far",  "west_far"),
        ( ( 0,-2), "west_far",  "east_far"),
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

# Port annotations
function port_boundaries(::Rectangular84, orientation) 
    # Split the near are far links halfway across the border
    coords = Dict(
        "east"      =>  ((1,0),    (1,0.5)),
        "east_far"  =>  ((1, 0.5), (1, 1)),
        "south"     =>  ((1,1),    (0.5, 1)),
        "south_far" =>  ((0.5, 1), (0, 1)),
        "west"      =>  ((0,0),    (0, 0.5)),
        "west_far"  =>  ((0,0.5),  (0,1)),
        "north"     =>  ((1,0), (0.5,0)),
        "north_far" =>  ((0.5,0), (0,0)),
    )

    return coords[orientation]
end

function initial_offset(::Rectangular84, orientation, direction)
    # Select where to start between the start and stop coordinates depending
    # on the direction selected
    starts = Dict(
        ( "north", Output ) => 0.55,
        ( "east" , Output ) => 0.55,
        ( "north_far", Output ) => 0.55,
        ( "east_far" , Output ) => 0.55,
        ( "south", Input ) => 0.55,
        ( "west" , Input ) => 0.55,
        ( "south_far", Input ) => 0.55,
        ( "west_far" , Input ) => 0.55,

        ( "north", Input ) => 0.05,
        ( "east" , Input ) => 0.05,
        ( "north_far", Input ) => 0.05,
        ( "east_far" , Input ) => 0.05,
        ( "south", Output ) => 0.05,
        ( "west" , Output ) => 0.05,
        ( "south_far", Output ) => 0.05,
        ( "west_far" , Output ) => 0.05,
    )

    return starts[(orientation, direction)]
end

#####
##### 8-8 rectangular
#####

# 8 nearest neighbors
struct Rectangular88 <: AbstractRectangular 
    # Number of interprocessor links
    links :: Int
    io_links :: Int
end

# Have two types of links in each direction - one for 1 hop links and another for 2 hop links
directions(::Rectangular88) = [
    "east", 
    "north_east",
    "north", 
    "north_west", 
    "west",
    "south_west",
    "south", 
    "south_east", 
]
function procrules(style::Rectangular88) 

    offset_skeleton = (
        ( (-1, 0), "north", "south"),
        ( ( 1, 0), "south", "north"),
        ( ( 0, 1), "east",  "west"),
        ( ( 0,-1), "west",  "east"),
        ( (-1, 1), "north_east", "south_west"),
        ( (-1,-1), "north_west", "south_east"),
        ( ( 1, 1), "south_east",  "north_west"),
        ( ( 1,-1), "south_west",  "north_east"),
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

# Port annotations
function port_boundaries(::Rectangular88, orientation) 
    # Split the near are far links halfway across the border
    coords = Dict(
        "east"        =>  ((1,0),    (1,0.5)),
        "south_east"  =>  ((1, 0.5), (1, 1)),
        "south"       =>  ((1,1),    (0.5, 1)),
        "south_west"  =>  ((0.5, 1), (0, 1)),
        "north_west"  =>  ((0,0),    (0, 0.5)),
        "west"        =>  ((0,0.5),  (0,1)),
        "north_east"  =>  ((1,0),    (0.5,0)),
        "north"       =>  ((0.5,0),  (0,0)),
    )

    return coords[orientation]
end

function initial_offset(::Rectangular88, orientation, direction)
    # Select where to start between the start and stop coordinates depending
    # on the direction selected
    starts = Dict(
        ( "north", Output ) => 0.55,
        ( "east" , Output ) => 0.55,
        ( "north_east", Output ) => 0.55,
        ( "south_east" , Output ) => 0.55,
        ( "south", Input ) => 0.55,
        ( "west" , Input ) => 0.55,
        ( "south_west", Input ) => 0.55,
        ( "north_west" , Input ) => 0.55,

        ( "north", Input ) => 0.05,
        ( "east" , Input ) => 0.05,
        ( "north_east", Input ) => 0.05,
        ( "south_east" , Input ) => 0.05,
        ( "south", Output ) => 0.05,
        ( "west" , Output ) => 0.05,
        ( "south_west", Output ) => 0.05,
        ( "north_west" , Output ) => 0.05,
    )

    return starts[(orientation, direction)]
end
