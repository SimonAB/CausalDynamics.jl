# Hypergraph implementation for higher-order causal interactions
# 
# A hypergraph extends a graph with hyperedges that can connect multiple vertices
# simultaneously, enabling representation of group interactions in causal systems.

export Hypergraph, HyperedgeData
export add_hyperedge!, rem_hyperedge!, hyperedge_vertices, incident_hyperedges
export num_hyperedges, num_vertices, hyperedges, to_simple_graph

"""
    HyperedgeData

A hyperedge connecting multiple vertices simultaneously.

Unlike edges (which connect exactly 2 vertices), hyperedges can connect any number
of vertices, representing group interactions where all members interact simultaneously.

# Fields
- `id::Int`: Unique identifier for this hyperedge
- `vertices::Set{Int}`: Set of vertex IDs in this hyperedge
"""
struct HyperedgeData
    id::Int
    vertices::Set{Int}
end

"""
    Hypergraph

A hypergraph with vertices, edges, and hyperedges for modeling higher-order
causal interactions.

In causal modeling, hypergraphs are useful for representing:
- **Group interventions**: Multiple variables affected simultaneously
- **Multi-way interactions**: Causal effects that involve more than two variables
- **Collective behaviour**: Agents interacting in groups

# Fields
- `graph::SimpleDiGraph`: The underlying directed graph for pairwise edges
- `hyperedges::Dict{Int, HyperedgeData}`: Hyperedges (id => HyperedgeData)
- `next_hyperedge_id::Int`: Next available hyperedge ID
- `vertex_to_hyperedges::Dict{Int, Set{Int}}`: Index: vertex -> set of hyperedge IDs

# Constructors

    Hypergraph(n::Int=0)

Create a hypergraph with `n` vertices and no edges or hyperedges.

    Hypergraph(g::SimpleDiGraph)

Create a hypergraph from an existing directed graph, preserving its edges.

# Examples

```julia
using CausalDynamics

# Create a hypergraph with 5 vertices
hg = Hypergraph(5)

# Add pairwise edges (using Graphs.jl functions)
add_edge!(hg, 1, 2)  # X → Y
add_edge!(hg, 2, 3)  # Y → Z

# Add a hyperedge representing a group interaction
# e.g., a meeting where agents 1, 2, 3 all interact
meeting = add_hyperedge!(hg, [1, 2, 3])

# Query the structure
num_vertices(hg)      # 5
num_hyperedges(hg)    # 1
hyperedge_vertices(hg, meeting)  # Set([1, 2, 3])

# Find all hyperedges containing vertex 2
incident_hyperedges(hg, 2)  # Set([meeting])

# Remove a hyperedge (intervention: ban the meeting)
rem_hyperedge!(hg, meeting)
```

# See Also
- `add_hyperedge!`: Add a hyperedge
- `rem_hyperedge!`: Remove a hyperedge
- `hyperedge_vertices`: Get vertices in a hyperedge
- `incident_hyperedges`: Get hyperedges containing a vertex
"""
mutable struct Hypergraph
    graph::SimpleDiGraph{Int}
    hyperedges::Dict{Int, HyperedgeData}
    next_hyperedge_id::Int
    vertex_to_hyperedges::Dict{Int, Set{Int}}
    
    function Hypergraph(n::Int=0)
        g = SimpleDiGraph(n)
        vertex_to_hyperedges = Dict{Int, Set{Int}}(v => Set{Int}() for v in 1:n)
        new(g, Dict{Int, HyperedgeData}(), 1, vertex_to_hyperedges)
    end
    
    function Hypergraph(g::SimpleDiGraph)
        n = Graphs.nv(g)
        vertex_to_hyperedges = Dict{Int, Set{Int}}(v => Set{Int}() for v in 1:n)
        new(g, Dict{Int, HyperedgeData}(), 1, vertex_to_hyperedges)
    end
end

# Forward common Graphs.jl functions to the underlying graph
Graphs.nv(hg::Hypergraph) = Graphs.nv(hg.graph)
Graphs.ne(hg::Hypergraph) = Graphs.ne(hg.graph)
Graphs.vertices(hg::Hypergraph) = Graphs.vertices(hg.graph)
Graphs.edges(hg::Hypergraph) = Graphs.edges(hg.graph)
Graphs.inneighbors(hg::Hypergraph, v::Int) = Graphs.inneighbors(hg.graph, v)
Graphs.outneighbors(hg::Hypergraph, v::Int) = Graphs.outneighbors(hg.graph, v)
Graphs.has_edge(hg::Hypergraph, s::Int, t::Int) = Graphs.has_edge(hg.graph, s, t)
Graphs.add_edge!(hg::Hypergraph, s::Int, t::Int) = Graphs.add_edge!(hg.graph, s, t)
Graphs.add_vertex!(hg::Hypergraph) = begin
    result = Graphs.add_vertex!(hg.graph)
    if result
        v = Graphs.nv(hg.graph)
        hg.vertex_to_hyperedges[v] = Set{Int}()
    end
    result
end
Graphs.add_vertices!(hg::Hypergraph, n::Int) = begin
    old_nv = Graphs.nv(hg.graph)
    result = Graphs.add_vertices!(hg.graph, n)
    for v in (old_nv + 1):Graphs.nv(hg.graph)
        hg.vertex_to_hyperedges[v] = Set{Int}()
    end
    result
end

