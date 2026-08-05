"""
    backdoor_adjustment_set(g, X, Y)

Find a valid backdoor adjustment set for estimating the causal effect of `X` on `Y`.

Delegates to `CausalInference.find_min_backdoor_adjustment`. Returns `nothing` if
no valid set exists (`false` from CausalInference).

# Arguments
- `g`: Directed acyclic graph
- `X`: Treatment node
- `Y`: Outcome node

# Returns
- `Set{Int}` of adjustment nodes (possibly empty if no backdoors), or `nothing`
"""
function backdoor_adjustment_set(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    adj = CausalInference.find_min_backdoor_adjustment(g, X, Y)
    adj === false && return nothing
    return Set{Int}(adj)
end

"""
    is_backdoor_adjustable(g, X, Y)

Return `true` if a backdoor adjustment set exists (including the empty set when
there are no backdoor paths).
"""
function is_backdoor_adjustable(g::AbstractGraph, X::Int, Y::Int)
    return backdoor_adjustment_set(g, X, Y) !== nothing
end

export backdoor_adjustment_set, is_backdoor_adjustable
