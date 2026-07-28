# Import Graphs functions
using Graphs: inneighbors

"""
    find_backdoor_paths(g, X, Y; max_paths=10_000)

Find all backdoor paths from X to Y.

A backdoor path is a path that starts with an edge pointing into X.

# Arguments
- `g`: Directed acyclic graph
- `X`: Source node
- `Y`: Target node
- `max_paths`: Cap on enumerated paths (raises if exceeded)

# Returns
- Vector of backdoor paths (each path is a vector of nodes)
"""
function find_backdoor_paths(g::AbstractGraph, X::Int, Y::Int; max_paths::Int = 10_000)
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end

    backdoor_paths = Vector{Vector{Int}}()
    parents_X = inneighbors(g, X)
    for parent in parents_X
        paths_from_parent = _all_simple_paths(g, parent, Y; max_paths = max_paths - length(backdoor_paths))
        for path in paths_from_parent
            push!(backdoor_paths, [X, path...])
            length(backdoor_paths) >= max_paths && throw(ArgumentError(
                "find_backdoor_paths exceeded max_paths=$max_paths between $X and $Y; use reachability helpers instead",
            ))
        end
    end
    return backdoor_paths
end

"""
    find_directed_paths(g, X, Y; max_paths=10_000)

Find all directed paths from X to Y (forward edges only).

Prefer [`nodes_on_directed_paths`](@ref) or [`has_path`](@ref) when only
membership / existence is needed — full enumeration is exponential on dense DAGs.
"""
function find_directed_paths(g::AbstractGraph, X::Int, Y::Int; max_paths::Int = 10_000)
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    return _all_simple_paths(g, X, Y; directed = true, max_paths = max_paths)
end

"""
    nodes_on_directed_paths(g, X, Y) -> Set{Int}

Nodes that lie on at least one directed path from `X` to `Y` (including endpoints).

On a DAG this is `({X} ∪ descendants(X)) ∩ ({Y} ∪ ancestors(Y))` restricted to
nodes reachable from `X` toward `Y` — computed via BFS, not path enumeration.
"""
function nodes_on_directed_paths(g::AbstractGraph, X::Int, Y::Int)
    if X < 1 || X > nv(g) || Y < 1 || Y > nv(g)
        throw(ArgumentError("Node indices X=$X and Y=$Y must be in range [1, $(nv(g))]. Graph has $(nv(g)) nodes."))
    end
    X == Y && return Set([X])
    forward = union(Set([X]), get_descendants(g, X))
    backward = union(Set([Y]), get_ancestors(g, Y))
    return intersect(forward, backward)
end

"""
    _has_directed_path(g, source, target; forbidden=Set{Int}()) -> Bool

BFS reachability along forward edges, skipping `forbidden` nodes (except that
`source` may be checked separately).
"""
function _has_directed_path(
    g::AbstractGraph,
    source::Int,
    target::Int;
    forbidden::Set{Int} = Set{Int}(),
)
    source == target && return source ∉ forbidden
    source in forbidden && return false
    queue = Int[source]
    visited = Set{Int}([source])
    while !isempty(queue)
        u = popfirst!(queue)
        for v in outneighbors(g, u)
            v in forbidden && continue
            v == target && return true
            if v ∉ visited
                push!(visited, v)
                push!(queue, v)
            end
        end
    end
    return false
end

"""
    _has_undirected_path(g, source, target; forbidden=Set{Int}()) -> Bool

BFS on the underlying undirected graph, skipping `forbidden` nodes.
"""
function _has_undirected_path(
    g::AbstractGraph,
    source::Int,
    target::Int;
    forbidden::Set{Int} = Set{Int}(),
)
    source == target && return source ∉ forbidden
    source in forbidden && return false
    queue = Int[source]
    visited = Set{Int}([source])
    while !isempty(queue)
        u = popfirst!(queue)
        for v in Iterators.flatten((outneighbors(g, u), inneighbors(g, u)))
            v in forbidden && continue
            v == target && return true
            if v ∉ visited
                push!(visited, v)
                push!(queue, v)
            end
        end
    end
    return false
end

"""
    _has_backdoor_path(g, X, Y; forbidden=Set{Int}()) -> Bool

True if a backdoor path `X ← ⋯ → Y` exists, without enumerating paths.
Optional `forbidden` nodes may not be traversed (and `X` is never re-entered).
"""
function _has_backdoor_path(
    g::AbstractGraph,
    X::Int,
    Y::Int;
    forbidden::Set{Int} = Set{Int}(),
)
    Y in forbidden && return false
    block = union(forbidden, Set([X]))
    for parent in inneighbors(g, X)
        parent in forbidden && continue
        parent == Y && return true
        _has_undirected_path(g, parent, Y; forbidden = block) && return true
    end
    return false
end

"""
    _all_simple_paths(g, source, target; directed=false, max_paths=10_000)

Find all simple paths from source to target.

When `directed=false` (default), traverses edges in both directions
(undirected paths, used for backdoor path finding).
When `directed=true`, only follows edge direction (used for directed path finding).

Raises `ArgumentError` if more than `max_paths` paths are found.
"""
function _all_simple_paths(
    g::AbstractGraph,
    source,
    target;
    directed::Bool = false,
    max_paths::Int = 10_000,
)
    paths = Vector{Vector{Int}}()
    current_path = Int[]
    visited = Set{Int}()

    function dfs(node)
        length(paths) >= max_paths && return
        push!(current_path, node)

        if node == target
            push!(paths, copy(current_path))
            pop!(current_path)
            return
        end

        push!(visited, node)

        for neighbor in outneighbors(g, node)
            if neighbor ∉ visited
                dfs(neighbor)
            end
        end

        if !directed
            for neighbor in Graphs.inneighbors(g, node)
                if neighbor ∉ visited
                    dfs(neighbor)
                end
            end
        end

        pop!(current_path)
        delete!(visited, node)
    end

    dfs(source)
    if length(paths) >= max_paths
        throw(ArgumentError(
            "_all_simple_paths exceeded max_paths=$max_paths from $source to $target; " *
            "use nodes_on_directed_paths / has_path / _has_backdoor_path instead",
        ))
    end
    return paths
end

export find_backdoor_paths, find_directed_paths, nodes_on_directed_paths
