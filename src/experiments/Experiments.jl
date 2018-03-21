struct FunctionCall
    f       ::Function
    args    ::Tuple
    kwargs  ::Dict{Symbol,Any}
    FunctionCall(f, args::Tuple = (), kwargs = Dict{Symbol,Any}()) = new(f, args, kwargs)
end
call(f::FunctionCall, args...) = (f.f)(args..., f.args...; f.kwargs...)

abstract type Experiment end
abstract type Result end

################################################################################
# Includes
################################################################################
include("Simple.jl")
include("SharedPlacement.jl")
include("MultiArch.jl")

################################################################################
# Saving
################################################################################

const _datafile = "data.jls.gz"
const _exprfile = "expr.jls.gz"
dirstring(::Experiment) = "experiment"

results_dir() = joinpath(RESULTS, string(Date(now())))

function save(exp::Experiment, dir::String)
    ispath(dir) || mkpath(dir)
    fullpath = augment(dir, _exprfile)
    @assert ispath(fullpath) == false

    # serialize
    f = GZip.open(fullpath, "w")
    serialize(f, exp)
    close(f)
end

function save(r::Result, dir::String)
    ispath(dir) || mkpath(dir)
    fullpath = augment(dir, _datafile)
    @assert ispath(fullpath) == false

    # serialize
    f = GZip.open(fullpath, "w")
    serialize(f, r)
    close(f)
end

################################################################################
# Helper functions
################################################################################
stripped_contents(dir::String) = [first(gzsplitext(i)) for i in readdir(dir)]
number_regex(str) = Regex("(?<=$(str)_)\\d+")

function append_suffix(iter, key::String)
    rgx = number_regex(key)

    matches = Int[]
    for k in iter
        attach!(matches, match(rgx, k))
    end

    return length(matches) == 0 ? "$(key)_1" : "$(key)_$(1+maximum(matches))"
end

attach!(a, m) = nothing
function attach!(a::Vector{T}, m::RegexMatch) where T
    val = tryparse(T, m.match)
    if !isnull(val)
        push!(a, val.value)
    end
end

function gzsplitext(s)
    y,z = splitext(s)
    if z == ".gz"
        x,y = splitext(y)
        return x, y*z
    end
    return y,z
end


"""
    augment(dir::String, new::String)

Add a numeric suffix to `new` so it does not conflict with anything in directory
`dir`. Create `dir` if it does nto exist.
"""
function augment(dir::String, new::String)
    dir = isempty(dir) ? "." : dir
    ispath(dir) || mkpath(dir)

    prefix, ext = gzsplitext(new)
    newprefix = append_suffix(stripped_contents(dir), prefix)

    return joinpath(dir, newprefix*ext)
end

# Fallback experiment based augment function
augment(dir::String, ex::Experiment) = augment(dir, dirstring(ex))
