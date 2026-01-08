"""
Graph visualization utilities for CausalDynamics.jl

Provides functions to visualize causal graphs with proper formatting,
node labels, and highlighting of paths or adjustment sets.

# Note
Visualization functions require GraphMakie.jl and CairoMakie.jl to be loaded.
These are optional dependencies. Load them with:
```julia
using GraphMakie, CairoMakie
```
"""

"""
    plot_causal_graph(g; node_labels, highlight_nodes, highlight_edges, kwargs...)

Plot a causal graph with optional node labels and highlighting.

# Arguments
- `g::AbstractGraph`: The causal graph to plot
- `node_labels::Vector{String}`: Optional labels for nodes (default: node indices)
- `highlight_nodes::Set{Int}`: Nodes to highlight (e.g., adjustment set)
- `highlight_edges::Vector{Tuple{Int, Int}}`: Edges to highlight (e.g., backdoor paths)
- `kwargs...`: Additional arguments passed to GraphMakie.graphplot

# Returns
- Figure object from GraphMakie

# Example
```julia
using CausalDynamics, Graphs, GraphMakie, CairoMakie

g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 1, 3)
add_edge!(g, 2, 3)

fig = plot_causal_graph(g; 
    node_labels = ["Z", "X", "Y"],
    highlight_nodes = Set([1])  # Highlight confounder
)
```

# Note
This function requires GraphMakie.jl and CairoMakie.jl to be loaded.
"""
function plot_causal_graph(g::AbstractGraph; 
    node_labels = nothing,
    highlight_nodes = Set{Int}(),
    highlight_edges = Tuple{Int, Int}[],
    kwargs...
)
    # Check if required packages are loaded (they should be in Main namespace)
    # This matches the book's usage pattern where packages are loaded explicitly
    if !isdefined(Main, :GraphMakie)
        error("GraphMakie.jl is required for visualization. Load it with: using GraphMakie")
    end
    if !isdefined(Main, :CairoMakie)
        error("CairoMakie.jl is required for visualization. Load it with: using CairoMakie")
    end
    
    GraphMakie = Main.GraphMakie
    CairoMakie = Main.CairoMakie
    
    # Default node labels (pre-allocate for type stability)
    if node_labels === nothing
        node_labels = Vector{String}(undef, nv(g))
        for i in 1:nv(g)
            node_labels[i] = string(i)
        end
    end
    
    # Determine node colors (pre-allocate for type stability)
    node_colors = Vector{Symbol}(undef, nv(g))
    for i in 1:nv(g)
        node_colors[i] = i in highlight_nodes ? :red : :lightblue
    end
    
    # Determine edge colors and widths
    edge_colors = String[]
    edge_widths = Float64[]
    for edge in Graphs.edges(g)
        src, dst = Graphs.src(edge), Graphs.dst(edge)
        is_highlighted = (src, dst) in highlight_edges || (dst, src) in highlight_edges
        push!(edge_colors, is_highlighted ? "red" : "black")
        push!(edge_widths, is_highlighted ? 3.0 : 1.0)
    end
    
    # Create figure and plot
    fig = CairoMakie.Figure()
    ax = CairoMakie.Axis(fig[1, 1])
    
    # Use GraphMakie to plot
    gp = GraphMakie.graphplot!(ax, g;
        node_color = node_colors,
        edge_color = edge_colors,
        edge_width = edge_widths,
        node_size = 20,
        arrow_size = 15,
        nlabels = node_labels,
        kwargs...
    )
    
    return fig
end

"""
    plot_with_adjustment_set(g, X, Y, Z; node_labels, kwargs...)

Plot a causal graph highlighting an adjustment set.

# Arguments
- `g::AbstractGraph`: The causal graph
- `X::Int`: Treatment node
- `Y::Int`: Outcome node
- `Z::Vector{Int}`: Adjustment set nodes
- `node_labels::Vector{String}`: Optional node labels
- `kwargs...`: Additional arguments for plotting

# Returns
- Figure object

# Example
```julia
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

fig = plot_with_adjustment_set(g, 2, 3, [1]; 
    node_labels = ["Z", "X", "Y"]
)
```
"""
function plot_with_adjustment_set(g::AbstractGraph, X::Int, Y::Int, Z::Vector{Int};
    node_labels = nothing,
    kwargs...
)
    highlight_nodes = Set([X, Y, Z...])
    # Pre-allocate highlight edges
    highlight_edges = Vector{Tuple{Int, Int}}()
    for z in Z
        if has_edge(g, z, X)
            push!(highlight_edges, (z, X))
        end
        if has_edge(g, z, Y)
            push!(highlight_edges, (z, Y))
        end
    end
    
    return plot_causal_graph(g;
        node_labels = node_labels,
        highlight_nodes = highlight_nodes,
        highlight_edges = highlight_edges,
        kwargs...
    )
end

"""
    plot_backdoor_paths(g, X, Y; node_labels, kwargs...)

Plot a causal graph highlighting backdoor paths from X to Y.

# Arguments
- `g::AbstractGraph`: The causal graph
- `X::Int`: Treatment node
- `Y::Int`: Outcome node
- `node_labels::Vector{String}`: Optional node labels
- `kwargs...`: Additional arguments for plotting

# Returns
- Figure object
"""
function plot_backdoor_paths(g::AbstractGraph, X::Int, Y::Int;
    node_labels = nothing,
    kwargs...
)
    # Find backdoor paths
    backdoor_paths = find_backdoor_paths(g, X, Y)
    
    # Extract edges from paths
    highlight_edges = Tuple{Int, Int}[]
    for path in backdoor_paths
        for i in 1:(length(path) - 1)
            push!(highlight_edges, (path[i], path[i+1]))
        end
    end
    
    highlight_nodes = Set([X, Y])
    for path in backdoor_paths
        union!(highlight_nodes, path)
    end
    
    return plot_causal_graph(g;
        node_labels = node_labels,
        highlight_nodes = highlight_nodes,
        highlight_edges = highlight_edges,
        kwargs...
    )
end

# Export visualization functions
export plot_causal_graph, plot_with_adjustment_set, plot_backdoor_paths
