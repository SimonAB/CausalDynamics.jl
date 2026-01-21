"""
    CausalGraph

A causal graph with attached properties (node names, data, metadata).

Extends `DiGraph` with property storage for causal inference workflows, including
integration with statistical estimation packages (TMLE.jl, Turing.jl, RxInfer.jl).

# Fields
- `graph::DiGraph`: The underlying directed acyclic graph structure
- `node_props::Dict{Int, Dict{Symbol, Any}}`: Properties attached to nodes
- `edge_props::Dict{Tuple{Int, Int}, Dict{Symbol, Any}}`: Properties attached to edges
- `graph_props::Dict{Symbol, Any}`: Graph-level properties (e.g., data, metadata)

# Examples

```julia
using CausalDynamics

# Create a causal graph with properties
g = CausalGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Attach node names
set_node_prop!(g, 1, :name, :Z)
set_node_prop!(g, 2, :name, :X)
set_node_prop!(g, 3, :name, :Y)

# Attach data (DataFrame, NamedTuple, or other table format)
# using DataFrames  # Optional - only needed if using DataFrames
# data = DataFrame(Z=randn(100), X=rand([0,1], 100), Y=randn(100))
# set_prop!(g, :data, data)
# Or use attach_data! convenience function
# attach_data!(g, data)

# Access properties
get_node_prop(g, 1, :name)  # :Z
get_prop(g, :data)  # DataFrame
```

# Notes

- All `Graphs.jl` operations work on `CausalGraph` (delegated to underlying graph)
- Properties are stored efficiently using nested dictionaries
- Compatible with GraphMakie.jl for visualisation (subtype of `AbstractGraph`)
- Designed for integration with probabilistic programming languages (Turing, RxInfer)

# See Also

- `set_prop!`: Set graph-level properties
- `get_prop`: Get graph-level properties
- `set_node_prop!`: Set node properties
- `get_node_prop`: Get node properties
- `attach_data!`: Convenience function to attach data with node names
"""
struct CausalGraph <: Graphs.AbstractGraph
    graph::Graphs.DiGraph
    node_props::Dict{Int, Dict{Symbol, Any}}
    edge_props::Dict{Tuple{Int, Int}, Dict{Symbol, Any}}
    graph_props::Dict{Symbol, Any}
    
    function CausalGraph(n::Integer)
        if n < 0
            throw(ArgumentError("Number of vertices must be non-negative, got $n"))
        end
        g = Graphs.DiGraph(n)
        node_props = Dict{Int, Dict{Symbol, Any}}()
        edge_props = Dict{Tuple{Int, Int}, Dict{Symbol, Any}}()
        graph_props = Dict{Symbol, Any}()
        return new(g, node_props, edge_props, graph_props)
    end
    
    function CausalGraph(g::Graphs.DiGraph)
        node_props = Dict{Int, Dict{Symbol, Any}}()
        edge_props = Dict{Tuple{Int, Int}, Dict{Symbol, Any}}()
        graph_props = Dict{Symbol, Any}()
        return new(g, node_props, edge_props, graph_props)
    end
end

