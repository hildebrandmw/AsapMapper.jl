module AsapMapper

#const USEPLOTS = true

using Mapper2
using IterTools, JSON, GZip
using MicroLogging

# Set up directory paths
const SRCDIR = @__DIR__
const PKGDIR = dirname(SRCDIR)
const RESULTS_DIR = joinpath(PKGDIR, "results")

export  testmap,
        place,
        route

# Helpful Functions
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

# Custom save format for the Project Manager
include("MapDump.jl")

include("RunFunctions.jl")
include("Tests.jl")
include("Results.jl")

include("Plots.jl")

end # module
