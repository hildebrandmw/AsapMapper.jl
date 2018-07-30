module AsapMapper

using Mapper2
using IterTools
using JSON
using Logging
using DataStructures

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
        # Architecture types
        KC,
        # Misc
        FunctionCall,
        call,
        # Project Manger interface
        PMConstructor,
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
struct KC{Frequency, Multi} <: Architecture
    # Inner constructor to enforce invariants on the type parameters.
    # Specifically, need to make sure "Frequency" and "Multi" are both
    # booleans and not both "Bool" at the same time.
    function KC{F,M}() where {F,M}
        if !isa(F, Bool) || !isa(M, Bool)
            error("Please use Boolean type parameters for KC")
        end

        if F && M
            error("""
                Parameters "Frequency" and "Multi" cannot both be `true`.
                """
            )
        end
        return new{F,M}()
    end

    # Convenience constructor
    KC{F}() where F = KC{F,false}()
end

include("Helper.jl")
include("Metadata.jl")

# Architectures
include("cad_models/cad_models.jl")
#include("experimental_models/experimental_models.jl")
#include("models/models.jl")

# Include files
include("PM_Interface/PM_Interface.jl")
include("Mapper2_Interface.jl")

# Customize placement/routing plus architectures.
include("PNR.jl")

#include("IP_Router/Router.jl")

include("Plots/MappingPlots.jl")

################################################################################
# Useful for testing and debugging
################################################################################

function testmap()
    # Build taskgraph - look in "apps" directory
    path = joinpath(PKGDIR, "apps", "mapper_in_7.json")
    options = Dict(
        #:use_frequency => true,
        #:frequency_penalty_start => 50.0,
        #:num_links => 3,
        #:architecture => FunctionCall(asap3, (2, KC{true,true})),
        #:architecture => FunctionCall(asap3, (2, KC{true,false})),
    )
    return build_map(PMConstructor(path, options))
end

################################################################################
# Generic Place and Route function.
################################################################################

function swoop(profilepath::String)
    savedir = joinpath(PKGDIR, "apps")
    # Create a name for this in the save directory.
    savename = augment(savedir, "mapper_in.json")
    savepath = joinpath(savedir, savename)

    println("Swooping")
    cp(profilepath, savepath)
end

function place_and_route(profile_path, dump_path)
    # swoop(profile_path)
    # Initialize an uncompressed taskgraph constructor
    c = PMConstructor(profile_path)
    m = build_map(c)

    # Run place-and-route
    if typeof(m.options[:existing_map]) <: Void
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
