"""Sensitivity analysis over valid adjustment sets."""

"""
    identification_report(g, treatment, outcome; node_names=nothing) -> Vector{NamedTuple}

Enumerate candidate adjustment sets and mark which satisfy the backdoor criterion.
Returns a vector of named tuples (no DataFrames dependency).
"""
function identification_report(
    g::AbstractGraph,
    treatment::Int,
    outcome::Int;
    node_names = nothing,
)
    X, Y = treatment, outcome
    _node_index(g, X)
    _node_index(g, Y)
    names = _normalize_node_names(node_names, nv(g))
    minimal = backdoor_adjustment_set(g, X, Y)
    candidates = find_all_adjustment_sets(g, X, Y)
    rows = NamedTuple{(:set, :valid, :minimal, :size), Tuple{Vector{Any}, Bool, Bool, Int}}[]
    min_set = minimal === nothing ? Set{Int}() : minimal
    for cand in candidates
        valid = is_valid_adjustment_set(g, X, Y, cand)
        is_min = cand == min_set
        labels = _labels_from_indices(Set(cand), names)
        push!(rows, (set = labels, valid = valid, minimal = is_min, size = length(cand)))
    end
    return rows
end

export identification_report
