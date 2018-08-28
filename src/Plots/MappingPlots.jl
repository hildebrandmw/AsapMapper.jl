using RecipesBase
#using Plots
#gr()

using Mapper2.MapperGraphs
#pyplot()

################################################################################
# Post routing plotting.
################################################################################
struct DrawBox
    x           ::Float64
    y           ::Float64
    width       ::Float64
    height      ::Float64
    fill        ::Symbol
    core_bin    ::Union{Float64,Missing}
    task_bin    ::Union{Float64,Missing}
end

# ------- #
# Methods #
# ------- #

# Given a box, give X and Y vectors to trace the outline of the box.
getx(d::DrawBox) = [d.x, d.x + d.width, d.x + d.width, d.x, d.x]
gety(d::DrawBox) = [d.y, d.y, d.y + d.height, d.y + d.height, d.y]

# Pointers to corners in the box. Useful for printing text in the upper left
# or lower right.
lowerleft(d::DrawBox) = (d.x + d.width/4, d.y + d.height/4)
upperright(d::DrawBox) = (d.x + 3*d.width/4, d.y + 3*d.height/4)

# Methds for getting upper right/lower left triangles for a box. Was
# experimenting with using color to represent various frequency values and core
# values. This didn't really work so well.
utrianglex(d::DrawBox) = [d.x, d.x + d.width, d.x, d.x]
utriangley(d::DrawBox) = [d.y, d.y, d.y + d.height, d.y]
ltrianglex(d::DrawBox) = [d.x + d.width, d.x + d.width, d.x, d.x + d.width]
ltriangley(d::DrawBox) = [d.y + d.height, d.y, d.y + d.height, d.y + d.height]

# Encoding for a route through the architecture.
struct DrawRoute
    x       ::Vector{Float64}
    y       ::Vector{Float64}
    color   ::Symbol
end

# --------------- #
# Plotting Recipe #
# --------------- #
struct PlotWrapper{T}
    map::Map
end

RoutePlot(x) = PlotWrapper{true}(x)
RatsnestPlot(x) = PlotWrapper{false}(x)

@recipe function f(r::PlotWrapper{T}) where T
    # Unpack map
    map = r.map
    

    # Set up parameters
    spacing = 10
    tilesize = 20

    # Build boxes and routes
    boxes = getboxes(map, spacing, tilesize)
    routes = T ? getroutes(map, spacing, tilesize) : getlines(map, spacing, tilesize)

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

function getboxes(m::Map{2}, spacing, tilesize)
    a = m.toplevel
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
            task = MapperCore.gettask(m, addr)

            task_rank = getrank(task)
            if ismissing(task_rank)
                task_bin = missing
            else
                task_bin = task_rank.normalized_rank
            end
        else
            fill = :white
            task_bin = missing
        end

        #core_bin = round(Mapper2.get_metadata!(child, "rank").normalized_rank, 2)
        core_bin = 2
        push!(boxes, DrawBox(x, y, width, height, fill, core_bin, task_bin))
    end
    return boxes
end

function getroutes(m::Map{2}, spacing, tilesize)
    a = m.toplevel
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

function getlines(m::Map{2}, spacing, tilesize)
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
