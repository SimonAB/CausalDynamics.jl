"""
    create_causal_graph(edges)

Create a causal graph from a list of edges.

Convenience function to create a validated DAG from edge specifications.
Automatically determines graph size and validates that the result is a DAG.

# Arguments
- `edges`: Edge specification, either:
  - `Vector{Tuple{Int, Int}}`: List of (source, target) tuples
  - `Dict{Int, Vector{Int}}`: Dictionary mapping source nodes to vectors of target nodes

# Returns
- `DiGraph`: Validated directed acyclic graph

# Examples

```julia
using CausalDynamics

# From edge list: Z → X, Z → Y, X → Y
edges = [(1, 2), (1, 3), (2, 3)]
g = create_causal_graph(edges)

# From dictionary (same graph)
edge_dict = Dict(
    1 => [2, 3],  # Z → X, Z → Y
    2 => [3]      # X → Y
)
g = create_causal_graph(edge_dict)
```

# Throws
- `ArgumentError`: If the resulting graph is not a DAG (contains cycles)

# Notes
- Automatically determines number of nodes from edge specifications
- Validates that graph is acyclic before returning
- Node indices start at 1

# See Also
- `validate_causal_graph`: Validate that a graph is a DAG
- `is_dag`: Check if a graph is acyclic
"""
function create_causal_graph(edges::Union{Vector{Tuple{Int, Int}}, Dict{Int, Vector{Int}}})
    if edges isa Dict
        # Convert dictionary to edge list
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
    g = Graphs.DiGraph(max_node)
    for (src, tgt) in edges
        Graphs.add_edge!(g, src, tgt)
    end
    
    # Validate (available from validation.jl)
    validate_causal_graph(g)
    
    return g
end

export create_causal_graph