"""
    num_vertices(hg::Hypergraph) -> Int

Return the number of vertices in the hypergraph.
"""
num_vertices(hg::Hypergraph) = Graphs.nv(hg)

"""
    num_hyperedges(hg::Hypergraph) -> Int

Return the number of hyperedges in the hypergraph.
"""
num_hyperedges(hg::Hypergraph) = length(hg.hyperedges)

"""
    hyperedges(hg::Hypergraph)

Return an iterator over all hyperedges in the hypergraph.
"""
hyperedges(hg::Hypergraph) = values(hg.hyperedges)

"""
    add_hyperedge!(hg::Hypergraph, vertex_ids) -> Int

Add a hyperedge connecting multiple vertices. Returns the hyperedge ID.

A hyperedge represents a group interaction where all vertices interact simultaneously.
Unlike edges (which are pairwise), hyperedges can connect any number of vertices.

# Arguments
- `hg::Hypergraph`: The hypergraph to modify
- `vertex_ids`: Collection of vertex IDs (Vector, Set, or Tuple)

# Returns
- `Int`: The ID of the newly created hyperedge

# Examples
```julia
hg = Hypergraph(5)

# Group meeting with agents 1, 2, 3
meeting_id = add_hyperedge!(hg, [1, 2, 3])

# Coalition of agents 2, 4, 5
coalition_id = add_hyperedge!(hg, Set([2, 4, 5]))
```
"""
function add_hyperedge!(hg::Hypergraph, vertex_ids::Union{Set{Int}, Vector{Int}, Tuple, AbstractVector})
    vertices_set = Set{Int}(vertex_ids)
    
    n = Graphs.nv(hg)
    for v in vertices_set
        if v < 1 || v > n
            throw(ArgumentError("Vertex $v out of range [1, $n]"))
        end
    end
    
    id = hg.next_hyperedge_id
    hg.hyperedges[id] = HyperedgeData(id, vertices_set)
    hg.next_hyperedge_id += 1
    
    # Update index
    for v in vertices_set
        push!(hg.vertex_to_hyperedges[v], id)
    end
    
    return id
end

"""
    rem_hyperedge!(hg::Hypergraph, id::Int)

Remove a hyperedge by its ID.

This represents an intervention on the hypergraph structure: \$do(H \\leftarrow H^*)\$
where we modify the set of group interactions.

# Examples
```julia
hg = Hypergraph(5)
meeting = add_hyperedge!(hg, [1, 2, 3])

# Intervention: ban the meeting
rem_hyperedge!(hg, meeting)
```
"""
function rem_hyperedge!(hg::Hypergraph, id::Int)
    if haskey(hg.hyperedges, id)
        # Update index
        for v in hg.hyperedges[id].vertices
            delete!(hg.vertex_to_hyperedges[v], id)
        end
        delete!(hg.hyperedges, id)
    end
end

"""
    hyperedge_vertices(hg::Hypergraph, id::Int) -> Set{Int}

Return the set of vertices in the specified hyperedge.

# Examples
```julia
hg = Hypergraph(5)
meeting = add_hyperedge!(hg, [1, 2, 3])
hyperedge_vertices(hg, meeting)  # Set([1, 2, 3])
```
"""
function hyperedge_vertices(hg::Hypergraph, id::Int)
    if !haskey(hg.hyperedges, id)
        throw(KeyError("Hyperedge $id not found"))
    end
    return hg.hyperedges[id].vertices
end

"""
    incident_hyperedges(hg::Hypergraph, v::Int) -> Set{Int}

Return the set of hyperedge IDs that contain vertex `v`.

This is useful for finding all group interactions that a particular vertex
(e.g., an agent) participates in.

# Examples
```julia
hg = Hypergraph(5)
meeting1 = add_hyperedge!(hg, [1, 2, 3])  # Agent 2 in meeting 1
meeting2 = add_hyperedge!(hg, [2, 4, 5])  # Agent 2 in meeting 2

incident_hyperedges(hg, 2)  # Set([meeting1, meeting2])
incident_hyperedges(hg, 1)  # Set([meeting1])
```
"""
function incident_hyperedges(hg::Hypergraph, v::Int)
    n = Graphs.nv(hg)
    if v < 1 || v > n
        throw(ArgumentError("Vertex $v out of range [1, $n]"))
    end
    return hg.vertex_to_hyperedges[v]
end

"""
    to_simple_graph(hg::Hypergraph) -> SimpleDiGraph

Return the underlying directed graph (pairwise edges only).

This is useful for applying standard graph algorithms that don't support hyperedges.
"""
to_simple_graph(hg::Hypergraph) = hg.graph

# Pretty printing
function Base.show(io::IO, hg::Hypergraph)
    print(io, "Hypergraph(vertices=$(Graphs.nv(hg)), edges=$(Graphs.ne(hg)), hyperedges=$(num_hyperedges(hg)))")
end

function Base.show(io::IO, ::MIME"text/plain", hg::Hypergraph)
    println(io, "Hypergraph:")
    println(io, "  Vertices: $(Graphs.nv(hg))")
    println(io, "  Edges: $(Graphs.ne(hg))")
    println(io, "  Hyperedges: $(num_hyperedges(hg))")
    if num_hyperedges(hg) > 0 && num_hyperedges(hg) <= 10
        println(io, "  Hyperedge details:")
        for he in hyperedges(hg)
            println(io, "    $(he.id) → $(sort(collect(he.vertices)))")
        end
    end
end
