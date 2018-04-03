address_wrap(a::Address) = a
address_wrap(a::NTuple{D,<:Integer}) where D = Address(a)

vector_wrap(a::Vector) = a
vector_wrap(a) = [a]

struct TileLocation{D}
    base   ::Address{D}
    offsets::Vector{Address{D}}

    # -- inner constructor for convenience calling
    function TileLocation{D}(a, b) where D
        A = address_wrap(a)
        B = address_wrap.(vector_wrap(b))
        return new{D}(A,B)
    end
end

################################################################################
abstract type InstComponent end
struct InstDef{T <: InstComponent,D}
    def      ::T
    locations::Vector{TileLocation{D}}
end

# Use special fieldnames to control more advanced instantiation routines.
# Mainly needed to ensure that Memory_Processors end up near Memories.

# Fallback method for determining if a given instcomponent has a special 
# neighbor or not.
@generated function hasneighbor(i::InstComponent)
    b = :neighbor in fieldnames(i)    
    return :($b)
end

@generated function hasshadow(i::InstComponent)
    b = :shadow in fieldnames(i)
    return :($b)
end

#-------------------------------------------------------------------------------

# Used to reserve slots in an architecture without actually doing anything.
struct Reserved <: InstComponent
end
function build(::Reserved) 
    c = Component("")
    c.metadata["inst_component"] = Reserved()
    return c
end

#-------------------------------------------------------------------------------
struct AsapProc <: InstComponent
    nlinks::Int 
    memory::Bool

    function AsapProc(nlinks::Int; memory = false)
        if nlinks <= 0
            error("Number of links for an AsapProc must be greater than 0.")
        end
        new(nlinks, memory)
    end
end

function build(a::AsapProc) 
    c = build_processor_tile(a.nlinks, include_memory = a.memory)
    c.metadata["inst_component"] = a
    return c
end

function attributes(a::AsapProc)
    if a.memory
        return ["processor", "memory_processor"]
    else
        return ["processor"]
    end
end

#-------------------------------------------------------------------------------
struct Memory{D} <: InstComponent
    nports  ::Int
    shadow  ::Vector{Address{D}}
    neighbor::AsapProc
end
function Memory(nports, neighbor, shadow::Vector{Address{D}} = [Address(0,1)]) where D
    Memory{D}(nports, shadow, neighbor)
end

function build(a::Memory) 
    c = build_memory(a.nports)
    c.metadata["inst_component"] = a
    return c
end
atributes(a::Memory) = ["memory_$(i)port" for i in 1:a.nports]

#-------------------------------------------------------------------------------
struct InputHandler <: InstComponent
    nlinks::Int
end

function build(a::InputHandler) 
    c = build_input_handler(a.nlinks)
    c.metadata["inst_component"] = a
    return c
end
attributes(a::InputHandler) = ["input_handler"]

#-------------------------------------------------------------------------------
struct OutputHandler <: InstComponent
    nlinks::Int
end

function build(a::OutputHandler) 
    c = build_output_handler(a.nlinks)
    c.metadata["inst_component"] = a
    return c
end
attributes(a::OutputHandler) = ["output_handler"]
