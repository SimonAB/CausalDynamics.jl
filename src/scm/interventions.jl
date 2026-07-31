"""
    DoIntervention

Represents a `do(·)` intervention on a single variable, fixing it to a definite value
(the mechanism is imposed, not merely observed).

For static [`GraphSCM`](@ref) this replaces the structural assignment. For continuous
CDMs it is accepted as a hard pin (prefer [`DoPin`](@ref) / [`do_pin`](@ref)).

# Fields
- `variable::Union{Int, Symbol}`: Variable to intervene on (node index or symbol)
- `value::Any`: Value to set the variable to

# Notes
- For `GraphSCM`, use integer node indices; symbol resolution is reserved for future
  `SymbolicSCM` / `CausalGraph` name maps.
"""
struct DoIntervention <: AbstractCausalIntervention
    variable::Union{Int, Symbol}
    value::Any
end

"""
    do_intervention(variable, value)

Convenience function to create a `DoIntervention` object.

# Arguments
- `variable::Union{Int, Symbol}`: Variable to intervene on
- `value::Any`: Value to set the variable to

# Returns
- `DoIntervention`: Intervention object representing `do(variable = value)`

# Examples

```julia
using CausalDynamics

# Intervene on variable :x, setting it to 1.0
intervention = do_intervention(:x, 1.0)

# Intervene on node 2, setting it to 0
intervention2 = do_intervention(2, 0)
```

# See Also
- `DoIntervention`: Type representing interventions
- `apply_intervention`: Apply intervention to an SCM
"""
function do_intervention(variable, value)
    return DoIntervention(variable, value)
end

"""
    apply_intervention(scm::GraphSCM, intervention::DoIntervention)

Apply a `do(·)` intervention to a GraphSCM, returning a new SCM.

An intervention `do(X = x)` replaces the structural equation for variable X
with a constant assignment `X := x`, removing its dependence on parents
(modularity principle). All other equations remain unchanged.

# Arguments
- `scm::GraphSCM`: Structural Causal Model
- `intervention::DoIntervention`: Intervention to apply

# Returns
- `GraphSCM`: New SCM with the intervention applied (mutilated model)

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 2, 3)  # X → Y

equations = Dict{Int, Function}(
    1 => (args...) -> args[end],          # Z = U_Z
    2 => (z, u) -> z + u,                 # X = Z + U_X
    3 => (x, u) -> 2x + u                 # Y = 2X + U_Y
)

scm = GraphSCM(g, equations, Set([1]))

# Intervene: do(X = 5)
intervention = do_intervention(2, 5.0)
scm_do = apply_intervention(scm, intervention)

# In scm_do, node 2's equation is replaced with constant 5.0,
# and the edge Z → X is removed.
```

# Notes
- **Modularity principle**: Only the intervened variable's equation is changed
- Incoming edges to the intervened node are removed (parents no longer prehend into it)
- The intervened variable's equation becomes `(args...) -> value`

# References
- Pearl, J. (2009). *Causality*, Chapter 1.3 and Chapter 3.2
"""
function apply_intervention(scm::GraphSCM, intervention::DoIntervention)
    var = intervention.variable
    val = intervention.value

    # Resolve variable to node index
    node = if var isa Int
        var
    else
        throw(ArgumentError(
            "Symbol-based variable resolution not yet supported for GraphSCM. Use integer node indices."
        ))
    end

    if node < 1 || node > nv(scm.graph)
        throw(ArgumentError("Intervention node $node is out of range [1, $(nv(scm.graph))]."))
    end

    # Create mutilated graph: remove all incoming edges to the intervened node
    new_graph = copy(scm.graph)
    parents_to_remove = collect(Graphs.inneighbors(new_graph, node))
    for parent in parents_to_remove
        Graphs.rem_edge!(new_graph, parent, node)
    end

    # Create new equations: replace the intervened variable's equation with a constant
    new_equations = copy(scm.equations)
    new_equations[node] = (args...) -> val

    return GraphSCM(new_graph, new_equations, scm.exogenous)
end

"""
    apply_intervention(scm::GraphSCM, interventions::Vector{DoIntervention})

Apply multiple simultaneous interventions to a GraphSCM.

# Arguments
- `scm::GraphSCM`: Structural Causal Model
- `interventions::Vector{DoIntervention}`: Vector of interventions to apply

# Returns
- `GraphSCM`: New SCM with all interventions applied
"""
function apply_intervention(scm::GraphSCM, interventions::Vector{DoIntervention})
    result = scm
    for intervention in interventions
        result = apply_intervention(result, intervention)
    end
    return result
end

"""
    simulate_scm(scm::GraphSCM, exogenous_values::Dict{Int, <:Any})

Simulate an SCM forward given exogenous noise values, producing endogenous
variable values in topological order.

# Arguments
- `scm::GraphSCM`: Structural Causal Model
- `exogenous_values::Dict{Int, <:Any}`: Dictionary mapping node indices to exogenous noise values

# Returns
- `Dict{Int, Any}`: Dictionary mapping each node to its computed value

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # X → Y
add_edge!(g, 2, 3)  # Y → Z

equations = Dict{Int, Function}(
    1 => (u) -> u,
    2 => (x, u) -> x + u,
    3 => (y, u) -> 2y + u
)

scm = GraphSCM(g, equations, Set{Int}())

# Simulate with exogenous values
U = Dict(1 => 1.0, 2 => 0.5, 3 => -0.3)
values = simulate_scm(scm, U)
# values[1] = 1.0, values[2] = 1.5, values[3] = 2.7
```

# Notes
- Computes values in topological order so parent values are available
- Each equation receives parent values followed by the exogenous value
- `exogenous_values` fixes exogenous noise `U` for this unit (creative advance held constant)
- Returned endogenous values are the settled outcomes each node contributes to its descendants
"""
function simulate_scm(scm::GraphSCM, exogenous_values::Dict{Int, T}) where T
    g = scm.graph
    n = nv(g)

    # Topological sort for evaluation order
    topo_order = Graphs.topological_sort(g)

    values = Dict{Int, Any}()

    for node in topo_order
        parents = sort(collect(Graphs.inneighbors(g, node)))
        parent_vals = [values[p] for p in parents]
        u = get(exogenous_values, node, 0.0)

        if haskey(scm.equations, node)
            eq = scm.equations[node]
            # Call equation with parent values followed by exogenous value
            args = vcat(parent_vals, [u])
            values[node] = eq(args...)
        else
            # No equation defined — use exogenous value directly
            values[node] = u
        end
    end

    return values
end

export DoIntervention, apply_intervention, do_intervention, simulate_scm
