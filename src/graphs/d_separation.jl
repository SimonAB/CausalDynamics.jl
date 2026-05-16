# Import Graphs functions
using Graphs: outneighbors

"""
    d_separated(g, X, Y, Z)

Check if nodes `X` and `Y` are d-separated by set `Z` in directed acyclic graph `g`
(associative dependence blocked given `Z`; Pearl Level 1).

Uses the Bayes-Ball algorithm (Shachter 1998) for O(V+E) complexity,
rather than path enumeration which is exponential in graph size.

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

# Algorithm

The Bayes-Ball algorithm determines reachability in a DAG respecting
d-separation rules. Starting from source nodes X, it propagates "balls"
through the graph. A ball can travel:

- Through a non-collider (chain or fork) if the node is NOT in Z
- Through a collider if the node or any descendant IS in Z

If any ball reaches a node in Y, then X and Y are NOT d-separated by Z.

# References
- Shachter, R. D. (1998). "Bayes-Ball: The Rational Pastime"
- Pearl, J. (2009). *Causality*, Chapter 1
- Koller, D. & Friedman, N. (2009). *Probabilistic Graphical Models*, Section 3.3
"""
function d_separated(g::AbstractGraph, X, Y, Z)
    # Normalise inputs to sets
    X_set = X isa AbstractVector ? Set(X) : (X isa Set ? X : Set([X]))
    Y_set = Y isa AbstractVector ? Set(Y) : (Y isa Set ? Y : Set([Y]))
    Z_set = Z isa AbstractVector ? Set(Z) : (Z isa Set ? Z : Set([Z]))

    # Handle trivial cases
    if !isempty(intersect(X_set, Y_set))
        return true  # A node is trivially d-separated from itself
    end

    # Use Bayes-Ball algorithm for O(V+E) d-separation
    reachable = _bayes_ball_reachable(g, X_set, Z_set)
    return isempty(intersect(reachable, Y_set))
end

"""
    _bayes_ball_reachable(g, X, Z)

Compute the set of nodes reachable from X given conditioning set Z,
using the Bayes-Ball algorithm (Shachter 1998).

The algorithm tracks two types of visits to each node:
- Visit "from child" (ball came via a child edge, i.e. travelling against edge direction)
- Visit "from parent" (ball came via a parent edge, i.e. travelling along edge direction)

The propagation rules are:

1. Ball arrives at node via parent (travelling along edge direction):
   - If node is NOT in Z: pass to children (continue forward)
   - If node IS in Z: blocked (do not pass)
   - Always: pass to parents if node is in Z (explaining away)

2. Ball arrives at node via child (travelling against edge direction):
   - If node is NOT in Z: pass to parents (continue backward)
   - If node IS in Z: blocked (do not pass to parents)

Additionally, for collider activation we must pre-compute which nodes
in Z have ancestors that are also relevant. The standard Bayes-Ball
handles this via the two-visit-type mechanism.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Set{Int}`: Source nodes
- `Z::Set{Int}`: Conditioning set

# Returns
- `Set{Int}`: Set of nodes reachable from X (not blocked by Z)

# References
- Shachter, R. D. (1998). "Bayes-Ball: The Rational Pastime"
"""
function _bayes_ball_reachable(g::AbstractGraph, X::Set, Z::Set)
    n = nv(g)
    if n == 0
        return Set{Int}()
    end

    # BFS from X using d-separation propagation rules.
    #
    # We track two visit types per node:
    #   visited_top[v]    = visited from parent direction (ball travels with edge)
    #   visited_bottom[v] = visited from child direction (ball travels against edge)
    #
    # Propagation rules (following Koller & Friedman, Algorithm 3.1):
    #
    #   Ball at node via PARENT ("top visit"):
    #     If node NOT in Z → send to children (top visit)
    #     If node IN Z     → do nothing (blocked at conditioned non-collider)
    #
    #   Ball at node via CHILD ("bottom visit"):
    #     If node NOT in Z → send to children (top visit) AND parents (bottom visit)
    #     If node IN Z (or is ancestor of Z) → send to parents (bottom visit) only
    #       (explaining away: conditioning on collider or its descendant)

    visited_top = falses(n)
    visited_bottom = falses(n)

    reachable = Set{Int}()

    # Queue entries: (node, from_top::Bool)
    # from_top = true  → ball arrived from a parent (top visit)
    # from_top = false → ball arrived from a child (bottom visit)
    queue = Tuple{Int, Bool}[]

    # Initialise: from source nodes, schedule BOTH directions.
    # This ensures we can reach nodes both forward (children) and backward (parents).
    for x in X
        if x >= 1 && x <= n
            if !visited_top[x]
                visited_top[x] = true
                push!(queue, (x, true))
            end
            if !visited_bottom[x]
                visited_bottom[x] = true
                push!(queue, (x, false))
            end
        end
    end

    while !isempty(queue)
        node, from_top = popfirst!(queue)

        push!(reachable, node)

        if from_top && node ∉ Z
            # Top visit (from parent), node NOT conditioned on:
            # Continue forward through non-collider → send to children (top)
            for child in Graphs.outneighbors(g, node)
                if !visited_top[child]
                    visited_top[child] = true
                    push!(queue, (child, true))
                end
            end

        elseif from_top && node ∈ Z
            # Top visit (from parent), node IS conditioned on:
            # Explaining away — send to parents (bottom visit)
            # This enables collider activation: A → B ← C with B ∈ Z
            # opens the path from A to C via B's other parents.
            for parent in Graphs.inneighbors(g, node)
                if !visited_bottom[parent]
                    visited_bottom[parent] = true
                    push!(queue, (parent, false))
                end
            end

        elseif !from_top && node ∉ Z
            # Bottom visit (from child), node NOT conditioned on:
            # Unobserved non-collider: pass to parents (bottom) AND children (top)
            for parent in Graphs.inneighbors(g, node)
                if !visited_bottom[parent]
                    visited_bottom[parent] = true
                    push!(queue, (parent, false))
                end
            end
            for child in Graphs.outneighbors(g, node)
                if !visited_top[child]
                    visited_top[child] = true
                    push!(queue, (child, true))
                end
            end

        elseif !from_top && node ∈ Z
            # Bottom visit (from child), node IS conditioned on:
            # Blocked — do not propagate in any direction
        end
    end

    return reachable
