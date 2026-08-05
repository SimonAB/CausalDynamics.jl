"""
    MinimalMediatorSets{T}

Result of [`find_minimal_mediator_sets`](@ref).

# Fields
- `sets`: Inclusion-minimal mediator sets, sorted by `(length, sorted members)`
- `status`:
  - `:ok` — `sets` holds the cuts (possibly empty only in degenerate cases)
  - `:no_path` — no directed path from treatment to outcome
  - `:uncuttable_direct_edge` — a direct treatment→outcome edge cannot be cut by mediators
  - `:uncuttable` — a residual directed path avoids every path-mediator candidate

Iterates over `sets` (so `collect(result)` and `Set(result)` still work).
"""
struct MinimalMediatorSets{T}
    sets::Vector{Set{T}}
    status::Symbol
end

Base.length(r::MinimalMediatorSets) = length(r.sets)
Base.isempty(r::MinimalMediatorSets) = isempty(r.sets)
Base.iterate(r::MinimalMediatorSets, state...) = iterate(r.sets, state...)
Base.getindex(r::MinimalMediatorSets, i) = r.sets[i]
Base.eltype(::Type{MinimalMediatorSets{T}}) where {T} = Set{T}
Base.keys(r::MinimalMediatorSets) = keys(r.sets)

function Base.show(io::IO, r::MinimalMediatorSets)
    print(io, "MinimalMediatorSets(status=$(r.status), n=$(length(r.sets)))")
end

"""
    intercepts_all_directed_paths(g, treatment, outcome, S) -> Bool

Return `true` if mediator set `S` intercepts every directed path from
`treatment` to `outcome` (no directed route avoids every node in `S`).
Endpoints are never forbidden. Same criterion used by
[`find_minimal_mediator_sets`](@ref).
"""
function intercepts_all_directed_paths(g::AbstractGraph, treatment::Int, outcome::Int, S)
    validate_causal_graph(g)
    check_node_indices!(g, treatment, outcome; names = ("treatment", "outcome"))
    S_set = S isa Set{Int} ? S : Set{Int}(S)
    for m in S_set
        check_node_index!(g, m; label = "Mediator")
    end
    treatment == outcome && return true
    return !_has_directed_path(g, treatment, outcome; forbidden = S_set)
end

"""
    find_path_mediators(g, treatment, outcome) -> Set{Int}

Structural mediator candidates between `treatment` and `outcome`: nodes that lie
on at least one **proper** directed path `treatment → ⋯ → outcome`
(excluding the endpoints).

On a DAG this is

```julia
intersect(get_descendants(g, treatment), get_ancestors(g, outcome))
```

This is **not** the frontdoor criterion. For single-node sets that satisfy the
frontdoor criterion, use [`find_frontdoor_mediators`](@ref).

# Arguments
- `g`: Directed acyclic graph
- `treatment`: Treatment node index
- `outcome`: Outcome node index

# Returns
- `Set{Int}` of mediator candidate indices

# Examples

```julia
using CausalDynamics, Graphs

# Nodes: A=1, M1=2, M2=3, M3=4, Y=5, C=6, D=7
# A → M1 → M2 → Y; A → M3 → Y; C → A; C → Y; A → D
g = DiGraph(7)
add_edge!(g, 1, 2); add_edge!(g, 2, 3); add_edge!(g, 3, 5)
add_edge!(g, 1, 4); add_edge!(g, 4, 5)
add_edge!(g, 6, 1); add_edge!(g, 6, 5)
add_edge!(g, 1, 7)

find_path_mediators(g, 1, 5)  # Set([2, 3, 4]) == {M1, M2, M3}
```
"""
function find_path_mediators(g::AbstractGraph, treatment::Int, outcome::Int)
    validate_causal_graph(g)

    check_node_indices!(g, treatment, outcome; names = ("treatment", "outcome"))

    # Equivalent to nodes_on_directed_paths without endpoints.
    return intersect(get_descendants(g, treatment), get_ancestors(g, outcome))
end

"""
    find_path_mediators(g, treatment, outcome; node_names) -> Set

As [`find_path_mediators`](@ref) with `Int` indices, but `treatment` / `outcome`
may be `Symbol`s when `node_names` maps indices to names (same conventions as
[`identify`](@ref)).

Returns a `Set{Symbol}` when `node_names` is provided, otherwise `Set{Int}`.
"""
function find_path_mediators(
    g::AbstractGraph,
    treatment,
    outcome;
    node_names = nothing,
)
    names = _normalize_node_names(node_names, nv(g))
    t = treatment isa Int ?
        _node_index(g, treatment) :
        _node_index(g, treatment, names)
    y = outcome isa Int ?
        _node_index(g, outcome) :
        _node_index(g, outcome, names)
    idx = find_path_mediators(g, t, y)
    names === nothing && return idx
    return Set(names[i] for i in idx if haskey(names, i))
end

