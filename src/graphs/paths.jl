# Import Graphs functions
using Graphs: inneighbors

"""
    find_backdoor_paths(g, X, Y)

Find all backdoor paths from X to Y.

A backdoor path is a path that starts with an edge pointing into X.

# Arguments
- `g`: Directed acyclic graph
- `X`: Source node
- `Y`: Target node

# Returns
- Vector of backdoor paths (each path is a vector of nodes)

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Backdoor path: X ← Z → Y
paths = find_backdoor_paths(g, 2, 3)  # [[1, 3]]
```
"""
function find_backdoor_paths(g::AbstractGraph, X::Int, Y::Int)
    # Validate node indices
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    backdoor_paths = Vector{Vector{Int}}()
    
    # Backdoor paths start from parents of X and go to Y
    # A backdoor path is: X ← ... → Y
    # So we find paths from parents of X to Y, then prepend X
    
    # Better approach: find paths from parents of X to Y
    # A backdoor path is X ← ... → Y, so we find paths from parents of X to Y
    parents_X = inneighbors(g, X)
    for parent in parents_X
        paths_from_parent = _all_simple_paths(g, parent, Y)
        for path in paths_from_parent
            # Prepend X to make it a backdoor path
            backdoor_path = [X, path...]
            push!(backdoor_paths, backdoor_path)
        end
    end
    
    return backdoor_paths
end

"""
    find_directed_paths(g, X, Y)

Find all directed paths from X to Y.

A directed path follows the direction of edges (no backward traversal).

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Int`: Source node
- `Y::Int`: Target node

# Returns
- `Vector{Vector{Int}}`: Vector of directed paths, where each path is a vector of nodes

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 2)  # X → Y
add_edge!(g, 1, 3)  # X → Z
add_edge!(g, 2, 4)  # Y → W
add_edge!(g, 3, 4)  # Z → W

paths = find_directed_paths(g, 1, 4)  # [[1, 2, 4], [1, 3, 4]]
```

# Notes
- In a DAG, all simple paths are directed (if they exist)
- Returns empty vector if no path exists
"""
function find_directed_paths(g::AbstractGraph, X::Int, Y::Int)
    # Validate node indices
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    # All simple paths in a DAG are directed (if they exist)
    # Use the helper from d_separation.jl (available after it's included)
    return _all_simple_paths(g, X, Y)
end

# _all_simple_paths is available from d_separation.jl (included before this file)

# Export functions
export find_backdoor_paths, find_directed_paths
