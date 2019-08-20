# Styles - mainly for switching between hexagonal and rectangular layouts.
abstract type Style end

# Style API
links(x::Style) = x.links
iolinks(x::Style) = x.io_links

# For unifying filters for creating source/sink rules.
filter_proc(x) = search_metadata!(x, typekey(), MTypes.proc, in)
filter_io(x) = search_metadata!(
    x, 
    typekey(), 
    [MTypes.proc, MTypes.input, MTypes.output], 
    oneofin
)

filter_memproc(x) = search_metadata!(x, typekey(), MTypes.memoryproc, in)
filter_memory(n) = x -> search_metadata!(x, typekey(), MTypes.memory(n), in)

cartesian(s::Style, x::Address) = cartesian(s, Tuple(x))
cartesian(s::Style, x::Tuple) = cartesian(s, x...)

include("styles/rectangular.jl")
include("styles/five.jl")
include("styles/hexagonal.jl")

