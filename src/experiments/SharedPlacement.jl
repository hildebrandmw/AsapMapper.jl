"""
    SharedPlacement <: Experiment

The goal of this experiment is to test how different routing configurations
affect the final number of global links needed for routing.

This experiment accelerates gathering data on different routing styles if
placement semantices are not changed for different architecture arguments.

# Fields
* `arch::Function` - Constructor for the architecture (`<: TopLevel`) used for
    this experiment.
* `arch_args::Vector` - A vector of arguments to be passed to the `arch` 
    constuctor. Generally, the argument tuples in this field should not change
    the placement semantics of the architecture. Only the availability of
    routing resources. This is provided as a speed optimization where multiple
    different routing styles can share a single placement.
* `place::FunctionCall` - Call to placement function. 
* `route::FunctionCall` - Call to routing function.
"""
struct SharedPlacement <: Experiment
    arch        ::Function
    arch_args   ::Vector
    place       ::FunctionCall
    route       ::FunctionCall
end
