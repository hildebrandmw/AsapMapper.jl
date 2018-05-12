using Plots
gr()
#pyplot()

################################################################################
# Post routing plotting.
################################################################################
struct DrawBox
    x      ::Float64
    y      ::Float64
    width  ::Float64
    height ::Float64
    fill   ::Symbol    
end
getx(d::DrawBox) = [d.x, d.x + d.width, d.x + d.width, d.x, d.x]
gety(d::DrawBox) = [d.y, d.y, d.y + d.height, d.y + d.height, d.y]

struct DrawRoute
    x       ::Vector{Float64}
    y       ::Vector{Float64}
    color   ::Symbol
end

@userplot RoutePlot

@recipe function f(r::RoutePlot)
    # Set up plot attributes
    legend := false
    ticks  := nothing
    grid   := false
    yflip  := true

    # Plot boxes
    seriestype := :shape

    boxes = r.args[1]
    for box in boxes
        @series begin
            # Set fill color
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
    routes = r.args[2]
    for route in routes
        @series begin
            linecolor := route.color
            x = route.x
            y = route.y
            x,y
        end
    end
end

function getboxes(m::Map{A,2}, spacing, tilesize) where A
    a = m.architecture
    # Create draw boxes for each tile in the array.
    boxes = DrawBox[]
    for (name, child) in a.children
        addr = getaddress(a, name)
        # scale x,y
        if haskey(child.metadata, "shadow_offset")
            addrs = [addr + o for o in child.metadata["shadow_offset"]]
            push!(addrs, addr)
        else
            addrs = [addr]
        end
        scale = (spacing + tilesize)
        # Unpack tuple after manipulation
        y,x = dim_min(addrs) .* scale
        height,width = ((dim_max(addrs) .- dim_min(addrs)) .* scale) .+ tilesize

        # fill with cyan if box address is used.
        if MapperCore.isused(m, addr)
            fill = :cyan
        else
            fill = :white
        end
        push!(boxes, DrawBox(x,y,width,height,fill))
    end
    return boxes
end

function getroutes(m::Map{A,2}, spacing, tilesize) where A
    a = m.architecture
    routes = DrawRoute[]
    for graph in m.mapping.edges
        x = Float64[]
        y = Float64[]
        for path in linearize(graph)
            # Only look at global port paths.
            isglobalport(path) || continue
            # Get the address from the path.
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
        # Choose color based on length of path
        if length(x) <= 2
            color = :black
        elseif length(x) <= 5
            color = :blue
        else
            color = :red
        end
        # Add this route to the routes vector
        push!(routes, DrawRoute(x,y,color))
    end
    return routes
end

function getlines(m::Map{A,2}, spacing, tilesize) where A
    a = m.architecture
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

################################################################################
# Main functions
################################################################################

function plot_route(m::Map{A,2}, spacing = 10, tilesize = 20) where A
    boxes = getboxes(m, spacing, tilesize)
    routes = getroutes(m, spacing, tilesize)
    return routeplot(boxes, routes)
end

function plot_ratsnest(m::Map, spacing = 10, tilesize = 20)
    boxes = getboxes(m, spacing, tilesize)
    routes = getlines(m, spacing, tilesize)
    return routeplot(boxes, routes)
end
