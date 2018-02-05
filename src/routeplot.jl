using Plots
#Plots.gr()
Plots.pyplot()

function plot_route(m, spacing, b)
    # spacing = separation distance between tiles
    # b = length of a tile

    a = m.architecture # get the architecture to index the path
    edges = m.mapping.edges # includes edges from taskgraph

    p = Plots.plot(legend = :none)
    draw_tiles(a, spacing, b) # plot all the tiles in the architecture

    bigx = Vector{Array{Float64,1}}() # preallocate arrays to store global ports
    bigy = Vector{Array{Float64,1}}()
    sym = Array{Symbol,1}()

    count = 0
    for edge in edges
        x = Array{Float64,1}()
        y = Array{Float64,1}()

        symbol_count = 0
        for port in edge.path
            address = port.path.address
            x_offset = address.addr[1]*(spacing+b) # apply spacing and b offsets
            y_offset = address.addr[2]*(spacing+b)

            if isglobalport(port)
                x_offset += a[port].metadata["x"]*b # apply metadata offsets
                y_offset += (1-a[port].metadata["y"])*b
                push!(x, x_offset) # push into local edge array
                push!(y, y_offset)
                count += 1
                symbol_count += 1
            end
        end

        # sort the arrows distances according to num hops
        if symbol_count == 2
            for i = 1:length(x)
                push!(sym,:green)
            end
        elseif symbol_count >= 3 && symbol_count <= 5
            for i = 1:length(x)
                push!(sym,:yellow)
            end
        else
            for i = 1:length(x)
                push!(sym,:red)
            end
        end
        push!(bigx,x) # push local edge arrays into global array
        push!(bigy,y)
    end
    println(count)
    println(length(sym))
    x1 = zeros(Float64, 2, count) # 2 dimension arrays used for plotting arrows
    y1 = zeros(Float64, 2, count)

    count = 1
    for x in bigx
        for i = 1:length(x)
            if x[i] != x[end]
            # if port is not an ending port for a particular edge
                x1[1,count] = x[i]
                x1[2,count] = x[i+1]
            else
                x1[1,count] = x[i]
                x1[2,count] = x[i]
            end
            count += 1
        end
    end

    count = 1
    for y in bigy
        for i = 1:length(y)
            if y[i] != y[end]
            # if port is not an ending port for a particular edge
                y1[1,count] = y[i]
                y1[2,count] = y[i+1]
            else
                y1[1,count] = y[i]
                y1[2,count] = y[i]
            end
            count += 1
        end
    end

    Plots.plot!(x1, y1, line = :arrow, #linecolor = sym,
                linewidth = 1)

    savefig("test.png")
end

function draw_tiles(arch, spacing, b)

    x = Array{Float64,1}()
    y = Array{Float64,1}()

    for key in keys(arch.children)
        push!(x,key.addr[1]*(spacing+b))
        push!(y,key.addr[2]*(spacing+b))
    end # iterate through the children in TopLevel to obtain all the addresses

    draw_square(x, y, b) # call function to draw shape for the tile

end

function draw_square(x, y, b)

    x1 = zeros(Float64, 2, length(x)*4) # 2 dimension arrays used for plotting squares
    y1 = zeros(Float64, 2, length(y)*4)

    for i = 1:length(x)

        x1[:,(i-1)*4+1] = [x[i],x[i]+b]
        x1[:,(i-1)*4+2] = [x[i]+b,x[i]+b]
        x1[:,(i-1)*4+3] = [x[i]+b,x[i]]
        x1[:,(i-1)*4+4] = [x[i],x[i]]

        y1[:,(i-1)*4+1] = [y[i],y[i]]
        y1[:,(i-1)*4+2] = [y[i],y[i]+b]
        y1[:,(i-1)*4+3] = [y[i]+b,y[i]+b]
        y1[:,(i-1)*4+4] = [y[i]+b,y[i]]

    end
    Plots.plot!(x1, y1, color = :black, linewidth = 1)

end
