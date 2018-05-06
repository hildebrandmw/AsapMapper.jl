# Detailed models for performing mapping to Asap3/Asap4


# Managing and including data to architecture components to routing for
# various quirks of the Asap2/3/4 architectures.
include("metadata.jl")

# Constructors for basic components of the array
include("components.jl")

# Array layouts
include("asap3.jl")
include("asap4.jl")
include("build_model.jl")
