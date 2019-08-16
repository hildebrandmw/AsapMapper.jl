using RecipesBase
#using Plots
#gr()

using Mapper2.MapperGraphs
#pyplot()

################################################################################
# Post routing plotting.
################################################################################
struct Polygon
    x::Vector{Float64}
    y::Vector{Float64}
    fill::Symbol
end

# ------- #
# Methods #
# ------- #

# Given a box, give X and Y vectors to trace the outline of the box.
getx(d::Polygon) = d.x
gety(d::Polygon) = d.y

# Encoding for a route through the architecture.
struct DrawRoute
    x       ::Vector{Float64}
    y       ::Vector{Float64}
    color   ::Symbol
end

@recipe function f(map::Map; plot_route = true)
    # Unpack map
    #map = r.map
    #plot_route = r.plot_route
    

    # Set up parameters
    spacing = 10
    tilesize = 20

    # Build boxes and routes
    boxes = getboxes(map)
    routes = plot_route ? getroutes(map) : getlines(map)

    # Set up plot attributes
    legend := false
    ticks  := nothing
    grid   := false
    yflip  := true

    # Plot boxes
    seriestype := :shape

    for box in boxes
        @series begin
            #linecolor := :black
            c := box.fill

            # Get x,y coordinates from box
            x = getx(box)
            y = gety(box)
            x, y
        end
    end

    seriestype := :path
    linewidth  := 2

    # Plot routes
    for route in routes
        @series begin
            linecolor := route.color
            x = route.x
            y = route.y
            x,y
        end
    end
end

function getboxes(m::Map{2})
    a = m.toplevel
    style = a.metadata["style"]

    # Create draw boxes for each tile in the array.
    boxes = Polygon[]
    for (name, child) in a.children
        addr = getaddress(a, name)
        # scale x,y
        if haskey(child.metadata, "shadow_offset")
            addrs = [addr + o for o in child.metadata["shadow_offset"]]
            push!(addrs, addr)
        else
            addrs = [addr]
        end

        # Unpack tuple after manipulation
        y, x = cartesian(style, dim_min(addrs))

        # fill with cyan if box address is used.
        if MapperCore.isused(m, addr)
            fill = :cyan
        else
            fill = :white
        end
        push!(boxes, Polygon(polygon(style, x, y)..., fill))
    end
    return boxes
end

function getroutes(m::Map{2})
    a = m.toplevel
    style = a.metadata["style"]

    routes = DrawRoute[]
    for graph in m.mapping.edges
        x = Float64[]
        y = Float64[]
        for path in Mapper2.MapperGraphs.linearize(graph)
            # Only look at global port paths.
            isglobalport(path) || continue
            # Get the address from the path.
            address = getaddress(a, path)

            # Create offsets for smooth paths
            metadata = a[path].metadata
            y0, x0 = cartesian(style, address)

            push!(x, x0 + get(metadata, "x", 0.5))
            push!(y, y0 + get(metadata, "y", 0.5))
        end
        # Choose color based on length of path
        if length(x) <= 2
            color = :black
        elseif length(x) <= 5
            color = :blue
        else
            color = :red
        end
        # Add this route to the routes vector
        push!(routes, DrawRoute(x, y, color))
    end
    return routes
end

function getlines(m::Map{2})
    a = m.toplevel
    lines = DrawRoute[]
    for edge in getedges(m.taskgraph)

        x = Float64[]
        y = Float64[]
        source = first(getsources(edge))
        dest   = first(getsinks(edge))

        for node in (source, dest)
            # Get the address from the path.
            path = Mapper2.MapperCore.getpath(m.mapping, node)
            address = getaddress(a, path)
            # Create offsets for smooth paths

            # Big offset for macro location in the whole array
            x_offset_big = address[2]*(spacing + tilesize)
            y_offset_big = address[1]*(spacing + tilesize)
            # Small offset for offset within a tile
            x_offset_small = get(a[path].metadata, "x", 0.5) * tilesize
            y_offset_small = get(a[path].metadata, "y", 0.5) * tilesize

            push!(x, x_offset_big + x_offset_small)
            push!(y, y_offset_big + y_offset_small)
        end
        # Default to black color
        color = :black
        # Add this route to the routes vector
        push!(lines, DrawRoute(x,y,color))
    end
    return lines
end