end

"""
    _ancestors_of_set(g, Z)

Compute the set of all ancestors of nodes in Z (including Z itself).

Used by Bayes-Ball to determine collider activation: a collider is
activated if it or any of its descendants is in Z, which is equivalent
to the collider being an ancestor of some node in Z.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `Z::Set{Int}`: Set of nodes

# Returns
- `Set{Int}`: All ancestors of Z (including Z itself)
"""
function _ancestors_of_set(g::AbstractGraph, Z::Set)
    ancestors = Set{Int}()
    queue = collect(Z)
    union!(ancestors, Z)

    while !isempty(queue)
        node = popfirst!(queue)
        for parent in Graphs.inneighbors(g, node)
            if parent ∉ ancestors
                push!(ancestors, parent)
                push!(queue, parent)
            end
        end
    end

    return ancestors
end


# ============================================================================
# Legacy internal helpers (retained for backward compatibility with paths.jl,
# backdoor.jl, and frontdoor.jl which use path enumeration)
# ============================================================================

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

# Notes
- Legacy helper retained for use by `find_backdoor_paths` and frontdoor criterion.
- The main `d_separated` function uses Bayes-Ball instead.
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
    descendants = get_descendants(g, node)
    return !isempty(intersect(descendants, Z))
end

"""
    _find_all_paths(g, X, Y)

Find all paths from any node in X to any node in Y in the underlying
undirected graph. Used for legacy path-based checking.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Set{Int}`: Set of source nodes
- `Y::Set{Int}`: Set of target nodes

# Returns
- `Vector{Vector{Int}}`: Vector of all paths, where each path is a vector of nodes

# Notes
- Internal helper function (not exported)
- Traverses edges in both directions (undirected paths for d-separation)
"""
function _find_all_paths(g::AbstractGraph, X::Set, Y::Set)
    paths = Vector{Vector{Int}}()

    for x in X
        for y in Y
            if x == y
                continue  # Skip self-loops
            end
            path_list = _all_simple_paths(g, x, y)
            append!(paths, path_list)
        end
    end

    return paths
end

"""
    _all_simple_paths(g, source, target; directed=false)

Find all simple paths from source to target.

When `directed=false` (default), traverses edges in both directions
(undirected paths, used for backdoor path finding).
When `directed=true`, only follows edge direction (used for directed path finding).

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `source::Int`: Source node
- `target::Int`: Target node
- `directed::Bool`: If true, only follow forward edges (default: false)

# Returns
- `Vector{Vector{Int}}`: Vector of all simple paths (each path is a vector of nodes)
"""
function _all_simple_paths(g::AbstractGraph, source, target; directed::Bool=false)
    # Use DFS to find all paths
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

        # Out-neighbours (forward edges) — always traversed
        for neighbor in outneighbors(g, node)
            if neighbor ∉ visited
                dfs(neighbor)
            end
        end

        # In-neighbours (backward edges) — only when undirected
        if !directed
            for neighbor in Graphs.inneighbors(g, node)
                if neighbor ∉ visited
                    dfs(neighbor)
                end
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
