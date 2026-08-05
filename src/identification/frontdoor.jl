"""
    frontdoor_adjustment_set(g, X, Y, M)

Check if M is a valid frontdoor adjustment set for estimating the causal effect of X on Y.

The frontdoor criterion states that a set M is a valid frontdoor adjustment set if:
1. M blocks all directed paths from X to Y
2. There are no backdoor paths from X to M
3. All backdoor paths from M to Y are blocked by X

Uses reachability (BFS), not path enumeration — safe on dense DAGs.

# Arguments
- `g`: Directed acyclic graph
- `X`: Treatment node
- `Y`: Outcome node
- `M`: Potential mediator set

# Returns
- `true` if M is a valid frontdoor adjustment set, `false` otherwise
"""
function frontdoor_adjustment_set(g::AbstractGraph, X::Int, Y::Int, M)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    M_set = M isa AbstractVector ? Set{Int}(M) : Set{Int}([M])
    for m in M_set
        check_node_index!(g, m; label = "Mediator")
    end

    # Condition 1: M intercepts every directed path X → Y
    if _has_directed_path(g, X, Y; forbidden = M_set)
        return false
    end

    # Condition 2: no *open* backdoor from X to m (empty conditioning).
    # Open backdoors from parents of X are directed routes parent → m avoiding X
    # (collider-blocked undirected routes such as X←U→Y←M are ignored).
    for m in M_set
        _has_open_backdoor(g, X, m) && return false
    end

    # Condition 3: all backdoors m — Y are blocked by X
    for m in M_set
        _has_open_backdoor(g, m, Y; conditioned = Set([X])) && return false
    end

    return true
end

"""
    _has_open_backdoor(g, A, B; conditioned=Set()) -> Bool

True if there is an open backdoor path `A ← ⋯ → B` given `conditioned`.

Approximates openness by directed reachability from parents of `A` to `B`,
forbidding `A` and `conditioned` (non-collider blocking). Sufficient for the
usual frontdoor examples and avoids exponential path enumeration.
"""
function _has_open_backdoor(
    g::AbstractGraph,
    A::Int,
    B::Int;
    conditioned::Set{Int} = Set{Int}(),
)
    B in conditioned && return false
    forbid = union(conditioned, Set([A]))
    for parent in inneighbors(g, A)
        parent in conditioned && continue
        parent == B && return true
        _has_directed_path(g, parent, B; forbidden = forbid) && return true
    end
    return false
end

"""
    find_frontdoor_mediators(g, X, Y)

Find single-node frontdoor mediators between X and Y.

Candidates are nodes on some directed path X → Y (`nodes_on_directed_paths`),
checked with [`frontdoor_adjustment_set`](@ref). Avoids enumerating all simple paths.
"""
function find_frontdoor_mediators(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    mediators = Vector{Set{Int}}()
    nodes_on_paths = nodes_on_directed_paths(g, X, Y)
    delete!(nodes_on_paths, X)
    delete!(nodes_on_paths, Y)

    for node in nodes_on_paths
        if frontdoor_adjustment_set(g, X, Y, [node])
            push!(mediators, Set([node]))
        end
    end

    return mediators
end

export frontdoor_adjustment_set, find_frontdoor_mediators