"""
    CausalGraph(edges; node_names=nothing, data=nothing, kwargs...)

Create a `CausalGraph` from edge specifications with optional properties.

# Arguments
- `edges`: Edge specification, either:
  - `Vector{Tuple{Int, Int}}`: List of (source, target) tuples
  - `Dict{Int, Vector{Int}}`: Dictionary mapping source nodes to vectors of target nodes
- `node_names::Union{Dict{Int, Symbol}, Nothing}`: Optional mapping from node indices to names
- `data`: Optional data to attach (DataFrame, NamedTuple, or other table format)
- `kwargs...`: Additional graph-level properties to set

# Returns
- `CausalGraph`: Validated causal graph with properties attached

# Examples

```julia
using CausalDynamics
# using DataFrames  # Optional - only needed if using DataFrames

# Create graph with node names
edges = [(1, 2), (1, 3), (2, 3)]
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
g = CausalGraph(edges; node_names=node_names)

# Create graph with data (DataFrame, NamedTuple, or other table format)
# data = DataFrame(Z=randn(100), X=rand([0,1], 100), Y=randn(100))
# g = CausalGraph(edges; node_names=node_names, data=data)
```

# See Also
- `create_causal_graph`: Create plain DiGraph from edges
- `attach_data!`: Attach data to existing graph
"""
function CausalGraph(edges::Union{Vector{Tuple{Int, Int}}, Dict{Int, Vector{Int}}};
    node_names::Union{Dict{Int, Symbol}, Nothing}=nothing,
    data=nothing,
    kwargs...
)
    # Convert edges to edge list if needed
    if edges isa Dict
        edge_list = Tuple{Int, Int}[]
        for (source, targets) in edges
            for target in targets
                push!(edge_list, (source, target))
            end
        end
        edges = edge_list
    end
    
    # Find maximum node number
    max_node = 0
    for (src, tgt) in edges
        max_node = max(max_node, src, tgt)
    end
    
    # Create graph
    g = CausalGraph(max_node)
    for (src, tgt) in edges
        Graphs.add_edge!(g.graph, src, tgt)
    end
    
    # Validate DAG
    validate_causal_graph(g.graph)
    
    # Attach node names if provided
    if node_names !== nothing
        for (idx, name) in node_names
            set_node_prop!(g, idx, :name, name)
        end
    end
    
    # Attach data if provided
    if data !== nothing
        set_prop!(g, :data, data)
    end
    
    # Attach additional properties
    for (key, value) in kwargs
        set_prop!(g, key, value)
    end
    
    return g
end

# ============================================================================
# Property API
# ============================================================================

"""
    set_prop!(g, key, value)

Set a graph-level property.

# Arguments
- `g::CausalGraph`: The causal graph
- `key::Symbol`: Property key
- `value`: Property value (any type)

# Examples

```julia
g = CausalGraph(3)
set_prop!(g, :data, my_dataframe)
set_prop!(g, :description, "Confounding example")
```

# See Also
- `get_prop`: Get graph-level property
- `has_prop`: Check if property exists
"""
function set_prop!(g::CausalGraph, key::Symbol, value)
    g.graph_props[key] = value
    return g
end

"""
    get_prop(g, key, default=nothing)

Get a graph-level property.

# Arguments
- `g::CausalGraph`: The causal graph
- `key::Symbol`: Property key
- `default`: Default value if property doesn't exist (default: `nothing`)

# Returns
- Property value, or `default` if not found

# Examples

```julia
g = CausalGraph(3)
set_prop!(g, :data, my_dataframe)
data = get_prop(g, :data)  # Returns DataFrame
missing_prop = get_prop(g, :nonexistent, :default)  # Returns :default
```

# See Also
- `set_prop!`: Set graph-level property
- `has_prop`: Check if property exists
"""
function get_prop(g::CausalGraph, key::Symbol, default=nothing)
    return get(g.graph_props, key, default)
end

"""
    has_prop(g, key)

Check if a graph-level property exists.

# Arguments
- `g::CausalGraph`: The causal graph
- `key::Symbol`: Property key

# Returns
- `Bool`: `true` if property exists, `false` otherwise

# Examples

```julia
g = CausalGraph(3)
set_prop!(g, :data, my_dataframe)
has_prop(g, :data)  # true
has_prop(g, :nonexistent)  # false
```

# See Also
- `set_prop!`: Set graph-level property
- `get_prop`: Get graph-level property
"""
function has_prop(g::CausalGraph, key::Symbol)
    return haskey(g.graph_props, key)
end

"""
    set_node_prop!(g, node, key, value)

Set a property for a specific node.

# Arguments
- `g::CausalGraph`: The causal graph
- `node::Int`: Node index
- `key::Symbol`: Property key
- `value`: Property value (any type)

# Throws
- `ArgumentError`: If node index is out of range

# Examples

```julia
g = CausalGraph(3)
set_node_prop!(g, 1, :name, :Z)
set_node_prop!(g, 1, :type, :confounder)
```

# See Also
- `get_node_prop`: Get node property
- `has_node_prop`: Check if node property exists
- `delete_node_prop!`: Delete node property
"""
function set_node_prop!(g::CausalGraph, node::Int, key::Symbol, value)
    # Validate node index
    if node < 1 || node > Graphs.nv(g.graph)
        throw(ArgumentError("Node index $node is out of range [1, $(Graphs.nv(g.graph))]"))
    end
    
    if !haskey(g.node_props, node)
        g.node_props[node] = Dict{Symbol, Any}()
    end
    g.node_props[node][key] = value
    return g
