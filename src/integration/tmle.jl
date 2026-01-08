"""
    TMLE Integration

Functions to integrate CausalDynamics.jl with TMLE.jl for causal effect estimation.

CausalDynamics.jl identifies adjustment sets from causal graphs, and TMLE.jl estimates
causal effects using those adjustment sets. This module provides convenience functions
to bridge the two packages.
"""

"""
    prepare_for_tmle(g, X, Y; node_names=nothing)

Prepare adjustment set from causal graph for use with TMLE.jl.

# Arguments
- `g`: Directed acyclic graph
- `X`: Treatment node (integer or symbol)
- `Y`: Outcome node (integer or symbol)
- `node_names`: Optional mapping from node indices to symbols/names. If provided,
  returns symbol names; otherwise returns node indices.

# Returns
- `adj_set`: Vector of confounders (symbols or integers) ready for TMLE.jl
- `is_identifiable`: Boolean indicating if effect is identifiable via backdoor adjustment

# Examples

```julia
using CausalDynamics, TMLE, DataFrames

# Create graph: Z → X → Y, Z → Y
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# With node names
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
confounders, identifiable = prepare_for_tmle(g, 2, 3; node_names=node_names)
# Returns: ([:Z], true)

# Without node names (returns indices)
confounders, identifiable = prepare_for_tmle(g, 2, 3)
# Returns: ([1], true)
```

# See Also
- `backdoor_adjustment_set`: Find backdoor adjustment set
- `is_backdoor_adjustable`: Check if backdoor adjustment is possible
"""
function prepare_for_tmle(g::AbstractGraph, X::Int, Y::Int; node_names=nothing)
    # Validation happens in backdoor_adjustment_set
    # Find adjustment set
    adj_set = backdoor_adjustment_set(g, X, Y)
    
    # Check identifiability
    is_identifiable = !isempty(adj_set) || is_backdoor_adjustable(g, X, Y)
    
    # Convert to vector and apply node names if provided
    if node_names !== nothing
        # Convert node indices to symbols
        # Pre-allocate for type stability
        confounders = Vector{Symbol}(undef, length(adj_set))
        for (i, node) in enumerate(adj_set)
            confounders[i] = node_names[node]
        end
    else
        # Return as vector of integers
        confounders = collect(adj_set)
    end
    
    return confounders, is_identifiable
end

"""
    estimate_effect(g, data, X, Y; node_names=nothing, method=:tmle, kwargs...)

Estimate causal effect using identified adjustment set and TMLE.jl.

This function combines identification (CausalDynamics.jl) with estimation (TMLE.jl)
in a single workflow.

# Arguments
- `g`: Directed acyclic graph
- `data`: DataFrame or table with observed data
- `X`: Treatment variable (integer index or symbol/name)
- `Y`: Outcome variable (integer index or symbol/name)
- `node_names`: Optional mapping from node indices to symbols/names. Required if
  X and Y are integers and data columns are named.
- `method`: Estimation method (currently only `:tmle` supported)
- `kwargs...`: Additional arguments passed to TMLE.jl estimation function

# Returns
- TMLE.jl result object with effect estimate, confidence intervals, etc.

# Examples

```julia
using CausalDynamics, TMLE, DataFrames

# Create graph: Z → X → Y, Z → Y
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Create data
data = DataFrame(
    Z = randn(100),
    X = rand([0, 1], 100),
    Y = randn(100)
)

# Estimate effect with node names
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
result = estimate_effect(g, data, 2, 3; node_names=node_names)

# Or use symbols directly if graph uses symbols
result = estimate_effect(g, data, :X, :Y)
```

# Notes

- Requires TMLE.jl to be loaded: `using TMLE`
- If no adjustment set is found, a warning is issued but estimation may still proceed
- Additional TMLE.jl arguments can be passed via `kwargs...`

# See Also
- `prepare_for_tmle`: Prepare adjustment set for TMLE.jl
- `backdoor_adjustment_set`: Find backdoor adjustment set
"""
function estimate_effect(g::AbstractGraph, data, X::Int, Y::Int; node_names=nothing, method=:tmle, kwargs...)
    # Validate node indices first (before checking TMLE)
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    # Check if TMLE is available
    # Try to find TMLE module in loaded modules
    tmle_module = nothing
    for mod in Base.loaded_modules_array()
        if nameof(mod) == :TMLE
            tmle_module = mod
            break
        end
    end
    
    if tmle_module === nothing
        error("TMLE.jl must be loaded. Use: using TMLE")
    end
    
    # Get adjustment set
    confounders, is_identifiable = prepare_for_tmle(g, X, Y; node_names=node_names)
    
    # Warn if not identifiable (contextualized error message)
    if !is_identifiable || isempty(confounders)
        treatment_name = node_names !== nothing && X isa Integer ? node_names[X] : X
        outcome_name = node_names !== nothing && Y isa Integer ? node_names[Y] : Y
        @warn "No backdoor adjustment set found for $treatment_name → $outcome_name. Effect may not be identifiable via backdoor adjustment. Consider checking for frontdoor adjustment (find_frontdoor_mediators) or instrumental variables (find_instruments). Proceeding with estimation anyway."
    end
    
    # Determine treatment and outcome names
    treatment_name = if node_names !== nothing && X isa Integer
        node_names[X]
    else
        X
    end
    
    outcome_name = if node_names !== nothing && Y isa Integer
        node_names[Y]
    else
        Y
    end
    
    # Call TMLE.jl
    if method == :tmle
        # Get TMLE.tmle function
        tmle_func = getproperty(tmle_module, :tmle)
        
        return tmle_func(
            data,
            treatment=treatment_name,
            outcome=outcome_name,
            confounders=confounders;
            kwargs...
        )
    else
        error("Unknown estimation method: $method. Currently only :tmle is supported.")
    end
end

"""
    get_tmle_confounders(g, X, Y; node_names=nothing)

Get confounders for TMLE.jl from causal graph.

Convenience function that returns just the confounders vector, without
the identifiability check.

# Arguments
- `g`: Directed acyclic graph
- `X`: Treatment node (integer or symbol)
- `Y`: Outcome node (integer or symbol)
- `node_names`: Optional mapping from node indices to symbols/names

# Returns
- Vector of confounders (symbols or integers) ready for TMLE.jl

# Examples

```julia
using CausalDynamics

g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 3)

node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
confounders = get_tmle_confounders(g, 2, 3; node_names=node_names)
# Returns: [:Z]
```

# See Also
- `prepare_for_tmle`: Full preparation with identifiability check
- `backdoor_adjustment_set`: Find backdoor adjustment set
"""
function get_tmle_confounders(g::AbstractGraph, X::Int, Y::Int; node_names=nothing)
    # Validation happens in prepare_for_tmle
    confounders, _ = prepare_for_tmle(g, X, Y; node_names=node_names)
    return confounders
end

export prepare_for_tmle, estimate_effect, get_tmle_confounders
