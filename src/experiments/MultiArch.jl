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

dirstring(::MultiArchitecture) = "multi_arch"

function run(ex::MultiArchitecture, dir::String = results_dir())
    dir = augment(dir,ex)
    save(ex, dir)
    # Iteratively run each architecture as an experiment.
    # Save with the expanded context to allow directory nesting.
    for arch in ex.archs
        s = SimpleExperiment(arch, ex.app, ex.place, ex.route)
        run(s, dir)
    end
end