end

"""
    get_node_prop(g, node, key, default=nothing)

Get a property for a specific node.

# Arguments
- `g::CausalGraph`: The causal graph
- `node::Int`: Node index
- `key::Symbol`: Property key
- `default`: Default value if property doesn't exist (default: `nothing`)

# Returns
- Property value, or `default` if not found

# Examples

```julia
g = CausalGraph(3)
set_node_prop!(g, 1, :name, :Z)
name = get_node_prop(g, 1, :name)  # Returns :Z
type = get_node_prop(g, 1, :type, :unknown)  # Returns :unknown
```

# See Also
- `set_node_prop!`: Set node property
- `has_node_prop`: Check if node property exists
"""
function get_node_prop(g::CausalGraph, node::Int, key::Symbol, default=nothing)
    if !haskey(g.node_props, node)
        return default
    end
    return get(g.node_props[node], key, default)
end

"""
    has_node_prop(g, node, key)

Check if a property exists for a specific node.

# Arguments
- `g::CausalGraph`: The causal graph
- `node::Int`: Node index
- `key::Symbol`: Property key

# Returns
- `Bool`: `true` if property exists, `false` otherwise

# Examples

```julia
g = CausalGraph(3)
set_node_prop!(g, 1, :name, :Z)
has_node_prop(g, 1, :name)  # true
has_node_prop(g, 1, :type)  # false
```

# See Also
- `set_node_prop!`: Set node property
- `get_node_prop`: Get node property
"""
function has_node_prop(g::CausalGraph, node::Int, key::Symbol)
    if !haskey(g.node_props, node)
        return false
    end
    return haskey(g.node_props[node], key)
end

"""
    set_edge_prop!(g, src, dst, key, value)

Set a property for a specific edge.

# Arguments
- `g::CausalGraph`: The causal graph
- `src::Int`: Source node index
- `dst::Int`: Destination node index
- `key::Symbol`: Property key
- `value`: Property value (any type)

# Throws
- `ArgumentError`: If edge doesn't exist in the graph

# Examples

```julia
g = CausalGraph(3)
add_edge!(g, 1, 2)
set_edge_prop!(g, 1, 2, :weight, 0.5)
set_edge_prop!(g, 1, 2, :label, "causes")
```

# See Also
- `get_edge_prop`: Get edge property
- `has_edge_prop`: Check if edge property exists
- `delete_edge_prop!`: Delete edge property
"""
function set_edge_prop!(g::CausalGraph, src::Int, dst::Int, key::Symbol, value)
    # Validate edge exists
    if !Graphs.has_edge(g.graph, src, dst)
        throw(ArgumentError("Edge ($src, $dst) does not exist in the graph"))
    end
    
    edge = (src, dst)
    if !haskey(g.edge_props, edge)
        g.edge_props[edge] = Dict{Symbol, Any}()
    end
    g.edge_props[edge][key] = value
    return g
end

"""
    get_edge_prop(g, src, dst, key, default=nothing)

Get a property for a specific edge.

# Arguments
- `g::CausalGraph`: The causal graph
- `src::Int`: Source node index
- `dst::Int`: Destination node index
- `key::Symbol`: Property key
- `default`: Default value if property doesn't exist (default: `nothing`)

# Returns
- Property value, or `default` if not found

# Examples

```julia
g = CausalGraph(3)
add_edge!(g, 1, 2)
set_edge_prop!(g, 1, 2, :weight, 0.5)
weight = get_edge_prop(g, 1, 2, :weight)  # Returns 0.5
```

# See Also
- `set_edge_prop!`: Set edge property
- `has_edge_prop`: Check if edge property exists
"""
function get_edge_prop(g::CausalGraph, src::Int, dst::Int, key::Symbol, default=nothing)
    edge = (src, dst)
    if !haskey(g.edge_props, edge)
        return default
    end
    return get(g.edge_props[edge], key, default)
end

