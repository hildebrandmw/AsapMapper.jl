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

struct SimpleResult <: Result
    arch    ::FunctionCall
    app     ::FunctionCall
    mapping ::Vector{Vector{Mapping}}
end

function run(exp::SimpleExperiment, dir = results_dir())
    dir = augment(dir,ex)
    save(exp, dir)
    arch = call(exp.arch)
    app  = call(exp.app)
    # Run place and route
    call(exp.place, arch, app)
    results = call(exp.route, arch, app)
    
    result_struct = SimpleResult(exp.arch, exp.app, results)
    save(result_struct, dir)
end
