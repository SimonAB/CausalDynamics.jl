"""
Time-indexed (lagged) causal graphs for discrete-time CDMs.

A [`TemporalDAGSpec`](@ref) describes time-invariant edges with integer lags.
[`unroll_temporal_dag`](@ref) expands this to a static DAG over occasions
`t = 1:T` so standard identification APIs (`d_separated`, `backdoor_adjustment_set`)
apply to dynamical confounding.
"""

"""
    LaggedEdge(parent, child, lag)

Directed edge from `parent` at occasion `t - lag` to `child` at occasion `t`.

`lag == 0` is contemporaneous (same occasion). `lag ≥ 1` is a lagged parent.
"""
struct LaggedEdge
    parent::Symbol
    child::Symbol
    lag::Int
end

function LaggedEdge((parent, child, lag)::Tuple{Symbol, Symbol, Int})
    return LaggedEdge(parent, child, lag)
end

"""
    TemporalDAGSpec(variables, edges)

Time-invariant lag structure over named endogenous variables.

# Arguments
- `variables`: symbols appearing in the model (documentation / validation)
- `edges`: vector of [`LaggedEdge`](@ref) or `(parent, child, lag)` tuples
"""
struct TemporalDAGSpec
    variables::Vector{Symbol}
    edges::Vector{LaggedEdge}
end

_as_lagged_edge(e::LaggedEdge) = e
_as_lagged_edge(e::Tuple{Symbol, Symbol, <:Integer}) = LaggedEdge(e[1], e[2], Int(e[3]))
_as_lagged_edge(e) = throw(ArgumentError(
    "edge must be a LaggedEdge or (parent::Symbol, child::Symbol, lag::Int) tuple, got $(typeof(e))",
))

function TemporalDAGSpec(variables::AbstractVector{Symbol}, edges::AbstractVector)
    return TemporalDAGSpec(
        collect(Symbol, variables),
        LaggedEdge[_as_lagged_edge(e) for e in edges],
    )
end

"""
    TemporalUnrolling

Result of unrolling a [`TemporalDAGSpec`](@ref) for `T` occasions.

# Fields
- `T`: number of occasions
- `spec`: source specification
- `graph`: unrolled `DiGraph`
- `node_index`: `(variable, t) => node id`
- `index_node`: node id `=> (variable, t)` (1-based indexing)
"""
struct TemporalUnrolling
    T::Int
    spec::TemporalDAGSpec
    graph::Graphs.DiGraph
    node_index::Dict{Tuple{Symbol, Int}, Int}
    index_node::Vector{Tuple{Symbol, Int}}
end

"""
    temporal_node(unrolling, variable, t)

Return the node index for `variable` at occasion `t` in `unrolling`.
"""
function temporal_node(unrolling::TemporalUnrolling, variable::Symbol, t::Int)
    haskey(unrolling.node_index, (variable, t)) ||
        throw(ArgumentError("no node for :$variable at t=$t in unrolling with T=$(unrolling.T)"))
    return unrolling.node_index[(variable, t)]
end

"""
    temporal_node_label(unrolling, node)

Human-readable label `"var[t]"` for a node index in `unrolling`.
"""
function temporal_node_label(unrolling::TemporalUnrolling, node::Int)
    var, t = unrolling.index_node[node]
    return string(var, "[", t, "]")
end

function _validate_lagged_edge(edge::LaggedEdge, variables::Vector{Symbol})
    edge.lag < 0 && throw(ArgumentError("lag must be ≥ 0, got $(edge.lag) for $(edge.parent)→$(edge.child)"))
    edge.parent in variables || throw(ArgumentError("unknown parent :$(edge.parent) in lagged edge"))
    edge.child in variables || throw(ArgumentError("unknown child :$(edge.child) in lagged edge"))
    return nothing
end

"""
    unroll_temporal_dag(spec::TemporalDAGSpec, T::Int)

Unroll `spec` to a static DAG over occasions `t = 1:T`.

Edges `(parent, child, lag)` become `parent[t-lag] → child[t]` for each valid `t`.
"""
function unroll_temporal_dag(spec::TemporalDAGSpec, T::Integer)
    T = Int(T)
    T < 1 && throw(ArgumentError("T must be ≥ 1, got $T"))

    for e in spec.edges
        _validate_lagged_edge(e, spec.variables)
    end

    node_index = Dict{Tuple{Symbol, Int}, Int}()
    index_node = Tuple{Symbol, Int}[]
    for t in 1:T, v in spec.variables
        push!(index_node, (v, t))
        node_index[(v, t)] = length(index_node)
    end

    g = Graphs.DiGraph(length(index_node))
    for t in 1:T, e in spec.edges
        t_src = t - e.lag
        t_src < 1 && continue
        src = node_index[(e.parent, t_src)]
        dst = node_index[(e.child, t)]
        Graphs.add_edge!(g, src, dst)
    end

    return TemporalUnrolling(T, spec, g, node_index, index_node)
end

"""
    d_separated_temporal(unrolling, treatment, t_treat, outcome, t_outcome, conditioned)

`d_separated` on the unrolled graph for `(treatment, t_treat)` and `(outcome, t_outcome)`.
`conditioned` is a vector of `(variable, t)` pairs.
"""
function d_separated_temporal(
    unrolling::TemporalUnrolling,
    treatment::Symbol,
    t_treat::Int,
    outcome::Symbol,
    t_outcome::Int,
    conditioned::AbstractVector{<:Tuple{Symbol, Int}},
)
  X = temporal_node(unrolling, treatment, t_treat)
  Y = temporal_node(unrolling, outcome, t_outcome)
  Z = Int[temporal_node(unrolling, v, t) for (v, t) in conditioned]
  return d_separated(unrolling.graph, X, Y, Z)
end

"""
    temporal_backdoor_adjustment_set(unrolling, treatment, t_treat, outcome, t_outcome)

Backdoor adjustment set for the effect of `treatment` at `t_treat` on `outcome` at `t_outcome`
in the unrolled DAG. Returns a `Set` of node indices into `unrolling.graph`.
"""
function temporal_backdoor_adjustment_set(
    unrolling::TemporalUnrolling,
    treatment::Symbol,
    t_treat::Int,
    outcome::Symbol,
    t_outcome::Int,
)
    X = temporal_node(unrolling, treatment, t_treat)
    Y = temporal_node(unrolling, outcome, t_outcome)
    return backdoor_adjustment_set(unrolling.graph, X, Y)
end

"""
    temporal_backdoor_adjustment_nodes(unrolling, treatment, t_treat, outcome, t_outcome)

Like [`temporal_backdoor_adjustment_set`](@ref) but returns `Set` of `(variable, t)` pairs.
"""
function temporal_backdoor_adjustment_nodes(
    unrolling::TemporalUnrolling,
    treatment::Symbol,
    t_treat::Int,
    outcome::Symbol,
    t_outcome::Int,
)
    adj = temporal_backdoor_adjustment_set(unrolling, treatment, t_treat, outcome, t_outcome)
    adj === nothing && return nothing
    return Set(unrolling.index_node[i] for i in adj)
end

export LaggedEdge, TemporalDAGSpec, TemporalUnrolling
export unroll_temporal_dag, temporal_node, temporal_node_label
export d_separated_temporal, temporal_backdoor_adjustment_set, temporal_backdoor_adjustment_nodes
