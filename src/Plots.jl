using Plots
#gr()
pyplot()

################################################################################
# Post routing plotting.
################################################################################

struct PathWalker{G}
    g::G
end

pathwalk(g::G) where G = PathWalker(g)

Base.start(p::PathWalker) = first(Mapper2.Helper.source_vertices(p.g))
function Base.next(p::PathWalker, s) 
    o = Mapper2.Helper.outneighbors(p.g, s)
    return isempty(o) ? (s,nothing) : (s, first(o))
end
Base.done(p::PathWalker, s) = s == nothing


"""
    plot_route(m::Map, spacing, tilesize)

Plot the routing of a mapped taskgraph

* `spacing` - sepration distance between tile in the architecture.
* `tilesize` - the size of each tile
"""
function plot_route(m, spacing = 20, tilesize = 20)

    a     = m.architecture # get the architecture to index the path
    edges = m.mapping.edges # includes edges from taskgraph

    p = Plots.plot(legend = :none)
    draw_tiles(a, spacing, tilesize) # plot all the tiles in the architecture

    bigx = Vector{Array{Float64,1}}() # preallocate arrays to store global ports
    bigy = Vector{Array{Float64,1}}()
    colors = Symbol[]

    count = 0
    for edge in edges
        x = Float64[]
        y = Float64[]

        symbol_count = 0
        for port in pathwalk(edge)
            # Filter out muxes
            typeof(port) <: AddressPath && continue

            address = port.path.address

            x_offset = address[2]*(spacing+tilesize)
            y_offset = address[1]*(spacing+tilesize) # apply spacing and tilesize offsets
            if isglobalport(port)
                x_offset += a[port].metadata["x"]*tilesize # apply metadata offsets
                y_offset += a[port].metadata["y"]*tilesize
                push!(x, x_offset) # push into local edge array
                push!(y, y_offset)
                count += 1
                symbol_count += 1
            end
        end

        # sort the arrows distances according to num hops
        if symbol_count == 2
            push!(colors,:blue)
        elseif symbol_count >= 3 && symbol_count <= 5
            push!(colors,:black)
        else
            push!(colors,:red)
        end
        push!(bigx,x) # push local edge arrays into global array
        push!(bigy,y)
    end

    # I'm not sure why this has to be defined for this to work, but apparently
    # it does.
    #
    # Using "sym" as a column vector does not apply colors correctly, and
    # transpose does not work because "transpose" is not defined for symbols.
    #
    # We could overwrite the base "transpose" as "Base.transpose(s::Symbol) = s"
    # but this is gross, so we do this.
    linecolors = reshape(colors, (1,:))

    Plots.plot!(bigx, bigy, 
                linecolor = linecolors,
                linewidth = 1,
                arrow = arrow(tilesize/50,tilesize/50),
                yflip = true,
               )

    gui()
    #savefig("test.png")
end

function draw_tiles(arch, spacing, tilesize)

    x = Array{Float64,1}()
    y = Array{Float64,1}()

    for key in keys(arch.children)
        push!(x,key[2]*(spacing+tilesize))
        push!(y,key[1]*(spacing+tilesize))
    end # iterate through the children in TopLevel to obtain all the addresses

    draw_square(x, y, tilesize) # call function to draw shape for the tile

end

function draw_square(x, y, tilesize)

    x1 = zeros(Float64, 2, length(x)*4) # 2 dimension arrays used for plotting squares
    y1 = zeros(Float64, 2, length(y)*4)

    for i = 1:length(x)

        x1[:,(i-1)*4+1] = [x[i],x[i]+tilesize]
        x1[:,(i-1)*4+2] = [x[i]+tilesize,x[i]+tilesize]
        x1[:,(i-1)*4+3] = [x[i]+tilesize,x[i]]
        x1[:,(i-1)*4+4] = [x[i],x[i]]

        y1[:,(i-1)*4+1] = [y[i],y[i]]
        y1[:,(i-1)*4+2] = [y[i],y[i]+tilesize]
        y1[:,(i-1)*4+3] = [y[i]+tilesize,y[i]+tilesize]
        y1[:,(i-1)*4+4] = [y[i]+tilesize,y[i]]

    end
    Plots.plot!(x1, y1, color = :black, linewidth = 1)

end
