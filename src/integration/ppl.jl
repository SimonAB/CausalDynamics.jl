"""
    Probabilistic Programming Language (PPL) Integration

Functions to integrate CausalDynamics.jl with probabilistic programming packages
like Turing.jl and RxInfer.jl for Bayesian causal inference.

This module provides utilities to:
- Convert causal graphs to PPL model specifications
- Extract data in formats compatible with PPL packages
- Prepare adjustment sets for Bayesian estimation
"""

# DataFrames is in dependencies but not imported in main module
# We'll use it conditionally here

"""
    prepare_for_turing(g, X, Y; node_names=nothing, data=nothing)

Prepare causal graph and data for use with Turing.jl.

Turing.jl uses DataFrames or NamedTuples for data, and requires explicit
variable names. This function extracts the necessary information from a
CausalGraph or prepares it from a plain graph.

# Arguments
- `g`: Directed acyclic graph (DiGraph or CausalGraph)
- `X::Int`: Treatment node index
- `Y::Int`: Outcome node index
- `node_names::Union{Dict{Int, Symbol}, Nothing}`: Optional mapping from node indices to names.
  For `CausalGraph`, automatically extracted if not provided.
- `data`: Optional data (DataFrame, NamedTuple, or other). For `CausalGraph`, automatically
  extracted if attached and not provided.

# Returns
- `NamedTuple` with fields:
  - `graph`: The underlying graph (DiGraph)
  - `treatment`: Treatment variable name (Symbol) or index (Int)
  - `outcome`: Outcome variable name (Symbol) or index (Int)
  - `confounders`: Vector of confounder names (Symbol) or indices (Int)
  - `data`: Data in format compatible with Turing
  - `node_names`: Dictionary mapping node indices to names
  - `is_identifiable`: Boolean indicating if effect is identifiable

# Examples

```julia
using CausalDynamics, DataFrames

# With CausalGraph
g = CausalGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 3)
set_node_prop!(g, 1, :name, :Z)
set_node_prop!(g, 2, :name, :X)
set_node_prop!(g, 3, :name, :Y)
data = DataFrame(Z=randn(100), X=rand([0,1], 100), Y=randn(100))
attach_data!(g, data)

spec = prepare_for_turing(g, 2, 3)
# Returns: (graph=..., treatment=:X, outcome=:Y, confounders=[:Z], data=..., ...)

# Use in Turing model
using Turing
@model function causal_model(spec)
    # Use spec.treatment, spec.outcome, spec.confounders, spec.data
    # ...
end
```

# Notes

- Data is returned as-is (DataFrame or NamedTuple) - Turing accepts both
- Node names are required for meaningful variable names in models
- If node names are not available, indices are used instead

# See Also
- `prepare_for_rxinfer`: Prepare for RxInfer.jl
- `get_tmle_confounders`: Get confounders for TMLE
"""
function prepare_for_turing(g::AbstractGraph, X::Int, Y::Int;
    node_names::Union{Dict{Int, Symbol}, Nothing}=nothing,
    data=nothing
)
    # Get node names
    if node_names === nothing && g isa CausalGraph
        node_names = get_node_names(g)
        if isempty(node_names)
            node_names = nothing
        end
    end
    
    # Get data
    if data === nothing && g isa CausalGraph
        data = get_data(g)
    end
    
    # Get confounders
    confounders, is_identifiable = prepare_for_tmle(g, X, Y; node_names=node_names)
    
    # Determine treatment and outcome names
    treatment = if node_names !== nothing && haskey(node_names, X)
        node_names[X]
    else
        X
    end
    
    outcome = if node_names !== nothing && haskey(node_names, Y)
        node_names[Y]
    else
        Y
    end
    
    # Get underlying graph
    underlying_graph = g isa CausalGraph ? g.graph : g
    
    return (
        graph = underlying_graph,
        treatment = treatment,
        outcome = outcome,
        confounders = confounders,
        data = data,
        node_names = node_names,
        is_identifiable = is_identifiable
    )
end

