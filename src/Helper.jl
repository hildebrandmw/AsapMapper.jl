# Type for specifying paths through nested dictionaries.
struct KeyChain{T}
    keys::T
end
KeyChain(args...) = KeyChain(args)

function Base.getindex(d::Dict, k::KeyChain)
    # Using the "pass-by-sharing" semantics, argument `d` will not be changed.
    for i in k.keys
        d = d[i]
    end
    return d
end

function Base.setindex!(d::Dict, x, k::KeyChain)
    for i in 1:length(k.keys)-1
        d = d[i]
    end
    d[endof(k.keys)] = x
end

################################################################################

type_sanitize(::Type{T}, v::T) where T = v
function type_sanitize(::Type{T}, v::U) where {T,U}
    throw(TypeError(:type_sanitize, "Unexpected type for link definitions",T,U))
end

"""
    getkeys(d::T, keys, required = true) where T <: Dict

Return a dictionary `r` of type `T` with just the requested keys and
corresponding values from `d`. If `required = true`, throw `KeyError` if a key
`k` is not found. Otherwise, set `r[k] = missing`.
"""
function getkeys(d::T, keys) where T <: Dict
    r = T()
    for k in keys
        !haskey(d,k) && throw(KeyError(k))
        r[k] = d[k]
    end
    return r
end

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

# Helpful for dealing with files with an additional .gz extension
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
`dir`. Create `dir` if it does not exist.
"""
function augment(dir::String, new::String)
    dir = isempty(dir) ? "." : dir
    ispath(dir) || mkpath(dir)

    prefix, ext = gzsplitext(new)
    newprefix = append_suffix(stripped_contents(dir), prefix)

    return joinpath(dir, newprefix*ext)
end
