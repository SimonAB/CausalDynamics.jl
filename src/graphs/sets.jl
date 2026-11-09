# Import Graphs functions
using Graphs: inneighbors, outneighbors

"""
    _node_set(nodes) -> Set{Int}

Normalise a single node or a collection of nodes to a `Set{Int}`.
"""
_node_set(nodes::Integer) = Set{Int}([nodes])
_node_set(nodes) = Set{Int}(nodes)

"""
    _reachable_set(g, nodes, step) -> Set{Int}

Collect every node reached from any of `nodes` by repeatedly following `step`
(`inneighbors` for ancestors, `outneighbors` for descendants).

Each seed is traversed independently, so a seed that is reachable from another
seed is itself included in the result.
"""
function _reachable_set(g::AbstractGraph, nodes, step::F) where {F}
    reached = Set{Int}()
    queue = Int[]
    for seed in _node_set(nodes)
        empty!(queue)
        push!(queue, seed)
        visited = Set{Int}([seed])
        while !isempty(queue)
            current = popfirst!(queue)
            for next in step(g, current)
                if next ∉ visited
                    push!(visited, next)
                    push!(reached, next)
                    push!(queue, next)
                end
            end
        end
    end
    return reached
end

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
get_ancestors(g::AbstractGraph, nodes) = _reachable_set(g, nodes, inneighbors)

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
get_descendants(g::AbstractGraph, nodes) = _reachable_set(g, nodes, outneighbors)

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
    parents = Set{Int}()
    for node in _node_set(nodes)
        union!(parents, inneighbors(g, node))
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
    children = Set{Int}()
    for node in _node_set(nodes)
        union!(children, outneighbors(g, node))
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
