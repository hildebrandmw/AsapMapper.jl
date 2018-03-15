using Plots
#gr()
pyplot()

################################################################################
# Post routing plotting.
################################################################################



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
                # Get the offsets. Default to 0.5 if metadata is not found
                # to avoid errors.
                x_offset += get(a[port].metadata, "x", 0.5)*tilesize # apply metadata offsets
                y_offset += get(a[port].metadata, "y", 0.5)*tilesize
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

function plot_ratsnest(m::Map)
    sa = SAStruct(m)
    Mapper2.SA.preplace(m, sa)
    plot_2d(sa)
end


function plot_2d(sa::SAStruct)
   #pa = tg.architecture

   #addr_length = length(addresses(pa))
   num_nodes = length(sa.nodes)

   x1 = Int64[]
   y1 = Int64[]

   max_row      = 0
   max_column   = 0

   for index in eachindex(sa.component_table)
       if length(sa.component_table[index]) > 0
           # Convert to coordinates
           (x,y) = ind2sub(sa.component_table, index)
           push!(x1, x)
           push!(y1, y)
       end
   end

   max_row      = size(sa.component_table,1)
   max_column   = size(sa.component_table,2)

   num_links  = length(sa.edges)

   x = zeros(Float64, 2, num_links)
   y = zeros(Float64, 2, num_links)

   for (index, link) in enumerate(sa.edges)
       src = getaddress(sa.nodes[link.source])
       snk = getaddress(sa.nodes[link.sink])
       y[:,index] = [src[2], snk[2]]
       x[:,index] = [src[1], snk[1]]
   end

   distance = zeros(Float64, 1, num_links)
   lc_symbol = Array{Symbol}(1, num_links)

   ##  sort the link distances according to color ##

   for i = 1:num_links
      distance[i] = sqrt((x[1,i]-x[2,i])^2+(y[1,i]-y[2,i])^2)

      if distance[i] > 10
          lc_symbol[i] = :red
      elseif distance[i] > 1
          lc_symbol[i] = :blue
      else
          lc_symbol[i] = :black
      end

   end
   ## title and legend ##

   #title = join(("Mapping for: ", sa.application_name, " on ", pa.name))
   p = Plots.plot(legend = :none, size = (700,700))
   ## plot the architecture tiles ##
   Plots.plot!(x1, y1,  shape = :rect,
                        linewidth = 0.5,
                        color = :white,
                        markerstrokewidth = 1)
   ## plot task links ##
   Plots.plot!(x, y, line = :arrow,
               linewidth = 4.0,
               linecolor = lc_symbol,
               xlims = (0,max_row+1),
               ylims = (0,max_column+1),)
   ## export as png ##
   gui()
   #savefig("plot.png")
   return nothing
end
