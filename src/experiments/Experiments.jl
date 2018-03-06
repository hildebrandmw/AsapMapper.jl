struct FunctionCall
    f       ::Function
    args    ::Tuple
    kwargs  ::Dict{Symbol,Any}
    FunctionCall(f, args::Tuple = (), kwargs = Dict{Symbol,Any}()) = new(f, args, kwargs)
end

call(f::FunctionCall, args...) = (f.f)(args..., f.args...; f.kwargs...)

abstract type Experiment end
abstract type Result end

const _datafile = "data.jld2"
const _exprfile = "expr.jld2"
dirstring(::Experiment) = "experiment"

results_dir = joinpath(RESULTS, string(Date(now())))
stripped_contents(dir::String) = [first(splitext(i)) for i in readdir(dir)]

function augment(dir::String, new::String)
    dir = isempty(dir) ? "." : dir
    ispath(dir) || mkdir(dir)

    prefix, ext = splitext(new)
    newprefix = append_suffix(stripped_contents(dir), prefix)

    return joinpath(dir, newprefix*ext)
end
# Fallback experiment based augment function
augment(dir::String, ex::Experiment) = augment(dir, dirstring(ex))

function save(e::Experiment, dir::String)
    ispath(dir) || mkpath(dir)      
    fullpath = augment(dir, _exprfile)
    jldopen(fullpath, "w") do f
        f["expr"] = e
    end
end

function save(r::Result, dir::String)
    ispath(dir) || mkpath(dir)
    fullpath = augment(dir, _datafile)
    # save results as a jld file
    jldopen(fullpath, "w") do f
        f["data"] = r 
    end
end

################################################################################
# Includes
################################################################################
include("SharedPlacement.jl")
