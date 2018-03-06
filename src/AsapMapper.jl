module AsapMapper

const USEPLOTS = false

using Mapper2
using IterTools, JSON, GZip
using MicroLogging
using JLD

# Set up directory paths
const SRCDIR = @__DIR__
const PKGDIR = dirname(SRCDIR)
const RESULTS = joinpath(PKGDIR, "results/results.jld2")

export  testmap,
        place,
        route

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

const _kilocore_attributes = Set([
      "processor",
      "memory_processor",
      "fast_processor",
      "viterbi",
      "fft",
      "input_handler",
      "output_handler",
      "memory_1port",
      "memory_2port",
    ])

const _special_attributes = Set([
      "memory_processor",
      "fast_processor",
      "viterbi",
      "fft",
      "input_handler",
      "output_handler",
      "memory_1port",
      "memory_2port",
    ])


################################################################################
# Custom Architecture used by this Framework
################################################################################

abstract type AbstractKC <: AbstractArchitecture end

struct KCNoWeight <: AbstractKC end
struct KCStandard  <: AbstractKC end

# Architectures
include("models/models.jl")

# Include files
include("Taskgraph.jl")
include("Placement.jl")
include("Routing.jl")

include("RunFunctions.jl")
include("Tests.jl")
include("Results.jl")

USEPLOTS && include("Plots.jl")

################################################################################
# Useful for testing and debugging
################################################################################

function testmap()

    #arch = asap4(2, KCStandard)
    #arch = asap3_hex(2, KCStandard)
    arch = asap3(2, KCStandard)
    #arch = generic(16,16,4,12, KCStandard)

    tg = load_taskgraph("sort")
    return NewMap(arch, tg)
end

################################################################################
# Generic Place and Route function.
################################################################################

function place_and_route(architecture, profile_path, dump_path)
    # Initialize an uncompressed taskgraph constructor
    tc = SimDumpConstructor{false}("blank", profile_path)
    t = build_taskgraph(tc)

    # Dispatch architecture
    if architecture == "asap4"
        a = asap4(2, KCStandard)
    elseif architecture == "asap3"
        a = asap3(2, KCNoWeight)
    else
        KeyError("Architecture $architecture not implemented.")
    end

    # Build the Map
    m = NewMap(a, t)
    # Run placement
    m = place(m)
    # Run Routing
    m = route(m)
    # Dump mapping to given dump path
    Mapper2.save(m, dump_path, false)
end


end # module
