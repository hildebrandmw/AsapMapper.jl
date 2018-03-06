#=
Database for saving and reading results.
=#

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
