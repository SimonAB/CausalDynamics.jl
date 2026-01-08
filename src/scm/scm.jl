"""
    AbstractSCM

Abstract type for Structural Causal Models (SCMs).

An SCM consists of:
- A causal graph (DAG) representing causal structure
- Structural equations defining how each variable depends on its parents
- Exogenous variables (noise terms) representing unobserved causes

# Subtypes
- `GraphSCM`: SCM with graph and function-based equations
- `SymbolicSCM`: SCM with symbolic equations (using ModelingToolkit.jl)

# References
- Pearl, J. (2009). *Causality*, Chapter 1
"""
abstract type AbstractSCM end

"""
    GraphSCM

A Structural Causal Model represented as a graph and structural equations.

Each variable X is defined by a function: X = f_X(Pa(X), U_X), where Pa(X) are
parents of X and U_X is exogenous noise.

# Fields
- `graph::DiGraph`: Directed acyclic graph representing causal structure
- `equations::Dict{Int, Function}`: Dictionary mapping node indices to functions
  - Function signature: `(parents, exogenous) -> value`
- `exogenous::Set{Int}`: Set of nodes that are exogenous (have no parents)

# Examples

```julia
using CausalDynamics, Graphs

# Create graph: X → Y, with U_X and U_Y exogenous
g = DiGraph(4)
add_edge!(g, 1, 3)  # X → Y
# Nodes: 1=X, 2=U_X, 3=Y, 4=U_Y

equations = Dict(
    1 => (pa, ex) -> ex[2],  # X = U_X
    3 => (pa, ex) -> pa[1] + ex[4]  # Y = X + U_Y
)

scm = GraphSCM(g, equations, Set([2, 4]))
```

# Notes
- Functions should be deterministic given parents and exogenous noise
- Exogenous nodes must have no parents in the graph
"""
struct GraphSCM <: AbstractSCM
    graph::Graphs.DiGraph
    equations::Dict{Int, Function}
    exogenous::Set{Int}
end

"""
    SymbolicSCM

A Structural Causal Model with symbolic equations (using ModelingToolkit.jl).

Allows symbolic manipulation of structural equations for identification,
intervention, and counterfactual reasoning.

# Fields
- `graph::DiGraph`: Directed acyclic graph representing causal structure
- `system::ModelingToolkit.AbstractSystem`: ModelingToolkit system containing symbolic equations
- `exogenous::Set{Symbol}`: Set of exogenous variable names (symbols)

# Examples

```julia
using CausalDynamics, Graphs, ModelingToolkit, Symbolics

@variables x, y, u_x, u_y
@parameters α, β

g = DiGraph(2)
add_edge!(g, 1, 2)  # X → Y

# Create symbolic equations
# x = u_x
# y = α * x + u_y

# (Implementation details depend on ModelingToolkit integration)
scm = create_symbolic_scm(g, equations_dict)
```

# Notes
- Enables symbolic computation of interventional and counterfactual distributions
- Integration with ModelingToolkit.jl for equation manipulation
- Currently under development

# See Also
- `create_symbolic_scm`: Create a SymbolicSCM from graph and equations
- `GraphSCM`: Function-based SCM (alternative implementation)
"""
struct SymbolicSCM <: AbstractSCM
    graph::Graphs.DiGraph
    system::Any  # ModelingToolkit.AbstractSystem (using Any for now to avoid import issues)
    exogenous::Set{Symbol}
end

export AbstractSCM, GraphSCM, SymbolicSCM
