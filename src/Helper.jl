struct PathWalker{G}
    g::G
end

pathwalk(g::G) where G = PathWalker(g)

Base.start(p::PathWalker) = first(Mapper2.Helper.source_vertices(p.g))
function Base.next(p::PathWalker, s) 
    o = Mapper2.Helper.outneighbors(p.g, s)
    return isempty(o) ? (s,nothing) : (s, first(o))
end
Base.done(p::PathWalker, s) = s == nothing
