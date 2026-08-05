"""
    find_all_adjustment_sets(g, X, Y)

List valid backdoor adjustment sets via `CausalInference.list_backdoor_adjustment`.
"""
function find_all_adjustment_sets(g::AbstractGraph, X::Int, Y::Int)
    validate_causal_graph(g)
    check_node_indices!(g, X, Y)

    return [Set{Int}(z) for z in CausalInference.list_backdoor_adjustment(g, X, Y)]
end

"""
    is_valid_adjustment_set(g, X, Y, Z)

Check if `Z` is a valid backdoor adjustment set via CausalInference.
"""
function is_valid_adjustment_set(g::AbstractGraph, X::Int, Y::Int, Z::Set)
    check_node_indices!(g, X, Y)

    descendants_X = get_descendants(g, X)
    if X ∈ Z || Y ∈ Z || !isempty(intersect(Z, descendants_X))
        return false
    end

    return CausalInference.alt_test_backdoor(g, X, Y, Z)
end

"""
    minimal_adjustment_set(g, X, Y)

Minimal backdoor adjustment set (same as `backdoor_adjustment_set`).
"""
function minimal_adjustment_set(g::AbstractGraph, X::Int, Y::Int)
    return backdoor_adjustment_set(g, X, Y)
end

export find_all_adjustment_sets, is_valid_adjustment_set, minimal_adjustment_set
