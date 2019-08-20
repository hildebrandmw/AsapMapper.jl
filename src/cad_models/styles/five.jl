#####
##### Five nearest neighbor stuff
#####

#=

#########################
#       #       #       #
#       #       #       #
# (0,0) # (0,1) # (0,2) #
#       #       #       #
#       #       #       #
#############################
    #       #       #       #
    #       #       #       #
    # (1,0) # (1,1) # (1,2) #
    #       #       #       #
    #       #       #       #
    #########################
    #       #       #       #
    #       #       #       #
    # (2,0) # (2,1) # (2,2) #
    #       #       #       #
    #       #       #       #
#############################
#       #       #       #
#       #       #       #
# (3,0) # (3,1) # (3,2) #
#       #       #       #
#       #       #       #
#########################

=#

struct Rect5 <: AbstractRectangular
    links::Int
    io_links::Int
end

# Encode hexagonal directions using angles.
directions(::Rect5) = ("north_left", "north_right", "north", "east", "west", "south_left", "south_right", "south")
function procrules(style::Rect5)
    # Set things up by row
    mod0_skeleton = (
        ((1, 0), "north_right_out", "south_left_in"),
        ((1,-1), "north_left_out", "south_right_in"),
        ((-1,0), "south_out", "north_in"),
        ((0, 1), "east_out", "west_in"),
        ((0,-1), "west_out", "east_in"),
    )
    mod0_offsets = squash([
        Offset(a, "$b[$i]", "$c[$i]") 
        for (a,b,c) in mod0_skeleton, i in 0:style.links-1
    ])
    mod0_rule = ConnectionRule(
        mod0_offsets, 
        source_filter = filter_proc,
        dest_filter = filter_proc,
        address_filter = x -> mod(x[1], 4) == 0
    )

    # Mod 1 row
    mod1_skeleton = (
        ((-1,0), "south_left_out", "north_right_in"),
        ((-1,1), "south_right_out", "north_left_in"),
        ((1,0), "north_out", "south_in"),
        ((0, 1), "east_out", "west_in"),
        ((0,-1), "west_out", "east_in"),
    )
    mod1_offsets = squash([
        Offset(a, "$b[$i]", "$c[$i]") 
        for (a,b,c) in mod1_skeleton, i in 0:style.links-1
    ])
    mod1_rule = ConnectionRule(
        mod1_offsets, 
        source_filter = filter_proc,
        dest_filter = filter_proc,
        address_filter = x -> mod(x[1], 4) == 1
    )

    # mod 2 row
    mod2_skeleton = (
        ((1, 1), "north_right_out", "south_left_in"),
        ((1, 0), "north_left_out", "south_right_in"),
        ((-1,0), "south_out", "north_in"),
        ((0, 1), "east_out", "west_in"),
        ((0,-1), "west_out", "east_in"),
    )
    mod2_offsets = squash([
        Offset(a, "$b[$i]", "$c[$i]") 
        for (a,b,c) in mod2_skeleton, i in 0:style.links-1
    ])
    mod2_rule = ConnectionRule(
        mod2_offsets, 
        source_filter = filter_proc,
        dest_filter = filter_proc,
        address_filter = x -> mod(x[1], 4) == 2
    )

    # Mod 3 row
    mod3_skeleton = (
        ((-1,-1), "south_left_out", "north_right_in"),
        ((-1,0), "south_right_out", "north_left_in"),
        ((1,0), "north_out", "south_in"),
        ((0, 1), "east_out", "west_in"),
        ((0,-1), "west_out", "east_in"),
    )
    mod3_offsets = squash([
        Offset(a, "$b[$i]", "$c[$i]") 
        for (a,b,c) in mod3_skeleton, i in 0:style.links-1
    ])
    mod3_rule = ConnectionRule(
        mod3_offsets, 
        source_filter = filter_proc,
        dest_filter = filter_proc,
        address_filter = x -> mod(x[1], 4) == 3
    )

    return [mod0_rule, mod1_rule, mod2_rule, mod3_rule]
end

function port_boundaries(::Rect5, orientation) 
    coords = Dict(
        "east" => ((1,0), (1,1)),

        "north_right"    => ((1, 1), (0.67, 1)),
        "north"         => ((0.67 ,1), (0.33,1)),
        "north_left"   => ((0.33 ,1), (0,1)),

        "west"          => ((0,0), (0,1)),

        "south_right"    => ((1, 0), (0.67, 0)),
        "south"         => ((0.67,0), (0.33,0)),
        "south_left"   => ((0.33,0), (0, 0))
    )

    return coords[orientation]
end

function initial_offset(::Rect5, orientation, direction)
    # Select where to start between the start and stop coordinates depending
    # on the direction selected
    starts = Dict(
        ( "north_left", Output ) => 0.55,
        ( "north", Output ) => 0.55,
        ( "north_right", Output ) => 0.55,
        ( "east" , Output ) => 0.55,
        ( "south_left", Input ) => 0.55,
        ( "south", Input ) => 0.55,
        ( "south_right", Input ) => 0.55,
        ( "west" , Input ) => 0.55,

        ( "north_left", Input ) => 0.55,
        ( "north", Input ) => 0.05,
        ( "north_right", Input ) => 0.55,
        ( "east" , Input ) => 0.05,
        ( "south_left", Output ) => 0.55,
        ( "south", Output ) => 0.05,
        ( "south_right", Output ) => 0.55,
        ( "west" , Output ) => 0.05,
    )

    return starts[(orientation, direction)]
end

# Extend `cartesian` to get the shifting of boxes correct
function cartesian(::Rect5, x, y)
    if mod(x, 4) == 1 || mod(x, 4) == 2
        return (1.5 * x, 1.5 * y + 0.75)
    end
    return (1.5*x, 1.5 * y)
end
