# AsapMapper

This is the KiloCore specific code for the KilCore mapping project.

Items that go in here include:

* Architecture models for Asap3, Asap4, and Asap like architectures.
* Constructors for Taskgraph based on simulation results from the AsapSim.
* Asap specific plotting libraries.
* Start routines for launching the Mapper from the command line, allowing 
    integration of the Mapper with the Project Manager Framework.

## Installation

This package is not a registered Julia package. To install, run the command
```julia
Pkg.clone("https://github.com/hildebrandmw/AsapMapper.jl")
```

Make sure [Mapper2](https://github.com/hildebrandmw/Mapper2.jl) is installed
as well.

## Running from Commandline
To invoke the Mapper from the command line, just run the following:

```
julia /path/to/mapper.jl architecture input_file output_file
```
where
* `architecture` is the name of the architecture to be mapped. Right now, it
    can either be `asap3` or `asap4`.
* `input_file` is the path to the simulator generated `profile.json` file.
* `output_file` is the desired name and path to the output file.