"""
    has_edge_prop(g, src, dst, key)

Check if a property exists for a specific edge.

# Arguments
- `g::CausalGraph`: The causal graph
- `src::Int`: Source node index
- `dst::Int`: Destination node index
- `key::Symbol`: Property key

# Returns
- `Bool`: `true` if property exists, `false` otherwise

# See Also
- `set_edge_prop!`: Set edge property
- `get_edge_prop`: Get edge property
"""
function has_edge_prop(g::CausalGraph, src::Int, dst::Int, key::Symbol)
    edge = (src, dst)
    if !haskey(g.edge_props, edge)
        return false
    end
    return haskey(g.edge_props[edge], key)
end

# ============================================================================
# Causal-specific convenience functions
# ============================================================================

"""
    get_node_names(g)

Get node names as a dictionary mapping node indices to symbols.

# Arguments
- `g::CausalGraph`: The causal graph

# Returns
- `Dict{Int, Symbol}`: Mapping from node indices to names, or empty dict if no names set

# Examples

```julia
g = CausalGraph(3)
set_node_prop!(g, 1, :name, :Z)
set_node_prop!(g, 2, :name, :X)
set_node_prop!(g, 3, :name, :Y)
names = get_node_names(g)  # Dict(1 => :Z, 2 => :X, 3 => :Y)
```

# See Also
- `set_node_prop!`: Set node name
- `get_node_name`: Get name for single node
"""
function get_node_names(g::CausalGraph)
    names = Dict{Int, Symbol}()
    for (node, props) in g.node_props
        if haskey(props, :name) && props[:name] isa Symbol
            names[node] = props[:name]
        end
    end
    return names
end

"""
    get_node_name(g, node, default=nothing)

Get the name for a specific node.

# Arguments
- `g::CausalGraph`: The causal graph
- `node::Int`: Node index
- `default`: Default value if name not set (default: `nothing`)

# Returns
- `Symbol`: Node name, or `default` if not set

# Examples

```julia
g = CausalGraph(3)
set_node_prop!(g, 1, :name, :Z)
name = get_node_name(g, 1)  # Returns :Z
```

# See Also
- `get_node_names`: Get all node names
- `set_node_prop!`: Set node name
"""
function get_node_name(g::CausalGraph, node::Int, default=nothing)
    return get_node_prop(g, node, :name, default)
end

"""
    attach_data!(g, data; node_names=nothing, check_columns=true)

Attach data to a causal graph with optional column name checking.

Designed for integration with statistical estimation packages:
- **TMLE.jl**: Uses DataFrames with named columns
- **Turing.jl**: Uses DataFrames or NamedTuples
- **RxInfer.jl**: Uses various table formats

# Arguments
- `g::CausalGraph`: The causal graph
- `data`: Data to attach (DataFrame, NamedTuple, or other table format)
- `node_names::Union{Dict{Int, Symbol}, Nothing}`: Optional mapping from node indices to column names.
  If not provided, uses `get_node_names(g)`.
- `check_columns::Bool`: If `true`, verify that data columns match node names (default: `true`)

# Returns
- `CausalGraph`: The graph with data attached (for method chaining)

# Examples

```julia
using CausalDynamics, DataFrames

g = CausalGraph(3)
set_node_prop!(g, 1, :name, :Z)
set_node_prop!(g, 2, :name, :X)
set_node_prop!(g, 3, :name, :Y)

data = DataFrame(Z=randn(100), X=rand([0,1], 100), Y=randn(100))
attach_data!(g, data)  # Automatically uses node names

# Or specify node names explicitly
attach_data!(g, data; node_names=Dict(1 => :Z, 2 => :X, 3 => :Y))
```

# Notes

- Data is stored in graph property `:data`
- Node names are used to map graph nodes to data columns
- Column checking ensures data columns match expected node names
- Compatible with probabilistic programming packages (Turing, RxInfer)

# See Also
- `get_data`: Get attached data
- `has_data`: Check if data is attached
- `get_node_names`: Get node names
"""
function attach_data!(g::CausalGraph, data; node_names::Union{Dict{Int, Symbol}, Nothing}=nothing, check_columns::Bool=true)
    # Get node names
    if node_names === nothing
        node_names = get_node_names(g)
    end
    
    # Check columns if requested and data is a table-like type
    if check_columns && (hasmethod(names, (typeof(data),)) || data isa NamedTuple)
        if data isa NamedTuple
            data_cols = Set(keys(data))
        elseif hasmethod(names, (typeof(data),))
            # DataFrame-like type
            data_cols = Set(Symbol.(names(data)))
        else
            data_cols = Set{Symbol}()  # Can't check
        end
        
        expected_cols = Set(values(node_names))
        missing_cols = setdiff(expected_cols, data_cols)
        if !isempty(missing_cols)
            @warn "Data missing columns for nodes: $missing_cols. Available columns: $data_cols"
        end
    end
    
    # Store data and node names mapping
    set_prop!(g, :data, data)
    if !isempty(node_names)
        set_prop!(g, :node_names, node_names)
    end
    
    return g
