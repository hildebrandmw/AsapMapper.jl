"""
    SharedPlacement <: Experiment

The goal of this experiment is to test how different routing configurations
affect the final number of global links needed for routing.

This experiment accelerates gathering data on different routing styles if
placement semantices are not changed for different architecture arguments.

# Fields
* `arch::Function` - Constructor for the architecture (`<: TopLevel`) used for
    this experiment.
* `arch_args::Vector` - A vector of arguments to be passed to the `arch`
    constuctor. Generally, the argument tuples in this field should not change
    the placement semantics of the architecture. Only the availability of
    routing resources. This is provided as a speed optimization where multiple
    different routing styles can share a single placement.
* `place::FunctionCall` - Call to placement function.
* `route::FunctionCall` - Call to routing function.
"""
struct SharedPlacement <: Experiment
    arch        ::Function
    arch_args   ::Vector
    arch_kwargs ::Vector
    app         ::FunctionCall
    place       ::FunctionCall
    route       ::FunctionCall
end

dirstring(::SharedPlacement) = "shared_placement"

struct SharedPlacementResult <: Result
    arch        ::FunctionCall
    app         ::FunctionCall
    mappings    ::Vector{Vector{Mapping}}
end

function run(ex::SharedPlacement, dir::String = results_dir())
    dir = augment(dir,ex)
    # Create the first architecture for placement
    fn = FunctionCall(ex.arch, first(ex.arch_args), first(ex.arch_kwargs))
    firstarch = call(fn)
    app = call(ex.app)
    # placement
    call(ex.place, firstarch, app)
    # Iterate through all architectures routing each.
    for (args,kwargs) in zip(ex.arch_args, ex.arch_kwargs)
        constructor = FunctionCall(ex.arch, args, kwargs)
        arch = call(constructor)
        results = call(ex.route, arch, app)
        # make a results struct 
        arch_fcall = FunctionCall(ex.arch, args, kwargs)
        results_struct = SharedPlacementResult(arch_fcall, ex.app, results)
        save(results_struct, dir)
    end
    save(ex, dir)
end

function testrun()
    arch        = asap4 
    arch_args   = [(2,KCStandard),
                   (3,KCStandard)]
    arch_kwargs = [Dict{String,Any}(),Dict{String,Any}()]

    app     = FunctionCall(load_taskgraph, ("alexnet",))

    pnr_kwargs = Dict(
        :nplacements => 2,
        :nsamples    => 2
     )
    place   = FunctionCall(shotgun_placement, (), pnr_kwargs)
    route   = FunctionCall(low_temp_route, (), pnr_kwargs)

    expr = SharedPlacement(arch, arch_args, arch_kwargs, app, place, route)
    run(expr)
end
