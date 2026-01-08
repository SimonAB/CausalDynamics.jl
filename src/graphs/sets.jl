# Import Graphs functions
using Graphs: inneighbors, outneighbors

"""
    get_ancestors(g, nodes)

Get the set of all ancestors of the given nodes.

An ancestor of node X is any node that has a directed path to X.

# Arguments
- `g`: Directed acyclic graph
- `nodes`: Node or set of nodes

# Returns
- Set of ancestor nodes

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 3)  # X → Z
add_edge!(g, 2, 3)  # Y → Z
add_edge!(g, 3, 4)  # Z → W

ancestors = get_ancestors(g, 4)  # {1, 2, 3}
```
"""
function get_ancestors(g::AbstractGraph, nodes)
    node_set = nodes isa AbstractVector ? Set(nodes) : Set([nodes])
    ancestors = Set{Int}()
    
    for node in node_set
        # Use BFS to find all ancestors
        queue = [node]
        visited = Set{Int}([node])
        
        while !isempty(queue)
            current = popfirst!(queue)
            
            for parent in inneighbors(g, current)
                if parent ∉ visited
                    push!(visited, parent)
                    push!(ancestors, parent)
                    push!(queue, parent)
                end
            end
        end
    end
    
    return ancestors
end

"""
    get_descendants(g, nodes)

Get the set of all descendants of the given nodes.

A descendant of node X is any node that has a directed path from X.

# Arguments
- `g`: Directed acyclic graph
- `nodes`: Node or set of nodes

# Returns
- Set of descendant nodes

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 2)  # X → Y
add_edge!(g, 1, 3)  # X → Z
add_edge!(g, 2, 4)  # Y → W

descendants = get_descendants(g, 1)  # {2, 3, 4}
```
"""
function get_descendants(g::AbstractGraph, nodes)
    node_set = nodes isa AbstractVector ? Set(nodes) : Set([nodes])
    descendants = Set{Int}()
    
    for node in node_set
        # Use BFS to find all descendants
        queue = [node]
        visited = Set{Int}([node])
        
        while !isempty(queue)
            current = popfirst!(queue)
            
            for child in outneighbors(g, current)
                if child ∉ visited
                    push!(visited, child)
                    push!(descendants, child)
                    push!(queue, child)
                end
            end
        end
    end
    
    return descendants
end

"""
    get_parents(g, nodes)

Get the set of parents of the given nodes.

A parent of node X is a node with a direct edge pointing into X.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `nodes`: Node (Int) or collection of nodes (Vector/Set)

# Returns
- `Set{Int}`: Set of parent nodes

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 3)  # X → Z
add_edge!(g, 2, 3)  # Y → Z
add_edge!(g, 3, 4)  # Z → W

parents = get_parents(g, 3)  # {1, 2}
```
"""
function get_parents(g::AbstractGraph, nodes)
    node_set = nodes isa AbstractVector ? Set(nodes) : Set([nodes])
    parents = Set{Int}()
    
    for node in node_set
        for parent in inneighbors(g, node)
            push!(parents, parent)
        end
    end
    
    return parents
end

"""
    get_children(g, nodes)

Get the set of children of the given nodes.

A child of node X is a node with a direct edge pointing from X.

# Arguments
- `g::AbstractGraph`: Directed acyclic graph
- `nodes`: Node (Int) or collection of nodes (Vector/Set)

# Returns
- `Set{Int}`: Set of child nodes

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 2)  # X → Y
add_edge!(g, 1, 3)  # X → Z
add_edge!(g, 2, 4)  # Y → W

children = get_children(g, 1)  # {2, 3}
```
"""
function get_children(g::AbstractGraph, nodes)
    node_set = nodes isa AbstractVector ? Set(nodes) : Set([nodes])
    children = Set{Int}()
    
    for node in node_set
        for child in outneighbors(g, node)
            push!(children, child)
        end
    end
    
    return children
end

"""
    markov_boundary(g, Y)

Compute the Markov boundary of node Y.

The Markov boundary of Y is the minimal set that d-separates Y from all other nodes.
It consists of: parents of Y, children of Y, and parents of children of Y.

# Arguments
- `g`: Directed acyclic graph
- `Y`: Target node

# Returns
- Set of nodes in the Markov boundary

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(4)
add_edge!(g, 1, 2)  # X → Y
add_edge!(g, 3, 2)  # Z → Y
add_edge!(g, 2, 4)  # Y → W
add_edge!(g, 5, 4)  # V → W

mb = markov_boundary(g, 2)  # {1, 3, 4, 5}
# Parents: {1, 3}
# Children: {4}
# Parents of children: {5}
```
"""
function markov_boundary(g::AbstractGraph, Y::Int)
    # Validate node index
    if Y < 1 || Y > nv(g)
        throw(ArgumentError("Node index Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    
    mb = Set{Int}()
    
    # Add parents of Y
    parents_Y = get_parents(g, Y)
    union!(mb, parents_Y)
    
    # Add children of Y
    children_Y = get_children(g, Y)
    union!(mb, children_Y)
    
    # Add parents of children of Y
    for child in children_Y
        parents_child = get_parents(g, child)
        union!(mb, parents_child)
    end
    
    # Remove Y itself
    delete!(mb, Y)
    
    return mb
end

# Export functions
export get_ancestors, get_descendants, get_parents, get_children, markov_boundary