"""
    prepare_for_rxinfer(g, X, Y; node_names=nothing, data=nothing)

Prepare causal graph and data for use with RxInfer.jl.

RxInfer.jl uses various data formats and requires explicit variable specifications.
This function extracts the necessary information from a CausalGraph or prepares
it from a plain graph.

# Arguments
- `g`: Directed acyclic graph (DiGraph or CausalGraph)
- `X::Int`: Treatment node index
- `Y::Int`: Outcome node index
- `node_names::Union{Dict{Int, Symbol}, Nothing}`: Optional mapping from node indices to names.
  For `CausalGraph`, automatically extracted if not provided.
- `data`: Optional data (DataFrame, NamedTuple, or other). For `CausalGraph`, automatically
  extracted if attached and not provided.

# Returns
- `NamedTuple` with fields:
  - `graph`: The underlying graph (DiGraph)
  - `treatment`: Treatment variable name (Symbol) or index (Int)
  - `outcome`: Outcome variable name (Symbol) or index (Int)
  - `confounders`: Vector of confounder names (Symbol) or indices (Int)
  - `data`: Data in format compatible with RxInfer
  - `node_names`: Dictionary mapping node indices to names
  - `is_identifiable`: Boolean indicating if effect is identifiable

# Examples

```julia
using CausalDynamics, DataFrames

# With CausalGraph
g = CausalGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 3)
set_node_prop!(g, 1, :name, :Z)
set_node_prop!(g, 2, :name, :X)
set_node_prop!(g, 3, :name, :Y)
data = DataFrame(Z=randn(100), X=rand([0,1], 100), Y=randn(100))
attach_data!(g, data)

spec = prepare_for_rxinfer(g, 2, 3)
# Returns: (graph=..., treatment=:X, outcome=:Y, confounders=[:Z], data=..., ...)

# Use in RxInfer model
using RxInfer
# Use spec.treatment, spec.outcome, spec.confounders, spec.data
```

# Notes

- Data is returned as-is - RxInfer accepts various formats
- Node names are required for meaningful variable names in models
- If node names are not available, indices are used instead
- RxInfer typically uses NamedTuples or dictionaries for data

# See Also
- `prepare_for_turing`: Prepare for Turing.jl
- `get_tmle_confounders`: Get confounders for TMLE
"""
function prepare_for_rxinfer(g::AbstractGraph, X::Int, Y::Int;
    node_names::Union{Dict{Int, Symbol}, Nothing}=nothing,
    data=nothing
)
    # RxInfer uses similar format to Turing, so delegate
    # (RxInfer accepts DataFrames, NamedTuples, and other table formats)
    return prepare_for_turing(g, X, Y; node_names=node_names, data=data)
end

"""
    get_data_for_ppl(g; format=:dataframe)

Extract data from CausalGraph in a format suitable for probabilistic programming.

# Arguments
- `g::CausalGraph`: The causal graph with attached data
- `format::Symbol`: Desired output format (`:dataframe`, `:namedtuple`, `:dict`)

# Returns
- Data in the requested format, or `nothing` if no data attached

# Examples

```julia
using CausalDynamics, DataFrames

g = CausalGraph(3)
data = DataFrame(Z=randn(100), X=rand([0,1], 100), Y=randn(100))
attach_data!(g, data)

# Get as DataFrame (default)
df = get_data_for_ppl(g)  # DataFrame

# Get as NamedTuple (for Turing/RxInfer)
nt = get_data_for_ppl(g; format=:namedtuple)  # NamedTuple

# Get as Dict
dict = get_data_for_ppl(g; format=:dict)  # Dict
```

# Notes

- Requires data to be attached to the graph
- Format conversion may have performance implications for large datasets
- NamedTuple format is efficient for Turing.jl
- Dict format is flexible for various PPL packages

# See Also
- `get_data`: Get data as-is
- `attach_data!`: Attach data to graph
"""
function get_data_for_ppl(g::CausalGraph; format::Symbol=:dataframe)
    data = get_data(g)
    if data === nothing
        return nothing
    end
    
    if format == :dataframe
        return data
    elseif format == :namedtuple
        # Convert to NamedTuple
        if data isa NamedTuple
            return data
        elseif hasmethod(names, (typeof(data),)) && hasmethod(getindex, (typeof(data), Symbol))
            # DataFrame-like type (has names and getindex)
            col_names = names(data)
            cols = [Symbol(col) => Vector(data[col]) for col in col_names]
            return NamedTuple(cols)
        elseif hasmethod(names, (typeof(data),)) && hasmethod(getproperty, (typeof(data), Symbol))
            # DataFrame-like type (has names and getproperty)
            col_names = names(data)
            cols = [Symbol(col) => Vector(getproperty(data, col)) for col in col_names]
            return NamedTuple(cols)
        else
            error("Cannot convert data type $(typeof(data)) to NamedTuple. Data must be a NamedTuple or table-like type with names() and getindex/getproperty methods.")
        end
    elseif format == :dict
        # Convert to Dict
        if data isa Dict
            return data
        elseif data isa NamedTuple
            return Dict(pairs(data))
        elseif hasmethod(names, (typeof(data),)) && hasmethod(getindex, (typeof(data), Symbol))
            # DataFrame-like type
            col_names = names(data)
            return Dict(Symbol(col) => Vector(data[col]) for col in col_names)
        elseif hasmethod(names, (typeof(data),)) && hasmethod(getproperty, (typeof(data), Symbol))
            # DataFrame-like type
            col_names = names(data)
            return Dict(Symbol(col) => Vector(getproperty(data, col)) for col in col_names)
        else
            error("Cannot convert data type $(typeof(data)) to Dict. Data must be a Dict, NamedTuple, or table-like type with names() and getindex/getproperty methods.")
        end
    else
        error("Unknown format: $format. Supported formats: :dataframe, :namedtuple, :dict")
    end
end

export prepare_for_turing, prepare_for_rxinfer, get_data_for_ppl
