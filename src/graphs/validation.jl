"""
    is_dag(g)

Check if graph g is a directed acyclic graph (DAG).

A DAG is a directed graph with no cycles (no path from a node back to itself).

# Arguments
- `g::AbstractGraph`: Directed graph to test

# Returns
- `Bool`: `true` if g is a DAG, `false` otherwise

# Examples

```julia
using CausalDynamics, Graphs

# Valid DAG
g1 = DiGraph(3)
add_edge!(g1, 1, 2)
add_edge!(g1, 2, 3)
is_dag(g1)  # true

# Contains cycle
g2 = DiGraph(3)
add_edge!(g2, 1, 2)
add_edge!(g2, 2, 3)
add_edge!(g2, 3, 1)  # Cycle: 1 → 2 → 3 → 1
is_dag(g2)  # false
```

# Notes
- Uses topological sort to detect cycles
- Returns `false` if topological sort fails (indicates cycle)
- Causal graphs must be DAGs (no causal loops)

# See Also
- `validate_causal_graph`: Validate and throw error if not DAG
"""
function is_dag(g::AbstractGraph)
    # Use topological sort - if it succeeds, graph is acyclic
    try
        Graphs.topological_sort_by_dfs(g)
        return true
    catch
        return false
    end
end

"""
    validate_causal_graph(g)

Validate that graph g is a valid causal graph (DAG).

Causal graphs must be directed acyclic graphs (DAGs) to represent well-defined
causal relationships without circular dependencies.

# Arguments
- `g::AbstractGraph`: Directed graph to validate

# Returns
- `Bool`: `true` if valid (always returns true, throws on error)

# Throws
- `ArgumentError`: If graph is not a DAG (contains cycles)

# Examples

```julia
using CausalDynamics, Graphs

# Valid DAG
g1 = DiGraph(3)
add_edge!(g1, 1, 2)
add_edge!(g1, 2, 3)
validate_causal_graph(g1)  # true

# Invalid: contains cycle
g2 = DiGraph(3)
add_edge!(g2, 1, 2)
add_edge!(g2, 2, 3)
add_edge!(g2, 3, 1)
validate_causal_graph(g2)  # throws ArgumentError
```

# Notes
- Used internally by identification functions to ensure graph validity
- Causal models require DAGs to avoid circular causal dependencies
- Throws error rather than returning false for clearer error messages

# See Also
- `is_dag`: Check if graph is DAG (returns boolean)
"""
function validate_causal_graph(g::AbstractGraph)
    if !is_dag(g)
        throw(ArgumentError("Graph must be a directed acyclic graph (DAG)"))
    end
    return true
end

"""
    check_node_indices!(g, idxs...; names=("X", "Y"))

Throw `ArgumentError` unless every index lies in `1:nv(g)`.
`names` labels the indices in the error message (cycled if shorter than `idxs`).
"""
function check_node_indices!(
    g::AbstractGraph,
    idxs::Integer...;
    names::Tuple = ("X", "Y"),
)
    n = nv(g)
    bad = false
    for idx in idxs
        if idx < 1 || idx > n
            bad = true
            break
        end
    end
    bad || return nothing
    parts = String[]
    for (i, idx) in enumerate(idxs)
        lab = names[mod1(i, length(names))]
        push!(parts, "$lab=$idx")
    end
    throw(ArgumentError(
        "Node indices $(join(parts, ", ")) must be in range [1, $n]. Graph has $n nodes.",
    ))
end

"""
    check_node_index!(g, idx; label="node")

Throw if a single node index is out of range.
"""
function check_node_index!(g::AbstractGraph, idx::Integer; label::AbstractString = "node")
    n = nv(g)
    if idx < 1 || idx > n
        throw(ArgumentError("$(label) index $idx out of range [1, $n]"))
    end
    return nothing
end

export is_dag, validate_causal_graph
