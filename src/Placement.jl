#=
High level placement routines.
=#
function shotgun_placement(arch     ::TopLevel,
                           taskgraph::Taskgraph;
                           nplacements::Int = 1,
                           nsamples::Int    = 1,
                           kwargs...)

    @info "Total Placements: $(nplacements)"
    # closure for parallel placement 
    p(x) = low_temp_placement(arch, taskgraph, x;
                              nsamples = nsamples,
                              kwargs...)

    # Parallelize placements
    pmap(x -> p(x), 1:nplacements)
end

function low_temp_placement(arch            ::TopLevel,
                            taskgraph       ::Taskgraph,
                            iteration_number::Int;
                            nsamples = 1,
                            place_kwargs...)

    @info "Sublacement iteration $iteration_number"
    # Construct a new Map object
    m = NewMap(arch, taskgraph)
    # Get the placement structure
    pstruct = SAStruct(m)
    # Scope "state" out of the loop to avoid renaming.
    local state
    for i = 1:nsamples
        if i == 1
            state = SA.place(pstruct; place_kwargs...)
        else
            SA.place(pstruct;
                    place_kwargs...,
                    supplied_state = state,
                    warmer = SA.TrueSAWarm()
                )
        end
        Mapper2.SA.record(m, pstruct)

        # serialize to temp/ dir so routing can find it.
        savename    = "$(iteration_number)_$(i)"
        save_path   = joinpath(PKGDIR, "temp", savename)
        Mapper2.MapperCore.save(m, save_path)
    end
end
