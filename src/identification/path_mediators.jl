"""
    find_path_mediators(g, treatment, outcome) -> Set{Int}

Structural mediator candidates between `treatment` and `outcome`: nodes that lie
on at least one **proper** directed path `treatment → ⋯ → outcome`
(excluding the endpoints).

On a DAG this is

```julia
intersect(get_descendants(g, treatment), get_ancestors(g, outcome))
```

This is **not** the frontdoor criterion. For single-node sets that satisfy the
frontdoor criterion, use [`find_frontdoor_mediators`](@ref).

# Arguments
- `g`: Directed acyclic graph
- `treatment`: Treatment node index
- `outcome`: Outcome node index

# Returns
- `Set{Int}` of mediator candidate indices

# Examples

```julia
using CausalDynamics, Graphs

# Nodes: A=1, M1=2, M2=3, M3=4, Y=5, C=6, D=7
# A → M1 → M2 → Y; A → M3 → Y; C → A; C → Y; A → D
g = DiGraph(7)
add_edge!(g, 1, 2); add_edge!(g, 2, 3); add_edge!(g, 3, 5)
add_edge!(g, 1, 4); add_edge!(g, 4, 5)
add_edge!(g, 6, 1); add_edge!(g, 6, 5)
add_edge!(g, 1, 7)

find_path_mediators(g, 1, 5)  # Set([2, 3, 4]) == {M1, M2, M3}
```
"""
function find_path_mediators(g::AbstractGraph, treatment::Int, outcome::Int)
    validate_causal_graph(g)

    n = nv(g)
    if treatment < 1 || treatment > n || outcome < 1 || outcome > n
        throw(ArgumentError(
            "Node indices treatment=$treatment and outcome=$outcome must be in range [1, $n].",
        ))
    end

    # Equivalent to nodes_on_directed_paths without endpoints.
    return intersect(get_descendants(g, treatment), get_ancestors(g, outcome))
end

"""
    find_path_mediators(g, treatment, outcome; node_names) -> Set

As [`find_path_mediators`](@ref) with `Int` indices, but `treatment` / `outcome`
may be `Symbol`s when `node_names` maps indices to names (same conventions as
[`identify`](@ref)).

Returns a `Set{Symbol}` when `node_names` is provided, otherwise `Set{Int}`.
"""
function find_path_mediators(
    g::AbstractGraph,
    treatment,
    outcome;
    node_names = nothing,
)
    names = _normalize_node_names(node_names, nv(g))
    t = treatment isa Int ?
        _node_index(g, treatment) :
        _node_index(g, treatment, names)
    y = outcome isa Int ?
        _node_index(g, outcome) :
        _node_index(g, outcome, names)
    idx = find_path_mediators(g, t, y)
    names === nothing && return idx
    return Set(names[i] for i in idx if haskey(names, i))
end

export find_path_mediators
