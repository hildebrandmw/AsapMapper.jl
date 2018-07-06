module AnalysisPlots

#=
Collection of methods plotting results from mapping characterization.

(experiment_1)
=#
using PGFPlotsX
using JSON
using Parameters

# For storing the data in a tabular format.
using DataFrames
using IterableTables
using JuliaDB

# For Quantile calculations for making box plots.
import StatsBase

import Base.Iterators.filter

# Methods for opening and reading result files.
function readresults(s)
    open(joinpath(@__DIR__, s, "results_mapper_in.json")) do f
        JSON.parse(f)
    end
end

################################################################################
# Singleton types to control dispatch to various plot generation functions.
abstract type AbstractPlotType end
struct BoxPlot <: AbstractPlotType end

@with_kw struct TopPlot{T <: AbstractPlotType}
    x :: Function
    y :: Function
    label_keys :: Vector{Symbol} = Symbol[]
    label_values :: Vector{Function} = Function[]
    title  :: String = ""
    xlabel :: String = ""
    ylabel :: String = ""
end

# All the color keywords recognized by PGFPlots. Taken from the manual - page 191.
colors() = (
    "red",
    "green",
    "blue",
    "cyan",
    "magenta",
    "yellow",
    "black",
    "gray",
    "darkgray",
    "lightgray",
    "brown",
    "lime",
    "olive",
    "orange",
    "pink",
    "purple",
    "teal",
    "violet",
)

function makelabel(labels, label_filters, data)
    strings = String[]
    for (label, filter) in zip(labels, label_filters)
        push!(strings, "$(strip_and_title(label)): $(filter(data))") 
    end
    return join(strings, " ")
end

function createlegend(t::TopPlot, data)
    # Gather the labels.
    labels = unique([makelabel(t.label_keys, t.label_values, d) for d in data])

    # Make a color map mapping labels to colors
    colormap = Dict(l => c for (l,c) in zip(labels, colors()))

    # Now, iterate through all the groups again, getting their color and 
    # building a vector of string "\addlegendimage{ ... }" blocks.
    #
    # Return the "legend" and the above vector to allow both to be splatted
    # into the final image.
    images = ["\\addlegendimage{line legend,$(colormap[l])}" for l in labels]

    return labels, images, colormap
end

function plot(t::TopPlot, data)
    # First, create the legend entries and custom legend images.
    labels, images, colormap = createlegend(t, data)

    # Gather a list of box plots for all of the filtered data.
    plots = []
    for d in data
        # Get the color for this dataset by creating a label for it and looking
        # up the color in the colormap
        color = colormap[makelabel(t.label_keys, t.label_values, d)]

        push!(plots, makeplot(t, d, color))
    end

    # Create a Tikz picture for the box plots. Ensure the boxes are oriented
    # vertically for maximal aesthetic.
    @pgf Axis({ "boxplot/draw direction" = "y",
                title = t.title,
                xlabel = t.xlabel,
                ylabel = t.ylabel,
                legend_entries = {
                    labels...
                },
                legend_pos = "outer north east",
               },
              # Splat images
              images...,
              plots...,
             )
end

function makeplot(t::TopPlot{BoxPlot}, data, color)
    # Expect data to be a vector of "data" dictionaries.
    # "x" should be the key for the x value, and "y" should be the key for
    # the "y" value.
    #
    # This routine will return a pgf "Plot" type for a box plot of this data item.

    # Average the "x" values to get the "x" coordinate of the box.
    x = t.x(data)
    y = t.y(data)

    # Compute the quartiles manually using StatsBase
    # This does not get the outliers, but we'll ignore that for now.
    quartiles = StatsBase.nquantile(y, 4)

    # Create a boxplot PGF plot. For the inner table fo values, must give the
    # option "y_index=0" to avoid TeX from erroring out for some reason.
    #
    # Also, give the x draw position so boxes will be spaced by their running
    # time.
    plt =  @pgf Plot({boxplot_prepared = {
                        lower_whisker  = quartiles[1],
                        lower_quartile = quartiles[2],
                        median         = quartiles[3],
                        upper_quartile = quartiles[4],
                        upper_whisker  = quartiles[5],
                        draw_position = x,
                        box_extend = 20,
                        whisker_extend = 40,
                        },
                      color = color,
                    },
                     Table(Array{Any}(0,0)),
                )

    return plt
end

################################################################################
# Include descriptions.
include("PlotDescriptions.jl")
include("DB.jl")

end # module AnalysisPlots
