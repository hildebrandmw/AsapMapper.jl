# AsapMapper

This is the Asap specific repo for mapping application to KiloCore like architectures.

## Installation


### Step 0 - Install Julia

If you do not yet have Julia installed, you can download it from 
<https://julialang.org/downloads/>. If you are running on a Linux/OSX system, you may also
want to alias the `julia` command to the installation location with the command below. 
(Note: you can put this line in your `.bashrc` or `.profile` file to make it persistent.)
```
alias julia=<path-to-julia-1.1.0/bin/julia>
```

### Step 1 - Install Mapper Source Files

#### Installation for Development

If you plan on modifying the Mapper, first download the source code using git:
```
git clone https://github.com/hildebrandmw/Mapper2.jl Mapper2
git clone https://github.com/hildebrandmw/AsapMapper.jl AsapMapper
```
You have to register these packages with Julia so it can find them. To do this, open Julia
and navigate to the directory where the Mapper repos were downloaded. Inside Julia, run the
following commands
```julia
# Enter Pkg mode
julia> ]

pkg> dev ./Mapper2

pkg> dev ./AsapMapper
```
After performing this step, Julia knows how to find the Mapper package, and they can be
imported into a Julia module or into the REPL using
```
julia> using Mapper2

julia> using AsapMapper
```

#### Installation for Just Usage

If you don't plan on developing the Mapper, and just want it installed and discoverable, you
can download them directly through Julia's built in package manager using
```julia
# Enger Pkg mode
julia> ]

pkg> add https://github.com/hildebrandmw/Mapper2.jl

pkg> add https://github.com/hildebrandmw/AsapMapper.jl
```

### Step 2 - General Julia Workflow Advice

I generally work with the Julia REPL (Read-Eval-Print Loop) open on one screen, and my code
open on another. Using the package [Revise](https://github.com/timholy/Revise.jl) really 
helps with this workflow as itwill automatically reload code that you've edited in the
same working session, allowing you to immediately reevaluate your changes (which is totally
baller). Revise can be installed from Julia's package manager using
```
pkg> add Revise
```
Consult the [documentation](https://timholy.github.io/Revise.jl/stable/config/) for how
to make Revise launch be default whenever Julia is started.


