strip_and_title(s::String) = titlecase(replace(s, "_", " "))
strip_and_title(s::Symbol) = titlecase(replace(string(s), "_", " "))

function runtime_plot(appname)
    return TopPlot{BoxPlot}(
        # Return average placement time as x values
        x = x -> mean(x[:data][:placement_time]),
        # Return vector of global links for y values.
        y = x -> x[:data][:placement_objective],
        # Make the labels the move generator and limiter
        label_keys = [:move_generator, :limit_ratio],
        label_values = [
            x -> x[:move_generator],
            x -> x[:limit_ratio],
        ],
        title = appname,
    )
end

# function ip_route_compare(appname)
#     # Create a vector of PlotGroups
#     limit_iter = [0.2, 0.3, 0.4, 0.44, 0.5]
#     move_iter = ["search", "cached"]
# 
#     color_map = Dict(
#         (0.2,"search") => "black",
#         (0.3 ,"search") => "red",
#         (0.4  ,"search")=> "blue",
#         (0.44 ,"search")=> "violet",
#         (0.5  ,"search")=> "teal",
#         (0.2  ,"cached") => "orange",
#         (0.3  ,"cached") => "magenta",
#         (0.4  ,"cached")=> "brown",
#         (0.44 ,"cached")=> "lightgray",
#         (0.5  ,"cached")=> "green"
#     )
# 
#     groups = map(Iterators.product(limit_iter, move_iter)) do x
#         # Unpack map variable
#         limit = x[1]
#         generator = x[2]
# # Create a vector of PlotDescriptions
#         PlotGroup{BoxPlot}(
#             filter = Dict("move_generator" => generator, "limit_ratio" => limit),
#             x = d -> [i["placement_time"] for i in d["data"]],
#             y = d -> [i["ip_route_objective"]/i["routing_global_links"] for i in d["data"]],
#             label = "$(strip_and_title(generator)). Limit: $limit",
#             color = color_map[x]
#         )
#     end |> x -> reshape(x, :)
# 
#     # Create the Top Plot and return it
#     return TopPlot(
#         groups = groups,
#         title = "IP Routing Ratio. App: $(strip_and_title(appname))",
#         xlabel = "Placement Time (s)",
#         ylabel = "(Global Links IP) / (Global Links Pathfinder)",
#     )
# end
# 
# function routing_runtime(appname)
#     # Create a vector of PlotGroups
#     limit_iter = [0.2, 0.3, 0.4, 0.44, 0.5]
#     move_iter = ["search", "cached"]
# 
#     color_map = Dict(
#         (0.2,"search") => "black",
#         (0.3 ,"search") => "red",
#         (0.4  ,"search")=> "blue",
#         (0.44 ,"search")=> "violet",
#         (0.5  ,"search")=> "teal",
#         (0.2  ,"cached") => "orange",
#         (0.3  ,"cached") => "magenta",
#         (0.4  ,"cached")=> "brown",
#         (0.44 ,"cached")=> "lightgray",
#         (0.5  ,"cached")=> "green"
#     )
# 
#     groups = map(Iterators.product(limit_iter, move_iter)) do x
#         # Unpack map variable
#         limit = x[1]
#         generator = x[2]
# 
#         # Create a vector of PlotDescriptions
#         PlotGroup{BoxPlot}(
#             filter = Dict("move_generator" => generator, "limit_ratio" => limit),
#             x = d -> [i["placement_time"] for i in d["data"]],
#             y = d -> [i["ip_route_solve_time"]/i["routing_time"] for i in d["data"]],
#             label = "$(strip_and_title(generator)). Limit: $limit",
#             color = color_map[x]
#         )
#     end |> x -> reshape(x, :)
# 
#     # Create the Top Plot and return it
#     return TopPlot(
#         groups = groups,
#         title = "Routing Runtime Ratios. App: $(strip_and_title(appname))",
#         xlabel = "Placement Time (s)",
#         ylabel = "(Run Time IP) / (Run Time Pathfinder)",
#     )
# end
