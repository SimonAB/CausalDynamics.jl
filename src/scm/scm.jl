"""
    AbstractSCM

Abstract type for Structural Causal Models (SCMs).

An SCM consists of:

- A causal graph (DAG)
- Structural equations: each variable from its parents and exogenous noise
- Exogenous variables (`U`): unmodelled unit-level factors

# Subtypes
- `GraphSCM`: SCM with graph and function-based equations (supported)
- `SymbolicSCM`: **Experimental** placeholder for ModelingToolkit-backed equations

# References
- Pearl, J. (2009). *Causality*, Chapter 1
"""
abstract type AbstractSCM end

"""
    GraphSCM

A Structural Causal Model represented as a graph and structural equations.

Each variable `X` is defined by a function `X = f_X(Pa(X), U_X)`, where `Pa(X)` are
parents and `U_X` is exogenous noise.

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
- One `simulate_scm` call settles all endogenous values for a fixed realisation of `U`
"""
struct GraphSCM <: AbstractSCM
    graph::Graphs.DiGraph
    equations::Dict{Int, Function}
    exogenous::Set{Int}
end

"""
    SymbolicSCM

**Experimental.** Placeholder Structural Causal Model for future ModelingToolkit.jl
integration. Not part of the supported `identify` / `simulate_scm` path; use
`GraphSCM` for executable models. The `system` field is typed as `Any` until a
concrete MTK backend lands.

# Fields
- `graph::DiGraph`: Directed acyclic graph representing causal structure
- `system::Any`: Intended ModelingToolkit system (placeholder)
- `exogenous::Set{Symbol}`: Set of exogenous variable names (symbols)

# See Also
- `GraphSCM`: Function-based SCM (supported implementation)
"""
struct SymbolicSCM <: AbstractSCM
    graph::Graphs.DiGraph
    system::Any  # ModelingToolkit.AbstractSystem placeholder (Any until MTK integration)
    exogenous::Set{Symbol}
end

export AbstractSCM, GraphSCM, SymbolicSCM
