# Tutorial

## Maps, Placement and Routing from the Project Manager

The main interface to AsapMapper is through the Project Manager Interface (`PM_Interface/`).
This takes a JSON file from the Project Manager and builds an architecture and taskgraph
from this file. An example of this file is `taskgraph/project_manager.json`. The following
sequence of commands shows how to use this file for a standard mapping.

```julia
julia> using AsapMapper

# Make a PM constructor, containing the path to the JSON file to parse
julia> constructor = PMConstructor("taskgraphs/project_manager.json")

# Build a `Map` object from the constructor. This will automatically choose the architecture
# to use, and construct the taskgraph from the JSON file
#
# The warnings given by AsapMapper are okay to ignore
julia> M = build_map(constructor);

# Run placement - note the the first time any function is run in Julia, it may take a little
# while since the function must be compiled. The second time will usually be much snappier.
julia> place!(M);

# Run routing. The Routing Summary info is a series of checks that runs to make sure that
# the Architecture and Taskgraph representations did not change in unexpected ways during
# the mapping process. If one of the checks fails, then the Mapper thinks something is wrong.
#
# Usually, a failure occurs when the Mapper cannot find a valid routing and the result is
# congested.
julia> route!(M);
[ Info: Running Pathfinder Routing Algorithm
┌ Info: Routing Summary
│ ---------------
│ Placement Check:    passed
│ Congestion Check:   passed
│ Port Check:         passed
│ Graph Connectivity: passed
│ Architecture Check: passed
└ Resource Check:     passed

# Report stats from the mapping. The returned object `histogram` is a dictionary containing
# the count of links of different lengths.
#
# Keys are the length of the link, and values are the number of links of that length
julia> histogram = AsapMapper.report_routing_stats(M);
Number of communication channels: 178
Total global routing links used: 246
Average Link Length: 1.3820224719101124
Maximum Link Distance: 5
Link Histogram:
DataStructures.SortedDict{Int64,Int64,Base.Order.ForwardOrdering} with 5 entries:
  1 => 131
  2 => 31
  3 => 13
  4 => 1
  5 => 2

# Plotting
# Make sure you have `Plots` installed
julia> ]

pkg> add Plots

# Import plots
julia> using Plots

# Plot the Map
julia> plot(M)
```

## Overwriting Defaults

When performing architecture exploration, it's you generally want to use a different 
architecture then that specified in the Project Manager file. This can be achieved by adding
these parameters to the `PMConstructor`. A full list of valid parameters can be found by
looking at the `_get_default_options` function in `PM_Constructor/Main.jl`. The main knob
to turn is the architecture. Suppose we wanted to map an application to Asap3 with 4 
inter-processer links instead of 2. That would be accomplished as follows:
```julia
julia> using AsapMapper

# We need to define a 0-argument function that will construct our desired architecture
julia> f() = asap3(Rectangular(4, 1))

# Create a named tuple for option overrides to the PMConstructor.
julia> overrides = (architecture = f,)

# Pass the overrides to the PMConstructor
julia> constructor = PMConstructor("taskgraphs/project_manager.json", overrides)

# Now when we place, route, and plot - it will be for the asap3 architecture
julia> M = build_map(constructor); place!(M); route!(M);

julia> using Plots

julia> plot(M)
```

## Using the Simulator for Input

Sometimes, it is easier to use the `profile.json` given by the Asap Simulator instead of 
using the Project Manager generated files. Using the Simulator output is very similar to the
Project Manager, but note that you **must** define the architecture constructor function.
```julia
julia> using AsapMapper

julia> f() = asap4(Rectangular(2,1))

julia> constructor = SimConstructor("taskgraphs/profile.json", (architecture = f,))

julia> M = build_map(constructor); place!(M); route!(M)

julia> using Plots; plot(M)
```

## Changing Placement Parameters

Generally, increasing the number of move attempts and initial temperature of the placement
will yield a higher qualityh mapping at the cost of extra run time. The documentation for
the placement algorithm is shown below:

```
place!(map::Map; kwargs...) :: SAState
```

Run simulated annealing placement directly on `map`.

Records the following metrics into `map.metadata`:

* `placement_struct_time` - Amount of time it took to build the 
    [`SAStruct`] from `map`.

* `placement_struct_bytes` - Number of bytes allocated during the construction
    of the [`SAStruct`]

* `placement_time` - Running time of placement.

* `placement_bytes` - Number of bytes allocated during placement.

* `placement_objective` - Final objective value of placement.

Keyword Arguments
-----------------
* `seed` - Seed to provide the random number generator. Specify this to a 
    constant value for consistent results from run to run.

    Default: `rand(UInt64)`

* `move_attempts :: Integer` - Number of successful moves to generate between
    state updates. State updates include adjusting temperature, move distance
    limit, state displaying etc.

    Higher numbers will generally yield higher quality placement but with a
    longer running time.

    Default: `20000`

* `initial_temperature :: Float64` - Initial temperature that the system begins
    its warming process at. Due to the warming procedure, this should not have
    much of an affect on placement.

    Default: `1.0`.

* `supplied_state :: Union{SAState,Nothing}` - State type to use for this 
    placement. Can be used to resume placement where it left off from a previous
    run. If `nothing`, a new `SAState` object will be initialized.

    Default: `nothing`

* `movegen :: MoveGenerator` - The [`MoveGenerator`] to use for this 
    placement.

    Default: [`CachedMoveGenerator`]

* `warmer` - The [`SAWarm`] warming schedule to use.

    Default: [`DefaultSAWarm`]

* `cooler` - The [`SACool`] cooling schedule to use.

    Default: [`DefaultSACool`]

* `limiter` - The [`SALimit`] move distance limiting algorithm to 
    use.

    Default: [`DefaultSALimit`]

* `doner` - The [`SADone`] exit condition to use.

    Default: [`DefaultSADone`]

To increase the number of move attempts (to say, 50000), call the place funtion like the
command below:
```julia
julia> using AsapMapper

julia> M = build_map(PMConstructor("taskgraphs/project_manager.json"));
julia> place!(M; move_attempts = 50000);
```

## Building Architecturs

The CAD models in `cad_models/` directory are the models that are guarenteed to work with 
the Mapper framework. When defining custom models, it's best to use those as a starting 
point since many of the inner functions (`build_processor_tile`, `build_memory` etc.) attach
important metadata to the inner objects that the downstream Mapper2 is expecting.

In general, though, the Mapper should do a pretty good job in figuring out what should be
done with new models. If more functionality is needed, or something is breaking, let me know!
