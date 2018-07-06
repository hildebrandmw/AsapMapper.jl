strip_and_title(s::String) = titlecase(replace(s, "_", " "))
strip_and_title(s::Symbol) = titlecase(replace(string(s), "_", " "))

function runtime_plot(appname)
    return TopPlot{BoxPlot}(
        # Return average placement time as x values
        x = x -> mean(x[:data][:placement_time]),
        # Return vector of global links for y values.
        y = x -> x[:data][:routing_global_links],
        # Make the labels the move generator and limiter
        label_keys = [:move_generator, :limit_ratio],
        label_values = [
            x -> x[:move_generator],
            x -> x[:limit_ratio],
        ],
        title = appname,
    )
end
