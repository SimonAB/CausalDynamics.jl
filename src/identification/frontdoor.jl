"""
    _mediator_set(M) -> Set{Int}

Normalise a frontdoor candidate set `M` (scalar, vector, or set).
"""
function _mediator_set(M)
    if M isa AbstractSet
        return Set{Int}(M)
    elseif M isa AbstractVector
        return Set{Int}(M)
    else
        return Set{Int}([M])
    end
end

"""
    frontdoor_adjustment_set(g, X, Y, M) -> Bool

Return `true` when `M` is a valid frontdoor adjustment set for the effect of `X` on
`Y`.

Delegates to
[`CausalInference.find_frontdoor_adjustment`](https://mschauer.github.io/CausalInference.jl/latest/)
with ``I = R = M`` (exact-set check). Uses the general frontdoor search of
[Wienöbst et al. (2024)](https://arxiv.org/abs/2211.16468) via CausalInference
`gensearch` (see also van der Zander et al., 2019 for backdoor listing).
"""
function frontdoor_adjustment_set(g::AbstractGraph, X::Int, Y::Int, M)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    M_set = _mediator_set(M)
    for m in M_set
        check_node_index!(g, m; label = "Mediator")
    end

    result = CausalInference.find_frontdoor_adjustment(
        g,
        Set([X]),
        Set([Y]),
        M_set,
        M_set,
    )
    return result !== false && result == M_set
end

"""
    find_frontdoor_adjustment_set(g, X, Y)

Find a frontdoor adjustment set for the effect of `X` on `Y`.

Delegates to
[`CausalInference.find_frontdoor_adjustment`](https://mschauer.github.io/CausalInference.jl/latest/).
Returns `nothing` when no valid set exists (`false` from CausalInference).
"""
function find_frontdoor_adjustment_set(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    adj = CausalInference.find_frontdoor_adjustment(g, Set([X]), Set([Y]))
    adj === false && return nothing
    return Set{Int}(adj)
end

"""
    find_min_frontdoor_adjustment_set(g, X, Y)

Find an inclusion-minimal frontdoor adjustment set, or `nothing` if none exists.

Delegates to
[`CausalInference.find_min_frontdoor_adjustment`](https://mschauer.github.io/CausalInference.jl/latest/).
"""
function find_min_frontdoor_adjustment_set(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    adj = CausalInference.find_min_frontdoor_adjustment(g, Set([X]), Set([Y]))
    adj === false && return nothing
    return Set{Int}(adj)
end

"""
    list_frontdoor_adjustment_sets(g, X, Y)

List all frontdoor adjustment sets for the effect of `X` on `Y`.

Delegates to
[`CausalInference.list_frontdoor_adjustment`](https://mschauer.github.io/CausalInference.jl/latest/).
This can materialise exponentially many sets on dense graphs; prefer
[`find_frontdoor_adjustment_set`](@ref), [`find_min_frontdoor_adjustment_set`](@ref),
or [`find_frontdoor_mediators`](@ref) when a single set or singleton mediators
suffice.
"""
function list_frontdoor_adjustment_sets(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    return [
        Set{Int}(z) for z in CausalInference.list_frontdoor_adjustment(g, Set([X]), Set([Y]))
    ]
end

"""
    find_frontdoor_mediators(g, X, Y)

Return singleton frontdoor adjustment sets between `X` and `Y`.

Each returned set has the form `Set([m])` for a node `m` that is a valid
frontdoor adjustment set on its own (typical textbook mediator between `X`
and `Y`). Validates each candidate with
[`frontdoor_adjustment_set`](@ref) rather than enumerating all frontdoor sets.
"""
function find_frontdoor_mediators(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    X_set = Set([X])
    Y_set = Set([Y])
    candidates = setdiff(Set(vertices(g)), union(X_set, Y_set))
    mediators = Set{Int}[]
    for m in candidates
        M = Set([m])
        result = CausalInference.find_frontdoor_adjustment(g, X_set, Y_set, M, M)
        if result !== false && result == M
            push!(mediators, M)
        end
    end
    return mediators
end

export frontdoor_adjustment_set,
    find_frontdoor_adjustment_set,
    find_min_frontdoor_adjustment_set,
    list_frontdoor_adjustment_sets,
    find_frontdoor_mediators
