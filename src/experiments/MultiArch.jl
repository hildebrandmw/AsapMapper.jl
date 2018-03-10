"""
    MultieArchitecture <: Experiment

This experiment tests mapping the same taskgraph to multiple different 
architecture 
"""
struct MultiArchitecture <: Experiment
    archs   ::Vector{FunctionCall}
    app     ::FunctionCall
    place   ::FunctionCall
    route   ::FunctionCall
end
