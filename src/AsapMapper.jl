module AsapMapper

const is07 = VERSION > v"0.7.0-"

using Mapper2
using IterTools, JSON, GZip
is07 ? (using Logging) : (using MicroLogging)
using Missings
using Compat

# Set up directory paths
const SRCDIR = @__DIR__
const PKGDIR = dirname(SRCDIR)
const RESULTS = joinpath(PKGDIR, "results")
const APPS    = joinpath(PKGDIR, "apps")

set_logging(level) = configure_logging(AsapMapper, min_level=level)


export  place_and_route,
        testmap,
        asap_place,
        place,
        route,
        set_logging,
        # Taskgraph constructors
        load_taskgraph,
        # Architecture constructors
        asap4,
        asap3,
        # Architecture types
        KCStandard,
        KCNoWeight,
        # Experiments
        Experiment,
        SharedPlacement,
        MultiArchitecture,
        # Results
        Result,
        SharedPlacementResult,
        # Misc
        FunctionCall,
        call

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

struct KC{EdgeWeight,Freq} <: AbstractArchitecture end

include("Helper.jl")

# Architectures
include("cad_models/cad_models.jl")
include("experimental_models/experimental_models.jl")
#include("models/models.jl")

# Include files
include("PM_Interface.jl")
include("Mapper2_Interface.jl")

# For communication with the project manager
include("Dump.jl")

# Customize placement/routing plus architectures.
include("PNR.jl")
include("experiments/Experiments.jl")

include("Plots.jl")


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
    # Run pnr, do 3 retries.
    num_retries = 3
    lowtemp_pnr(m, num_retries)
    # Dump mapping to given dump path
    dump_map(m, dump_path)
end

end # module
