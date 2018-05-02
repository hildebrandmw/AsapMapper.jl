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
function getkeys(d::T, keys, required = true) where T <: Dict
    r = T()
    for k in keys
        if required && !haskey(d, k)
            throw(KeyError(k))
        end
        r[k] = get(d, k, missing)
    end
    return r
end
