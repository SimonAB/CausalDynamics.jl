"""
    frontdoor_adjustment_set(g, X, Y, M)

Check if M is a valid frontdoor adjustment set for estimating the causal effect of X on Y.

The frontdoor criterion states that a set M is a valid frontdoor adjustment set if:
1. M blocks all directed paths from X to Y
2. There are no backdoor paths from X to M
3. All backdoor paths from M to Y are blocked by X

# Arguments
- `g`: Directed acyclic graph
- `X`: Treatment node
- `Y`: Outcome node
- `M`: Potential mediator set

# Returns
- `true` if M is a valid frontdoor adjustment set, `false` otherwise

# Examples

```julia
using CausalDynamics, Graphs

# Frontdoor example: X → M → Y, with confounding U
g = DiGraph(4)
add_edge!(g, 1, 2)  # U → X
add_edge!(g, 1, 4)  # U → Y
add_edge!(g, 2, 3)  # X → M
add_edge!(g, 3, 4)  # M → Y

# M is a valid frontdoor adjustment set
is_valid = frontdoor_adjustment_set(g, 2, 4, [3])  # true
```

# References
- Pearl, J. (2009). *Causality*, Chapter 3
"""
function frontdoor_adjustment_set(g::AbstractGraph, X::Int, Y::Int, M)
    validate_causal_graph(g)
    
    # Validate node indices
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    M_set = M isa AbstractVector ? Set(M) : Set([M])
    
    # Condition 1: M blocks all directed paths from X to Y
    directed_paths = find_directed_paths(g, X, Y)
    for path in directed_paths
        # Check if path goes through M
        if isempty(intersect(Set(path), M_set))
            # Path doesn't go through M - check if it's blocked
            if !_is_path_blocked(g, path, M_set)
                return false  # M doesn't block all directed paths
            end
        end
    end
    
    # Condition 2: No backdoor paths from X to M
    for m in M_set
        backdoor_paths_XM = find_backdoor_paths(g, X, m)
        if !isempty(backdoor_paths_XM)
            return false  # Backdoor path exists from X to M
        end
    end
    
    # Condition 3: All backdoor paths from M to Y are blocked by X
    for m in M_set
        backdoor_paths_MY = find_backdoor_paths(g, m, Y)
        X_set = Set([X])
        for path in backdoor_paths_MY
            if !_is_path_blocked(g, path, X_set)
                return false  # Backdoor path from M to Y not blocked by X
            end
        end
    end
    
    return true  # All conditions satisfied
end

# _is_path_blocked is available from d_separation.jl (included before this file)

"""
    find_frontdoor_mediators(g, X, Y)

Find potential frontdoor mediators between X and Y.

Searches for nodes on directed paths from X to Y that satisfy the frontdoor criterion.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Int`: Treatment node
- `Y::Int`: Outcome node

# Returns
- `Vector{Set{Int}}`: Vector of potential mediator sets (each set contains nodes that form a valid frontdoor adjustment set)

# Examples

```julia
using CausalDynamics, Graphs

# Frontdoor example
g = DiGraph(4)
add_edge!(g, 1, 2)  # U → X
add_edge!(g, 1, 4)  # U → Y
add_edge!(g, 2, 3)  # X → M
add_edge!(g, 3, 4)  # M → Y

mediators = find_frontdoor_mediators(g, 2, 4)  # [Set([3])]
```

# Notes
- Only checks single-node mediators (not multi-node sets)
- Returns empty vector if no valid mediators found
- For multi-node frontdoor sets, use `frontdoor_adjustment_set` directly

# See Also
- `frontdoor_adjustment_set`: Check if a specific set is a valid frontdoor adjustment set
"""
function find_frontdoor_mediators(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    
    # Validate node indices
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    mediators = Vector{Set{Int}}()
    
    # Find all nodes on directed paths from X to Y
    directed_paths = find_directed_paths(g, X, Y)
    nodes_on_paths = Set{Int}()
    for path in directed_paths
        union!(nodes_on_paths, Set(path))
    end
    delete!(nodes_on_paths, X)
    delete!(nodes_on_paths, Y)
    
    # Check each subset of nodes on paths
    for node in nodes_on_paths
        if frontdoor_adjustment_set(g, X, Y, [node])
            push!(mediators, Set([node]))
        end
    end
    
    return mediators
end

export frontdoor_adjustment_set, find_frontdoor_mediators
