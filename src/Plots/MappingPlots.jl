using Plots
gr()
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
@userplot RoutePlot
@recipe function f(r::RoutePlot)
    # Set up plot attributes
    legend := false
    ticks  := nothing
    grid   := false
    yflip  := true


    # Find the maximum ratio.
    boxes = r.args[1]

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

        core_bin = round(Mapper2.get_metadata!(child, "rank").normalized_rank, 2)
        push!(boxes, DrawBox(x, y, width, height, fill, core_bin, task_bin))
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

################################################################################

plot_ranks(m::Map; nbins = 10) = rankplot(m, nbins)

@userplot rankplot

@recipe function f(r::rankplot)
    m = r.args[1]
    nbins = r.args[2]

    architecture = m.architecture
    taskgraph = m.taskgraph

    # Get the ranks from the tasks and processors
    taskranks = [getrank(task) for task in getnodes(taskgraph) if isproc(task)]
    coreranks = [getrank(architecture[path]) 
                 for path in walk_children(architecture)
                 if isproc(architecture[path])]
    
    # Set up global plotting attributes.
    legend := false
    grid   := false
    link   := :none
    seriestype := :histogram
    nbins := nbins

    layout := @layout [tn{0.5w,0.5h} tqn{0.5w,0.5h}
                       cn{0.5w,0.5h} cqn{0.5w,0.5h}]

    subplot := 1
    @series begin
        [t.normalized_rank for t in taskranks]
    end

    subplot := 3
    @series begin
        [t.quartile_normalized_rank 
         for t in taskranks 
         if !ismissing(t.quartile_normalized_rank)
        ]
    end

    subplot := 2
    @series begin
        [c.normalized_rank for c in coreranks]
    end

    subplot := 4
    @series begin
        [c.quartile_normalized_rank 
         for c in coreranks 
         if !ismissing(c.quartile_normalized_rank)
        ]
    end
end
