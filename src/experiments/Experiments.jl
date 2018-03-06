struct FunctionCall
    f       ::Function
    args    ::Tuple
    kwargs  ::Dict{Symbol,Any}
    FunctionCall(f, args::Tuple = (), kwargs = Dict{Symbol,Any}()) = new(f, args, kwargs)
end

call(f::FunctionCall, args...) = (f.f)(args..., f.args...; f.kwargs...)

abstract type Experiment end
abstract type LeafExperiment <: Experiment end

struct PlaceAndRoute <: LeafExperiment
    arch    ::FunctionCall
    app     ::FunctionCall
    place   ::FunctionCall
    route   ::FunctionCall
end

typestring(::PlaceAndRoute) = "mapping"

#function create_name(context, group)
#    local name
#    jldopen(RESULTS, "r") do file
#        if !haskey(file, context)
#            name = "$(group)_0"
#        else
#            
#        end
#
#    end
#end
#
#function save(pnr::PlaceAndRoute, mappings, context = string(Date(now())))
#    jldopen(RESULTS, "a+") do file
#        
#    end
#end


################################################################################
# Includes
################################################################################
include("SharedPlacement.jl")
