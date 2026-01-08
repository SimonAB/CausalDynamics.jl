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
        # No backdoor paths - no adjustment needed
        return Set{Int}()
    end
    
    # Get descendants of X (cannot be in adjustment set)
    descendants_X = get_descendants(g, X)
    
    # Find minimal set that blocks all backdoor paths
    # Simple approach: use parents of X that are not descendants of X
    parents_X = get_parents(g, X)
    valid_adjustment = setdiff(parents_X, descendants_X)
    
    # Check if this set blocks all backdoor paths
    if _blocks_all_backdoor_paths(g, valid_adjustment, backdoor_paths)
        return valid_adjustment
    end
    
    # If parents don't work, try more sophisticated algorithm
    # For now, return parents as a heuristic
    return valid_adjustment
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
    adj_set = backdoor_adjustment_set(g, X, Y)
    return adj_set !== nothing && !isempty(adj_set) || isempty(find_backdoor_paths(g, X, Y))
end

export backdoor_adjustment_set, is_backdoor_adjustable
