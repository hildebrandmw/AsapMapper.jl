module AsapMapper

using Mapper2
using IterTools
using JSON
using Logging
using DataStructures

import Base: parse
# Set up directory paths
const SRCDIR = @__DIR__
const PKGDIR = dirname(SRCDIR)

#set_logging(level) = configure_logging(AsapMapper, min_level=level)
set_logging(level) = nothing

export  place_and_route,
        testmap,
        asap_place,
        parallel_map_and_save,
        place!,
        route!,
        set_logging,
        # Taskgraph constructors
        load_taskgraph,
        # Architecture constructors
        asap4,
        asap3,
        Rectangular,
        Hexagonal,
        # Architecture types
        KC,
        # Misc
        FunctionCall,
        call,
        # Project Manger interface
        PMConstructor,
        SimConstructor,
        build_map

# Helper Functions
function oneofin(a,b)
    for i in a
        i in b && return true
    end
    return false
end

const push_to_dict = Mapper2.Helper.push_to_dict

################################################################################
# Attributes to determine what tasks may be mapped to which components in
# the architecture.
################################################################################
abstract type MapConstructor end

################################################################################
# Custom Architecture used by this Framework
################################################################################

# Invariants on the type:
#
# - Frequency and Multi are concrete Bool and cannot both be `true`.
abstract type AbstractKC <: RuleSet end

struct KC{Frequency} <: AbstractKC
    # Inner constructor to enforce invariants on the type parameters.
    # Specifically, need to make sure "Frequency" and "Multi" are both
    # booleans and not both "Bool" at the same time.
    function KC{F}() where {F}
        if !isa(F, Bool)
            error("Please use Boolean type parameters for KC")
        end
        return new{F}()
    end
end
struct Asap2 <: AbstractKC end

include("Helper.jl")
include("Metadata.jl")

# Architectures
include("cad_models/cad_models.jl")
#include("experimental_models/experimental_models.jl")
#include("models/models.jl")

# Include files
include("PM_Interface/PM_Interface.jl")
include("Simulator_Interface.jl")
include("Mapper2_Interface.jl")

# Customize placement/routing plus architectures.
include("PNR.jl")

#include("IP_Router/Router.jl")
include("Plots/MappingPlots.jl")

################################################################################
# Generic Place and Route function.
################################################################################

function place_and_route(profile_path, dump_path)
    # swoop(profile_path)
    # Initialize an uncompressed taskgraph constructor
    c = PMConstructor(profile_path)
    m = build_map(c)

    # Run place-and-route
    if typeof(m.options[:existing_map]) <: Nothing
        m = asap_pnr(m)
    end
    # Dump mapping to given dump path
    dump_map(m, dump_path)
end

function parallel_map_and_save(input_file, output_dir, num_mappings)
    # Make output directory if it does not exist.
    if !isdir(output_dir)
        mkdir(output_dir)
    end

    # Launch a parallel mapping
    c = PMConstructor(input_file)
    maps = pmap((i) -> (asap_pnr ∘ build_map)(c), 1:num_mappings)

    for (i,m) in enumerate(maps)
        savepath = joinpath(output_dir, "map_$(i).jls")
        Mapper2.MapperCore.save(m, savepath)
    end
end

end # module