"""
    find_minimal_mediator_sets(g, treatment, outcome; max_candidates=20) -> MinimalMediatorSets{Int}

Inclusion-minimal sets of mediators that **intercept every directed path**
`treatment → ⋯ → outcome`.

A set ``S`` intercepts all directed paths when
[`intercepts_all_directed_paths`](@ref) `(g, treatment, outcome, S)` is true.
Equivalently, ``S`` is a hitting set for the intermediate nodes of every
directed path.

Returns a [`MinimalMediatorSets`](@ref) with:

- `sets`: all inclusion-minimal cuts, sorted by `(length, sorted members)`
- `status`: `:ok`, `:no_path`, `:uncuttable_direct_edge`, or `:uncuttable`

Uses directed reachability (BFS with forbidden nodes), not full path enumeration.
Candidate nodes are [`find_path_mediators`](@ref). Enumeration of subsets is
exponential in the number of candidates; `max_candidates` caps that search.

This is **not** the frontdoor criterion — see [`find_frontdoor_mediators`](@ref).
Nor does it choose mediators for [`MediationQuery`](@ref); pass a chosen set
explicitly after inspecting `.sets`.

# Examples

```julia
using CausalDynamics, Graphs

# Sequential: A → M1 → M2 → Y
g = DiGraph(4)
add_edge!(g, 1, 2); add_edge!(g, 2, 3); add_edge!(g, 3, 4)
r = find_minimal_mediator_sets(g, 1, 4)
r.status  # :ok
r.sets    # [Set([2]), Set([3])]

# Parallel: A → M1 → Y and A → M2 → Y
g = DiGraph(4)
add_edge!(g, 1, 2); add_edge!(g, 2, 4)
add_edge!(g, 1, 3); add_edge!(g, 3, 4)
find_minimal_mediator_sets(g, 1, 4).sets  # [Set([2, 3])]

# Mixed: A → M1 → M3 → Y and A → M2 → M3 → Y
g = DiGraph(5)
add_edge!(g, 1, 2); add_edge!(g, 2, 4); add_edge!(g, 4, 5)
add_edge!(g, 1, 3); add_edge!(g, 3, 4)
find_minimal_mediator_sets(g, 1, 5).sets  # [Set([4]), Set([2, 3])]
```
"""
function find_minimal_mediator_sets(
    g::AbstractGraph,
    treatment::Int,
    outcome::Int;
    max_candidates::Int = 20,
)
    validate_causal_graph(g)

    check_node_indices!(g, treatment, outcome; names = ("treatment", "outcome"))
    max_candidates < 0 && throw(ArgumentError("max_candidates must be non-negative"))

    treatment == outcome && return MinimalMediatorSets{Int}(Set{Int}[], :no_path)

    if !_has_directed_path(g, treatment, outcome)
        return MinimalMediatorSets{Int}(Set{Int}[], :no_path)
    end
    if has_edge(g, treatment, outcome)
        return MinimalMediatorSets{Int}(Set{Int}[], :uncuttable_direct_edge)
    end

    candidates = sort!(collect(find_path_mediators(g, treatment, outcome)))
    isempty(candidates) && return MinimalMediatorSets{Int}(Set{Int}[], :uncuttable)

    if length(candidates) > max_candidates
        throw(ArgumentError(
            "find_minimal_mediator_sets: $(length(candidates)) mediator candidates " *
            "exceeds max_candidates=$max_candidates; raise the limit or reduce the graph.",
        ))
    end

    if _has_directed_path(g, treatment, outcome; forbidden = Set(candidates))
        return MinimalMediatorSets{Int}(Set{Int}[], :uncuttable)
    end

    minimal = Set{Int}[]
    for k in 1:length(candidates)
        for comb in _mediator_index_combinations(candidates, k)
            S = Set(comb)
            any(m -> issubset(m, S), minimal) && continue
            if intercepts_all_directed_paths(g, treatment, outcome, S)
                push!(minimal, S)
            end
        end
    end
    sort!(minimal; by = _mediator_set_sort_key)
    return MinimalMediatorSets{Int}(minimal, :ok)
end

"""
    find_minimal_mediator_sets(g, treatment, outcome; node_names, max_candidates=20)

As [`find_minimal_mediator_sets`](@ref) with `Int` indices. With `node_names`,
returns `MinimalMediatorSets{Symbol}`.
"""
function find_minimal_mediator_sets(
    g::AbstractGraph,
    treatment,
    outcome;
    node_names = nothing,
    max_candidates::Int = 20,
)
    names = _normalize_node_names(node_names, nv(g))
    t = treatment isa Int ?
        _node_index(g, treatment) :
        _node_index(g, treatment, names)
    y = outcome isa Int ?
        _node_index(g, outcome) :
        _node_index(g, outcome, names)
    idx = find_minimal_mediator_sets(g, t, y; max_candidates = max_candidates)
    names === nothing && return idx
    named_sets = [Set(names[i] for i in S if haskey(names, i)) for S in idx.sets]
    sort!(named_sets; by = _mediator_set_sort_key)
    return MinimalMediatorSets{Symbol}(named_sets, idx.status)
end

"""Sort key for stable mediator-set order: shorter first, then sorted members."""
function _mediator_set_sort_key(S::Set)
    return (length(S), sort!(collect(S)))
end

"""
Unordered combinations of length `k` from `xs` (no Combinatorics.jl dependency).
"""
function _mediator_index_combinations(xs::Vector{Int}, k::Integer)
    n = length(xs)
    k < 0 && throw(ArgumentError("k must be non-negative"))
    k > n && return Vector{Vector{Int}}()
    k == 0 && return [Int[]]
    result = Vector{Vector{Int}}()
    chosen = Int[]
    function rec(start::Int)
        if length(chosen) == k
            push!(result, copy(chosen))
            return
        end
        for i in start:n
            remaining_needed = k - length(chosen)
            remaining_available = n - i + 1
            remaining_available < remaining_needed && break
            push!(chosen, xs[i])
            rec(i + 1)
            pop!(chosen)
        end
    end
    rec(1)
    return result
end

export find_path_mediators, find_minimal_mediator_sets, MinimalMediatorSets
export intercepts_all_directed_paths