end

"""
    get_data(g)

Get the attached data from a causal graph.

# Arguments
- `g::CausalGraph`: The causal graph

# Returns
- Attached data (DataFrame, NamedTuple, or other), or `nothing` if no data attached

# Examples

```julia
g = CausalGraph(3)
data = DataFrame(Z=randn(100), X=rand([0,1], 100), Y=randn(100))
attach_data!(g, data)
retrieved_data = get_data(g)  # Returns DataFrame
```

# See Also
- `attach_data!`: Attach data to graph
- `has_data`: Check if data is attached
"""
function get_data(g::CausalGraph)
    return get_prop(g, :data, nothing)
end

"""
    has_data(g)

Check if data is attached to a causal graph.

# Arguments
- `g::CausalGraph`: The causal graph

# Returns
- `Bool`: `true` if data is attached, `false` otherwise

# See Also
- `get_data`: Get attached data
- `attach_data!`: Attach data to graph
"""
function has_data(g::CausalGraph)
    return has_prop(g, :data)
end

# ============================================================================
# Property deletion methods
# ============================================================================

"""
    delete_prop!(g, key)

Delete a graph-level property.

# Arguments
- `g::CausalGraph`: The causal graph
- `key::Symbol`: Property key to delete

# Returns
- `CausalGraph`: The graph (for method chaining)

# Examples

```julia
g = CausalGraph(3)
set_prop!(g, :data, my_data)
delete_prop!(g, :data)  # Remove data property
```

# See Also
- `set_prop!`: Set graph-level property
- `get_prop`: Get graph-level property
"""
function delete_prop!(g::CausalGraph, key::Symbol)
    delete!(g.graph_props, key)
    return g
end

"""
    delete_node_prop!(g, node, key)

Delete a property for a specific node.

# Arguments
- `g::CausalGraph`: The causal graph
- `node::Int`: Node index
- `key::Symbol`: Property key to delete

# Returns
- `CausalGraph`: The graph (for method chaining)

# Examples

```julia
g = CausalGraph(3)
set_node_prop!(g, 1, :name, :Z)
delete_node_prop!(g, 1, :name)  # Remove name property
```

# See Also
- `set_node_prop!`: Set node property
- `get_node_prop`: Get node property
"""
function delete_node_prop!(g::CausalGraph, node::Int, key::Symbol)
    if haskey(g.node_props, node)
        delete!(g.node_props[node], key)
        # Clean up empty dict
        if isempty(g.node_props[node])
            delete!(g.node_props, node)
        end
    end
    return g
end

"""
    delete_edge_prop!(g, src, dst, key)

Delete a property for a specific edge.

# Arguments
- `g::CausalGraph`: The causal graph
- `src::Int`: Source node index
- `dst::Int`: Destination node index
- `key::Symbol`: Property key to delete

# Returns
- `CausalGraph`: The graph (for method chaining)

# Examples

```julia
g = CausalGraph(3)
add_edge!(g, 1, 2)
set_edge_prop!(g, 1, 2, :weight, 0.5)
delete_edge_prop!(g, 1, 2, :weight)  # Remove weight property
```

# See Also
- `set_edge_prop!`: Set edge property
- `get_edge_prop`: Get edge property
"""
function delete_edge_prop!(g::CausalGraph, src::Int, dst::Int, key::Symbol)
    edge = (src, dst)
    if haskey(g.edge_props, edge)
        delete!(g.edge_props[edge], key)
        # Clean up empty dict
        if isempty(g.edge_props[edge])
            delete!(g.edge_props, edge)
        end
    end
    return g
