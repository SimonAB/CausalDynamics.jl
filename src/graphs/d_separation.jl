# Import Graphs functions
using Graphs: outneighbors

"""
    d_separated(g, X, Y, Z)

Check if nodes X and Y are d-separated by set Z in directed acyclic graph g.

# Arguments
- `g`: A directed acyclic graph (DiGraph)
- `X`: Source node or set of nodes
- `Y`: Target node or set of nodes
- `Z`: Conditioning set (set of nodes to condition on)

# Returns
- `true` if X and Y are d-separated by Z, `false` otherwise

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # X → Y
add_edge!(g, 3, 1)  # Z → X
add_edge!(g, 3, 2)  # Z → Y

# X and Y are d-separated by Z (Z blocks the path)
d_separated(g, 1, 2, [3])  # true

# X and Y are not d-separated without conditioning
d_separated(g, 1, 2, [])  # false
```

# References
- Pearl, J. (2009). *Causality*, Chapter 1
"""
function d_separated(g::AbstractGraph, X, Y, Z)
    # Normalise inputs to sets
    X_set = X isa AbstractVector ? Set(X) : Set([X])
    Y_set = Y isa AbstractVector ? Set(Y) : Set([Y])
    Z_set = Z isa AbstractVector ? Set(Z) : Set([Z])
    
    # Find all paths between X and Y
    paths = _find_all_paths(g, X_set, Y_set)
    
    # Check if any path is unblocked by Z
    for path in paths
        if !_is_path_blocked(g, path, Z_set)
            return false  # Found unblocked path
        end
    end
    
    return true  # All paths blocked
end

# Internal helper functions (not exported)
"""
    _is_path_blocked(g, path, Z)

Check if a path is blocked by conditioning set Z.

A path is blocked if:
1. It contains a collider that is not in Z and has no descendants in Z
2. It contains a non-collider that is in Z

# Arguments
- `g`: Directed acyclic graph
- `path`: Vector of nodes representing a path
- `Z`: Conditioning set

# Returns
- `true` if path is blocked, `false` otherwise
"""
function _is_path_blocked(g::AbstractGraph, path::AbstractVector, Z::Set)
    if length(path) < 2
        return true  # Trivial path
    end
    
    # Check each triple (i-1, i, i+1) for colliders
    for i in 2:(length(path)-1)
        node_i = path[i]
        node_prev = path[i-1]
        node_next = path[i+1]
        
        # Check if node_i is a collider (has incoming edges from both directions)
        is_collider = Graphs.has_edge(g, node_prev, node_i) && Graphs.has_edge(g, node_next, node_i)
        
        if is_collider
            # Collider: path is blocked unless node_i or its descendants are in Z
            if node_i ∉ Z && !_has_descendant_in_set(g, node_i, Z)
                return true  # Path blocked by collider
            end
        else
            # Non-collider: path is blocked if node_i is in Z
            if node_i ∈ Z
                return true  # Path blocked by conditioning
            end
        end
    end
    
    return false  # Path is unblocked
end

"""
    _has_descendant_in_set(g, node, Z)

Check if node has any descendants in set Z.

Used in d-separation to determine if a collider is "activated" (has a descendant
in the conditioning set Z).

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `node::Int`: Source node to check descendants of
- `Z::Set{Int}`: Set of nodes to check for intersection

# Returns
- `Bool`: `true` if any descendant of node is in Z, `false` otherwise

# Notes
- Internal helper function (not exported)
- Used by `_is_path_blocked` to check collider activation
- A collider is activated (path unblocked) if it or any descendant is in Z
"""
function _has_descendant_in_set(g::AbstractGraph, node, Z::Set)
    # Import get_descendants (available after sets.jl is included)
    # Since sets.jl is included before d_separation.jl, this should work
    descendants = get_descendants(g, node)
    return !isempty(intersect(descendants, Z))
end

"""
    _find_all_paths(g, X, Y)

Find all paths from any node in X to any node in Y.

Used by d-separation to find all paths between sets of nodes. Paths can traverse
edges in either direction (for d-separation, we need undirected paths).

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Set{Int}`: Set of source nodes
- `Y::Set{Int}`: Set of target nodes

# Returns
- `Vector{Vector{Int}}`: Vector of all paths, where each path is a vector of nodes

# Notes
- Internal helper function (not exported)
- Used by `d_separated` to find all paths between node sets
- Skips self-loops (paths from a node to itself)
- Uses `_all_simple_paths` to find paths between individual nodes
"""
function _find_all_paths(g::AbstractGraph, X::Set, Y::Set)
    paths = Vector{Vector{Int}}()
    
    for x in X
        for y in Y
            if x == y
                continue  # Skip self-loops
            end
            # Find all simple paths from x to y
            path_list = _all_simple_paths(g, x, y)
            append!(paths, path_list)
        end
    end
    
    return paths
end

"""
    _all_simple_paths(g, source, target)

Find all simple paths from source to target in the underlying undirected graph.

Used for d-separation, where paths can traverse edges in either direction.
A simple path visits each node at most once.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `source::Int`: Source node
- `target::Int`: Target node

# Returns
- `Vector{Vector{Int}}`: Vector of all simple paths (each path is a vector of nodes)

# Notes
- Internal helper function (not exported)
- Finds paths in underlying undirected graph (edges can be traversed in either direction)
- Uses depth-first search (DFS) to enumerate all paths
- Used by d-separation and path-finding functions
"""
function _all_simple_paths(g::AbstractGraph, source, target)
    # Use DFS to find all paths in the underlying undirected graph
    paths = Vector{Vector{Int}}()
    current_path = Int[]
    visited = Set{Int}()
    
    function dfs(node)
        push!(current_path, node)
        
        if node == target
            push!(paths, copy(current_path))
            pop!(current_path)
            return
        end
        
        push!(visited, node)
        
        # Check neighbors in both directions (for d-separation, we need undirected paths)
        # Out-neighbors (forward edges)
        for neighbor in outneighbors(g, node)
            if neighbor ∉ visited
                dfs(neighbor)
            end
        end
        
        # In-neighbors (backward edges) - needed for d-separation
        for neighbor in Graphs.inneighbors(g, node)
            if neighbor ∉ visited
                dfs(neighbor)
            end
        end
        
        pop!(current_path)
        delete!(visited, node)
    end
    
    dfs(source)
    return paths
end

# Export public API
export d_separated
