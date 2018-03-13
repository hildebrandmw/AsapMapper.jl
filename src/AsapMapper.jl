module AsapMapper

const USEPLOTS = false

const is07 = VERSION > v"0.7.0-"

using Mapper2
using IterTools, JSON, GZip
is07 ? (using Logging) : (using MicroLogging)
using Missings
using Compat
#using JLD2, FileIO

# Set up directory paths
const SRCDIR = @__DIR__
const PKGDIR = dirname(SRCDIR)
const RESULTS = joinpath(PKGDIR, "results")

export  place_and_route,
        testmap,
        place,
        route,
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

abstract type AbstractKC <: AbstractArchitecture end

struct KCNoWeight <: AbstractKC end
struct KCStandard <: AbstractKC end

include("Helper.jl")

# Architectures
include("cad_models/cad_models.jl")
#include("models/models.jl")

# Include files
include("PMConstructor.jl")
include("Mapper2_Interface.jl")

# For communication with the project manager
include("Dump.jl")

# Customize placement/routing plus architectures.
include("Placement.jl")
include("Routing.jl")
include("experiments/Experiments.jl")

#include("Plots.jl")

################################################################################
# Useful for testing and debugging
################################################################################

function testmap()

    #arch = asap4(2, KCStandard)
    #arch = asap3_hex(2, KCStandard)
    arch = asap3(2, KCStandard)
    #arch = generic(16,16,4,12, KCStandard)

    t = build_taskgraph(PMConstructor("mapper_in.json"))
    #tg = load_taskgraph("alexnet")
    return NewMap(arch, t)
end

################################################################################
# Generic Place and Route function.
################################################################################

function place_and_route(architecture, profile_path, dump_path)
    # Initialize an uncompressed taskgraph constructor
    c = PMConstructor(architecture, profile_path)
    m = build_map(c)
    # Run placement
    m = place(m)
    # Run Routing
    m = route(m)
    # Dump mapping to given dump path
    dump_map(m, dump_path)
end

end # module