end

# ============================================================================
# Graphs.jl delegation (AbstractGraph interface)
# ============================================================================

# Core graph operations - delegate to underlying graph
Base.length(g::CausalGraph) = length(g.graph)
Graphs.nv(g::CausalGraph) = Graphs.nv(g.graph)
Graphs.ne(g::CausalGraph) = Graphs.ne(g.graph)
Graphs.vertices(g::CausalGraph) = Graphs.vertices(g.graph)
Graphs.edges(g::CausalGraph) = Graphs.edges(g.graph)
Graphs.has_vertex(g::CausalGraph, v::Integer) = Graphs.has_vertex(g.graph, v)
Graphs.has_edge(g::CausalGraph, s::Integer, d::Integer) = Graphs.has_edge(g.graph, s, d)
Graphs.has_edge(g::CausalGraph, e::Graphs.AbstractEdge) = Graphs.has_edge(g.graph, e)

# Graph modification - delegate and maintain properties
function Graphs.add_vertex!(g::CausalGraph)
    result = Graphs.add_vertex!(g.graph)
    # Properties for new vertex are automatically available (lazy creation)
    return result
end

function Graphs.add_edge!(g::CausalGraph, s::Integer, d::Integer)
    result = Graphs.add_edge!(g.graph, s, d)
    # Edge properties are automatically available (lazy creation)
    return result
end

function Graphs.rem_edge!(g::CausalGraph, s::Integer, d::Integer)
    result = Graphs.rem_edge!(g.graph, s, d)
    # Remove edge properties if edge is removed
    edge = (s, d)
    if haskey(g.edge_props, edge)
        delete!(g.edge_props, edge)
    end
    return result
end

function Graphs.rem_vertex!(g::CausalGraph, v::Integer)
    # Remove node properties
    if haskey(g.node_props, v)
        delete!(g.node_props, v)
    end
    # Remove edge properties involving this vertex
    edges_to_remove = Tuple{Int, Int}[]
    for edge in keys(g.edge_props)
        if edge[1] == v || edge[2] == v
            push!(edges_to_remove, edge)
        end
    end
    for edge in edges_to_remove
        delete!(g.edge_props, edge)
    end
    return Graphs.rem_vertex!(g.graph, v)
end

# Neighbour operations
Graphs.inneighbors(g::CausalGraph, v::Integer) = Graphs.inneighbors(g.graph, v)
Graphs.outneighbors(g::CausalGraph, v::Integer) = Graphs.outneighbors(g.graph, v)
Graphs.all_neighbors(g::CausalGraph, v::Integer) = Graphs.all_neighbors(g.graph, v)

# Edge operations
Graphs.src(e::Graphs.AbstractEdge, g::CausalGraph) = Graphs.src(e, g.graph)
Graphs.dst(e::Graphs.AbstractEdge, g::CausalGraph) = Graphs.dst(e, g.graph)

# Graph properties
Graphs.is_directed(::Type{CausalGraph}) = true
Graphs.is_directed(g::CausalGraph) = true

# Required for some Graphs.jl operations
Graphs.zero(::Type{CausalGraph}) = CausalGraph(0)
Graphs.one(::Type{CausalGraph}) = CausalGraph(1)

# Iteration support
function Base.iterate(g::CausalGraph, state=1)
    n = Graphs.nv(g)
    if state > n
        return nothing
    end
    return (state, state + 1)
end

Base.length(g::CausalGraph) = Graphs.nv(g)
Base.eltype(::Type{CausalGraph}) = Int

# Conversion
Base.convert(::Type{Graphs.DiGraph}, g::CausalGraph) = g.graph

export CausalGraph, set_prop!, get_prop, has_prop, delete_prop!,
       set_node_prop!, get_node_prop, has_node_prop, delete_node_prop!,
       set_edge_prop!, get_edge_prop, has_edge_prop, delete_edge_prop!,
       get_node_names, get_node_name,
       attach_data!, get_data, has_data
