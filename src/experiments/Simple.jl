"""
A simple place and route of a single application to a single architecture.

# Fields
* `arch::FunctionCall` - The constructor for the architecture to use.
* `app::FunctionCall` - Constructor for the application mapped.
* `place::FunctionCall` - Placement function.
* `route::FUnctionCall` - Routing function.
"""
struct SimpleExperiment <: Experiment
    arch    ::FunctionCall
    app     ::FunctionCall
    place   ::FunctionCall
    route   ::FunctionCall
end

dirstring(::SimpleExperiment) = "simple_experiment"

struct SimpleResult{T} <: Result
    arch    ::FunctionCall
    app     ::FunctionCall
    mapping ::T
end

function run(ex::SimpleExperiment, dir = results_dir())
    dir = augment(dir,ex)
    save(ex, dir)
    arch = call(ex.arch)
    app  = call(ex.app)
    # Run place and route
    call(ex.place, arch, app)
    results = call(ex.route, arch, app)
    
    result_struct = SimpleResult(ex.arch, ex.app, results)
    save(result_struct, dir)
end

################################################################################
# Reconstruction methods.
################################################################################
function reconstruct(s::SimpleResult{T}) where T <: Mapping
    m = NewMap(call(s.arch), call(s.app))
    m.mapping = s.mapping
    return m
end

function reconstruct(s::SimpleResult{T}, i::Int) where T <: Vector{Mapping}
    m = NewMap(call(s.arch), call(s.app))
    m.mapping = s.mapping[i]
    return m
end
