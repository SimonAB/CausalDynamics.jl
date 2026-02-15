"""
    backdoor_adjustment_set(g, X, Y)

Find a valid backdoor adjustment set for estimating the causal effect of X on Y.

The backdoor criterion states that a set Z is a valid adjustment set if:
1. Z blocks all backdoor paths from X to Y
2. Z does not contain any descendants of X

# Arguments
- `g`: Directed acyclic graph
- `X`: Treatment node
- `Y`: Outcome node

# Returns
- Set of nodes that form a valid backdoor adjustment set, or `nothing` if no valid set exists

# Examples

```julia
using CausalDynamics, Graphs

# Confounding example
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Z is a valid adjustment set
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1])
```

# References
- Pearl, J. (2009). *Causality*, Chapter 3
"""
function backdoor_adjustment_set(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)

    # Validate node indices
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end

    # Find all backdoor paths from X to Y
    backdoor_paths = find_backdoor_paths(g, X, Y)

    if isempty(backdoor_paths)
        # No backdoor paths — no adjustment needed
        return Set{Int}()
    end

    # Get descendants of X (cannot be in adjustment set)
    descendants_X = get_descendants(g, X)

    # Quick heuristic: try parents of X minus descendants of X
    parents_X = get_parents(g, X)
    candidate = setdiff(parents_X, descendants_X)

    if _blocks_all_backdoor_paths(g, candidate, backdoor_paths)
        return candidate
    end

    # If parents alone don't suffice, search over candidate nodes.
    # Candidate nodes: all nodes except X, Y, and descendants of X.
    all_nodes = Set(Graphs.vertices(g))
    invalid_nodes = union(Set([X, Y]), descendants_X)
    candidate_nodes = collect(setdiff(all_nodes, invalid_nodes))
    sort!(candidate_nodes)

    # Search subsets by increasing size for a minimal valid set
    for size in 1:min(length(candidate_nodes), 5)
        for combo in _combinations(candidate_nodes, size)
            z = Set(combo)
            if _blocks_all_backdoor_paths(g, z, backdoor_paths)
                return z
            end
        end
    end

    # No valid adjustment set found within the size limit
    return nothing
end

"""
    _combinations(items, k)

Generate all k-element combinations of items. Simple implementation
for small candidate sets used in adjustment set search.
"""
function _combinations(items::Vector{Int}, k::Int)
    n = length(items)
    if k == 0
        return [Int[]]
    end
    if k > n
        return Vector{Int}[]
    end
    result = Vector{Int}[]
    combo = Vector{Int}(undef, k)

    function _generate(start, depth)
        if depth > k
            push!(result, copy(combo))
            return
        end
        for i in start:n
            combo[depth] = items[i]
            _generate(i + 1, depth + 1)
        end
    end

    _generate(1, 1)
    return result
end

"""
    _blocks_all_backdoor_paths(g, Z, backdoor_paths)

Check if set Z blocks all backdoor paths (internal helper function).

A path is blocked by Z if it contains a non-collider in Z or an unblocked collider.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `Z::Set{Int}`: Adjustment set to test
- `backdoor_paths::Vector{Vector{Int}}`: Pre-computed backdoor paths from X to Y

# Returns
- `Bool`: `true` if Z blocks all backdoor paths, `false` otherwise

# Notes
- This is an internal function used by `backdoor_adjustment_set`
- Uses d-separation logic to check path blocking
"""
function _blocks_all_backdoor_paths(g::AbstractGraph, Z::Set, backdoor_paths)
    for path in backdoor_paths
        if !_is_path_blocked(g, path, Z)
            return false  # Found unblocked path
        end
    end
    return true  # All paths blocked
end

# _is_path_blocked is available from d_separation.jl after it's included

"""
    is_backdoor_adjustable(g, X, Y)

Check if the causal effect of X on Y is identifiable via backdoor adjustment.

The effect is identifiable if there exists a valid backdoor adjustment set,
or if there are no backdoor paths (no confounding).

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Int`: Treatment node
- `Y::Int`: Outcome node

# Returns
- `Bool`: `true` if backdoor adjustment is possible, `false` otherwise

# Examples

```julia
using CausalDynamics, Graphs

# Confounding case
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

is_backdoor_adjustable(g, 2, 3)  # true (Z is valid adjustment set)

# No confounding
g2 = DiGraph(2)
add_edge!(g2, 1, 2)  # X → Y

is_backdoor_adjustable(g2, 1, 2)  # true (no backdoor paths)
```

# See Also
- `backdoor_adjustment_set`: Find a valid adjustment set
"""
function is_backdoor_adjustable(g::AbstractGraph, X::Int, Y::Int)
    backdoor_paths = find_backdoor_paths(g, X, Y)
    if isempty(backdoor_paths)
        return true  # No confounding — always adjustable
    end
    adj_set = backdoor_adjustment_set(g, X, Y)
    return adj_set !== nothing
end

export backdoor_adjustment_set, is_backdoor_adjustable
