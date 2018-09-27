# AsapMapper

[![Build Status](https://travis-ci.org/hildebrandmw/AsapMapper.jl.svg?branch=master)](https://travis-ci.org/hildebrandmw/AsapMapper.jl)
[![codecov.io](https://codecov.io/gh/hildebrandmw/AsapMapper.jl/graphs/badge.svg?branch=master)](https://codecov.io/gh/hildebrandmw/AsapMapper.jl)
[![Project Status: WIP – Initial development is in progress, but there has not yet been a stable, usable release suitable for the public.](https://www.repostatus.org/badges/latest/wip.svg)](https://www.repostatus.org/#wip)

This is the KiloCore specific code for the KilCore mapping project.

Items that go in here include:

* Architecture models for Asap3, Asap4, and Asap like architectures.
* Constructors for Taskgraph based on generated JSON files from the Project Manager
* Asap specific plotting recipes.

## Installation

This package is not a registered Julia package. To install, run the command
```julia
Pkg.clone("https://github.com/hildebrandmw/AsapMapper.jl")
```

Make sure [Mapper2](https://github.com/hildebrandmw/Mapper2.jl) is installed
as well.
