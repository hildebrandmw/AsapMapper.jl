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


# Helful for routines that specify connection rules. collect all elements of
# a tuple hierarchy.
splatify(a::Tuple) = (splatify(a[1])..., splatify(a[2:end])...)
splatify(a::Tuple{}) = ()
splatify(a) = (a,)

struct Splatter{I}
    iter::I 
end

Base.start(s::Splatter) = start(s.iter)
function Base.next(s::Splatter, state) 
    (ns, nextstate) = next(s.iter, state)
    return (splatify(ns), nextstate)
end
Base.done(s::Splatter, state) = done(s.iter, state)
