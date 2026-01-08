"""
    find_all_adjustment_sets(g, X, Y)

Find all valid adjustment sets for estimating the causal effect of X on Y.

A valid adjustment set Z must:
1. Block all backdoor paths from X to Y
2. Not contain X, Y, or any descendants of X

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Int`: Treatment node
- `Y::Int`: Outcome node

# Returns
- `Vector{Set{Int}}`: Vector of all valid adjustment sets (limited to sets of size ≤ 5 for performance)

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 2)  # Z₁ → X
add_edge!(g, 3, 2)  # Z₂ → X
add_edge!(g, 1, 4)  # Z₁ → Y
add_edge!(g, 3, 4)  # Z₂ → Y
add_edge!(g, 2, 4)  # X → Y

all_sets = find_all_adjustment_sets(g, 2, 4)
# Returns: [Set([1]), Set([3]), Set([1, 3])]
```

# Notes
- **Computational complexity**: Exponential in number of candidate nodes
- **Performance limit**: Only returns sets of size ≤ 5
- For large graphs, use `backdoor_adjustment_set` or `minimal_adjustment_set` instead

# See Also
- `backdoor_adjustment_set`: Find a single valid adjustment set
- `minimal_adjustment_set`: Find the smallest valid adjustment set
- `is_valid_adjustment_set`: Check if a specific set is valid
"""
function find_all_adjustment_sets(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    
    # Validate node indices
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    # Get all nodes except X, Y, and descendants of X
    all_nodes = Set(vertices(g))
    descendants_X = get_descendants(g, X)
    invalid_nodes = union(Set([X, Y]), descendants_X)
    candidate_nodes = setdiff(all_nodes, invalid_nodes)
    
    # Find all subsets of candidate nodes
    valid_sets = Vector{Set{Int}}()
    
    # Check each subset (this is exponential - may need optimization)
    # Limit to small sets for performance
    for subset in powerset(candidate_nodes)
        if length(subset) <= 5 && is_valid_adjustment_set(g, X, Y, subset)  # Limit size
            push!(valid_sets, subset)
        end
    end
    
    return valid_sets
end

"""
    is_valid_adjustment_set(g, X, Y, Z)

Check if Z is a valid adjustment set for X → Y.

A valid adjustment set Z must satisfy the backdoor criterion:
1. Z blocks all backdoor paths from X to Y
2. Z does not contain X, Y, or any descendants of X

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Int`: Treatment node
- `Y::Int`: Outcome node
- `Z::Set{Int}`: Candidate adjustment set

# Returns
- `Bool`: `true` if Z is a valid adjustment set, `false` otherwise

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

is_valid_adjustment_set(g, 2, 3, Set([1]))  # true
is_valid_adjustment_set(g, 2, 3, Set([2]))  # false (contains X)
is_valid_adjustment_set(g, 2, 3, Set([3]))  # false (contains Y)
```

# See Also
- `backdoor_adjustment_set`: Find a valid adjustment set automatically
- `find_all_adjustment_sets`: Find all valid adjustment sets
"""
function is_valid_adjustment_set(g::AbstractGraph, X::Int, Y::Int, Z::Set)
    # Validate node indices
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    # Z must not contain X, Y, or descendants of X
    descendants_X = get_descendants(g, X)
    if X ∈ Z || Y ∈ Z || !isempty(intersect(Z, descendants_X))
        return false
    end
    
    # Z must block all backdoor paths
    backdoor_paths = find_backdoor_paths(g, X, Y)
    return _blocks_all_backdoor_paths(g, Z, backdoor_paths)
end

"""
    minimal_adjustment_set(g, X, Y)

Find a minimal valid adjustment set (if one exists).

A minimal adjustment set is the smallest valid adjustment set (fewest nodes).

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `X::Int`: Treatment node
- `Y::Int`: Outcome node

# Returns
- `Union{Set{Int}, Nothing}`: Minimal adjustment set, or `nothing` if no valid set exists

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 2)  # Z₁ → X
add_edge!(g, 3, 2)  # Z₂ → X
add_edge!(g, 1, 4)  # Z₁ → Y
add_edge!(g, 3, 4)  # Z₂ → Y
add_edge!(g, 2, 4)  # X → Y

minimal = minimal_adjustment_set(g, 2, 4)
# Returns: Set([1]) or Set([3]) (one of the minimal sets)
```

# Notes
- Uses `find_all_adjustment_sets` internally, so subject to same performance limits
- If multiple minimal sets exist, returns one of them (not necessarily unique)
- Returns `nothing` if no valid adjustment set exists

# See Also
- `backdoor_adjustment_set`: Find a valid adjustment set (may not be minimal)
- `find_all_adjustment_sets`: Find all valid adjustment sets
"""
function minimal_adjustment_set(g::AbstractGraph, X::Int, Y::Int)
    # Validation happens in find_all_adjustment_sets
    all_sets = find_all_adjustment_sets(g, X, Y)
    
    if isempty(all_sets)
        return nothing
    end
    
    # Find set with minimum size
    minimal = all_sets[1]
    for s in all_sets
        if length(s) < length(minimal)
            minimal = s
        end
    end
    
    return minimal
end

"""
    powerset(s)

Generate the power set (set of all subsets) of set s.

# Arguments
- `s::Set{T}`: Input set

# Returns
- `Vector{Set{T}}`: Vector containing all subsets of s (including empty set and s itself)

# Examples

```julia
using CausalDynamics

s = Set([1, 2, 3])
all_subsets = powerset(s)
# Returns: [Set([]), Set([1]), Set([2]), Set([3]), Set([1, 2]), Set([1, 3]), Set([2, 3]), Set([1, 2, 3])]
```

# Notes
- **Computational complexity**: O(2^n) where n = length(s)
- Use with caution for large sets (n > 10)
- Used internally by `find_all_adjustment_sets`
"""
function powerset(s::Set)
    elements = collect(s)
    n = length(elements)
    subsets = Vector{Set{eltype(s)}}()
    
    for i in 0:(2^n - 1)
        subset = Set{eltype(s)}()
        for j in 1:n
            if (i >> (j-1)) & 1 == 1
                push!(subset, elements[j])
            end
        end
        push!(subsets, subset)
    end
    
    return subsets
end

export find_all_adjustment_sets, is_valid_adjustment_set, minimal_adjustment_set
