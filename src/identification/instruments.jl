"""
    find_instruments(g, X, Y)

Find instrumental variables for estimating the causal effect of X on Y.

An instrumental variable Z must satisfy:
1. Z has a causal effect on X
2. Z affects Y only through X (exclusion restriction)
3. Z is independent of confounders of X and Y (independence)

# Arguments
- `g`: Directed acyclic graph
- `X`: Treatment node
- `Y`: Outcome node

# Returns
- Vector of potential instrumental variables

# Examples

```julia
using CausalDynamics, Graphs

# IV example
g = DiGraph(4)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 2, 3)  # X → Y
add_edge!(g, 4, 2)  # U → X
add_edge!(g, 4, 3)  # U → Y

# Z is a valid instrument
instruments = find_instruments(g, 2, 3)  # [1]
```

# References
- Angrist, J. D., & Pischke, J. S. (2009). *Mostly Harmless Econometrics*
"""
function find_instruments(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    
    # Validate node indices
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    instruments = Vector{Int}()  # Pre-allocate for type stability
    
    # Find all nodes that have a directed path to X
    ancestors_X = get_ancestors(g, X)
    
    for Z in ancestors_X
        if Z == X
            continue  # Skip X itself
        end
        
        # Check if Z is a valid instrument
        if is_valid_instrument(g, Z, X, Y)
            push!(instruments, Z)
        end
    end
    
    return instruments
end

"""
    is_valid_instrument(g, Z, X, Y)

Check if Z is a valid instrumental variable for X → Y.

An instrument Z must satisfy three conditions:
1. **Relevance**: Z has a causal effect on X (directed path Z → X)
2. **Exclusion restriction**: Z affects Y only through X (all paths Z → Y go through X)
3. **Independence**: Z is independent of confounders (no backdoor paths Z → Y)

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `Z::Int`: Potential instrument node
- `X::Int`: Treatment node
- `Y::Int`: Outcome node

# Returns
- `Bool`: `true` if Z is a valid instrument, `false` otherwise

# Examples

```julia
using CausalDynamics, Graphs

# Valid instrument
g = DiGraph(4)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 2, 3)  # X → Y
add_edge!(g, 4, 2)  # U → X
add_edge!(g, 4, 3)  # U → Y

is_valid_instrument(g, 1, 2, 3)  # true

# Invalid: Z has direct path to Y
g2 = DiGraph(3)
add_edge!(g2, 1, 2)  # Z → X
add_edge!(g2, 1, 3)  # Z → Y (violates exclusion)
add_edge!(g2, 2, 3)  # X → Y

is_valid_instrument(g2, 1, 2, 3)  # false
```

# Notes
- The independence condition (3) is checked conservatively: if any backdoor paths exist, returns `false`
- In practice, independence may hold even with backdoor paths if they are blocked

# References
- Angrist, J. D., & Pischke, J. S. (2009). *Mostly Harmless Econometrics*, Chapter 4
"""
function is_valid_instrument(g::AbstractGraph, Z::Int, X::Int, Y::Int)
    # Validate node indices
    if Z < 1 || Z > nv(g) || X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices Z=$Z, X=$X, Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    # Condition 1: Z has a causal effect on X (there's a directed path Z → X)
    if !has_path(g, Z, X)
        return false
    end
    
    # Condition 2: Z affects Y only through X (exclusion restriction)
    # Check if there are any directed paths from Z to Y that don't go through X
    paths_ZY = find_directed_paths(g, Z, Y)
    for path in paths_ZY
        if X ∉ path
            return false  # Path from Z to Y that doesn't go through X
        end
    end
    
    # Condition 3: Z is independent of confounders (no backdoor paths from Z to Y)
    # This is harder to check without knowing confounders
    # For now, we check if there are no backdoor paths
    backdoor_paths = find_backdoor_paths(g, Z, Y)
    if !isempty(backdoor_paths)
        # Check if these paths are blocked (indicating independence)
        # This is a simplified check
        return false  # Conservative: if backdoor paths exist, may not be valid
    end
    
    return true
end

"""
    has_path(g, source, target)

Check if there exists a directed path from source to target.

A directed path follows edges in their forward direction only.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `source::Int`: Source node
- `target::Int`: Target node

# Returns
- `Bool`: `true` if a directed path exists, `false` otherwise

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)  # X → Y
add_edge!(g, 2, 3)  # Y → Z

has_path(g, 1, 3)  # true (path: 1 → 2 → 3)
has_path(g, 3, 1)  # false (no reverse path)
```

# Notes
- Returns `false` if source == target (no self-loops)
- Uses `find_directed_paths` internally
"""
function has_path(g::AbstractGraph, source::Int, target::Int)
    paths = find_directed_paths(g, source, target)
    return !isempty(paths)
end

export find_instruments, is_valid_instrument
