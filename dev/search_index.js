var documenterSearchIndex = {"docs": [

{
    "location": "#",
    "page": "Home",
    "title": "Home",
    "category": "page",
    "text": ""
},

{
    "location": "#AsapMapper-1",
    "page": "Home",
    "title": "AsapMapper",
    "category": "section",
    "text": "This is the Asap specific repo for mapping application to KiloCore like architectures."
},

{
    "location": "#Installation-1",
    "page": "Home",
    "title": "Installation",
    "category": "section",
    "text": ""
},

{
    "location": "#Step-0-Install-Julia-1",
    "page": "Home",
    "title": "Step 0 - Install Julia",
    "category": "section",
    "text": "If you do not yet have Julia installed, you can download it from  https://julialang.org/downloads/. If you are running on a Linux/OSX system, you may also want to alias the julia command to the installation location with the command below.  (Note: you can put this line in your .bashrc or .profile file to make it persistent.)alias julia=<path-to-julia-1.1.0/bin/julia>"
},

{
    "location": "#Step-1-Install-Mapper-Source-Files-1",
    "page": "Home",
    "title": "Step 1 - Install Mapper Source Files",
    "category": "section",
    "text": ""
},

{
    "location": "#Installation-for-Development-1",
    "page": "Home",
    "title": "Installation for Development",
    "category": "section",
    "text": "If you plan on modifying the Mapper, first download the source code using git:git clone https://github.com/hildebrandmw/Mapper2.jl Mapper2\ngit clone https://github.com/hildebrandmw/AsapMapper.jl AsapMapperYou have to register these packages with Julia so it can find them. To do this, open Julia and navigate to the directory where the Mapper repos were downloaded. Inside Julia, run the following commands# Enter Pkg mode\njulia> ]\n\npkg> dev ./Mapper2\n\npkg> dev ./AsapMapperAfter performing this step, Julia knows how to find the Mapper package, and they can be imported into a Julia module or into the REPL usingjulia> using Mapper2\n\njulia> using AsapMapper"
},

{
    "location": "#Installation-for-Just-Usage-1",
    "page": "Home",
    "title": "Installation for Just Usage",
    "category": "section",
    "text": "If you don\'t plan on developing the Mapper, and just want it installed and discoverable, you can download them directly through Julia\'s built in package manager using# Enger Pkg mode\njulia> ]\n\npkg> add https://github.com/hildebrandmw/Mapper2.jl\n\npkg> add https://github.com/hildebrandmw/AsapMapper.jl"
},

{
    "location": "#Step-2-General-Julia-Workflow-Advice-1",
    "page": "Home",
    "title": "Step 2 - General Julia Workflow Advice",
    "category": "section",
    "text": "I generally work with the Julia REPL (Read-Eval-Print Loop) open on one screen, and my code open on another. Using the package Revise really  helps with this workflow as itwill automatically reload code that you\'ve edited in the same working session, allowing you to immediately reevaluate your changes (which is totally baller). Revise can be installed from Julia\'s package manager usingpkg> add ReviseConsult the documentation for how to make Revise launch be default whenever Julia is started."
},

{
    "location": "tutorial/#",
    "page": "Tutorial",
    "title": "Tutorial",
    "category": "page",
    "text": ""
},

{
    "location": "tutorial/#Tutorial-1",
    "page": "Tutorial",
    "title": "Tutorial",
    "category": "section",
    "text": ""
},

{
    "location": "tutorial/#Maps,-Placement-and-Routing-from-the-Project-Manager-1",
    "page": "Tutorial",
    "title": "Maps, Placement and Routing from the Project Manager",
    "category": "section",
    "text": "The main interface to AsapMapper is through the Project Manager Interface (PM_Interface/). This takes a JSON file from the Project Manager and builds an architecture and taskgraph from this file. An example of this file is taskgraph/project_manager.json. The following sequence of commands shows how to use this file for a standard mapping.julia> using AsapMapper\n\n# Make a PM constructor, containing the path to the JSON file to parse\njulia> constructor = PMConstructor(\"taskgraphs/project_manager.json\")\n\n# Build a `Map` object from the constructor. This will automatically choose the architecture\n# to use, and construct the taskgraph from the JSON file\n#\n# The warnings given by AsapMapper are okay to ignore\njulia> M = build_map(constructor);\n\n# Run placement - note the the first time any function is run in Julia, it may take a little\n# while since the function must be compiled. The second time will usually be much snappier.\njulia> place!(M);\n\n# Run routing. The Routing Summary info is a series of checks that runs to make sure that\n# the Architecture and Taskgraph representations did not change in unexpected ways during\n# the mapping process. If one of the checks fails, then the Mapper thinks something is wrong.\n#\n# Usually, a failure occurs when the Mapper cannot find a valid routing and the result is\n# congested.\njulia> route!(M);\n[ Info: Running Pathfinder Routing Algorithm\n┌ Info: Routing Summary\n│ ---------------\n│ Placement Check:    passed\n│ Congestion Check:   passed\n│ Port Check:         passed\n│ Graph Connectivity: passed\n│ Architecture Check: passed\n└ Resource Check:     passed\n\n# Report stats from the mapping. The returned object `histogram` is a dictionary containing\n# the count of links of different lengths.\n#\n# Keys are the length of the link, and values are the number of links of that length\njulia> histogram = AsapMapper.report_routing_stats(M);\nNumber of communication channels: 178\nTotal global routing links used: 246\nAverage Link Length: 1.3820224719101124\nMaximum Link Distance: 5\nLink Histogram:\nDataStructures.SortedDict{Int64,Int64,Base.Order.ForwardOrdering} with 5 entries:\n  1 => 131\n  2 => 31\n  3 => 13\n  4 => 1\n  5 => 2\n\n# Plotting\n# Make sure you have `Plots` installed\njulia> ]\n\npkg> add Plots\n\n# Import plots\njulia> using Plots\n\n# Plot the Map\njulia> plot(M)"
},

{
    "location": "tutorial/#Overwriting-Defaults-1",
    "page": "Tutorial",
    "title": "Overwriting Defaults",
    "category": "section",
    "text": "When performing architecture exploration, it\'s you generally want to use a different  architecture then that specified in the Project Manager file. This can be achieved by adding these parameters to the PMConstructor. A full list of valid parameters can be found by looking at the _get_default_options function in PM_Constructor/Main.jl. The main knob to turn is the architecture. Suppose we wanted to map an application to Asap3 with 4  inter-processer links instead of 2. That would be accomplished as follows:julia> using AsapMapper\n\n# We need to define a 0-argument function that will construct our desired architecture\njulia> f() = asap3(Rectangular(4, 1))\n\n# Create a named tuple for option overrides to the PMConstructor.\njulia> overrides = (architecture = f,)\n\n# Pass the overrides to the PMConstructor\njulia> constructor = PMConstructor(\"taskgraphs/project_manager.json\", overrides)\n\n# Now when we place, route, and plot - it will be for the asap3 architecture\njulia> M = build_map(constructor); place!(M); route!(M);\n\njulia> using Plots\n\njulia> plot(M)"
},

{
    "location": "tutorial/#Using-the-Simulator-for-Input-1",
    "page": "Tutorial",
    "title": "Using the Simulator for Input",
    "category": "section",
    "text": "Sometimes, it is easier to use the profile.json given by the Asap Simulator instead of  using the Project Manager generated files. Using the Simulator output is very similar to the Project Manager, but note that you must define the architecture constructor function.julia> using AsapMapper\n\njulia> f() = asap4(Rectangular(2,1))\n\njulia> constructor = SimConstructor(\"taskgraphs/profile.json\", (architecture = f,))\n\njulia> M = build_map(constructor); place!(M); route!(M)\n\njulia> using Plots; plot(M)"
},

{
    "location": "tutorial/#Changing-Placement-Parameters-1",
    "page": "Tutorial",
    "title": "Changing Placement Parameters",
    "category": "section",
    "text": "Generally, increasing the number of move attempts and initial temperature of the placement will yield a higher qualityh mapping at the cost of extra run time. The documentation for the placement algorithm is shown below:place!(map::Map; kwargs...) :: SAStateRun simulated annealing placement directly on map.Records the following metrics into map.metadata:placement_struct_time - Amount of time it took to build the    [SAStruct] from map.\nplacement_struct_bytes - Number of bytes allocated during the construction   of the [SAStruct]\nplacement_time - Running time of placement.\nplacement_bytes - Number of bytes allocated during placement.\nplacement_objective - Final objective value of placement."
},

{
    "location": "tutorial/#Keyword-Arguments-1",
    "page": "Tutorial",
    "title": "Keyword Arguments",
    "category": "section",
    "text": "seed - Seed to provide the random number generator. Specify this to a    constant value for consistent results from run to run.\nDefault: rand(UInt64)\nmove_attempts :: Integer - Number of successful moves to generate between   state updates. State updates include adjusting temperature, move distance   limit, state displaying etc.\nHigher numbers will generally yield higher quality placement but with a   longer running time.\nDefault: 20000\ninitial_temperature :: Float64 - Initial temperature that the system begins   its warming process at. Due to the warming procedure, this should not have   much of an affect on placement.\nDefault: 1.0.\nsupplied_state :: Union{SAState,Nothing} - State type to use for this    placement. Can be used to resume placement where it left off from a previous   run. If nothing, a new SAState object will be initialized.\nDefault: nothing\nmovegen :: MoveGenerator - The [MoveGenerator] to use for this    placement.\nDefault: [CachedMoveGenerator]\nwarmer - The [SAWarm] warming schedule to use.\nDefault: [DefaultSAWarm]\ncooler - The [SACool] cooling schedule to use.\nDefault: [DefaultSACool]\nlimiter - The [SALimit] move distance limiting algorithm to    use.\nDefault: [DefaultSALimit]\ndoner - The [SADone] exit condition to use.\nDefault: [DefaultSADone]To increase the number of move attempts (to say, 50000), call the place funtion like the command below:julia> using AsapMapper\n\njulia> M = build_map(PMConstructor(\"taskgraphs/project_manager.json\"));\njulia> place!(M; move_attempts = 50000);"
},

{
    "location": "tutorial/#Building-Architecturs-1",
    "page": "Tutorial",
    "title": "Building Architecturs",
    "category": "section",
    "text": "The CAD models in cad_models/ directory are the models that are guarenteed to work with  the Mapper framework. When defining custom models, it\'s best to use those as a starting  point since many of the inner functions (build_processor_tile, build_memory etc.) attach important metadata to the inner objects that the downstream Mapper2 is expecting.In general, though, the Mapper should do a pretty good job in figuring out what should be done with new models. If more functionality is needed, or something is breaking, let me know!"
},

]}
