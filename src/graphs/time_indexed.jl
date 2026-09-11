"""
Time-indexed causal graphs for discrete-time causal dynamical models.

`TemporalDAGSpec` separates occasion-indexed variables from enduring entity
attributes. `unroll_temporal_dag` expands the specification over occasions
`t = 0:T`, while retaining each enduring variable as one graph node.
"""

"""
    LaggedEdge(parent, child, lag)

Directed edge from `parent` at the occasion `child_time - lag` to `child`.

For an enduring child, `child_time` is its `onset_time`; for an enduring
parent, the edge is emitted to every active occasion of the child.
"""
struct LaggedEdge
    parent::Symbol
    child::Symbol
    lag::Int
end

LaggedEdge((parent, child, lag)::Tuple{Symbol, Symbol, Int}) = LaggedEdge(parent, child, lag)

"""
    TemporalNodeSpec(name; temporal_mode=:occasion, causal_role=nothing, onset_time=0)

Describe one variable in a [`TemporalDAGSpec`](@ref).

`temporal_mode` is either `:occasion` or `:enduring`. Occasion variables have
one node at every active time; enduring variables have one node whose value is
available from `onset_time` onwards. `causal_role` is descriptive metadata and
does not affect identification.
"""
struct TemporalNodeSpec
    name::Symbol
    temporal_mode::Symbol
    causal_role::Union{Nothing, Symbol}
    onset_time::Int

    function TemporalNodeSpec(
        name::Symbol,
        temporal_mode::Symbol,
        causal_role::Union{Nothing, Symbol},
        onset_time::Int,
    )
        temporal_mode in (:occasion, :enduring) || throw(ArgumentError(
            "temporal_mode must be :occasion or :enduring, got :$temporal_mode",
        ))
        onset_time ≥ 0 || throw(ArgumentError("onset_time must be ≥ 0, got $onset_time"))
        return new(name, temporal_mode, causal_role, onset_time)
    end
end

function TemporalNodeSpec(
    name::Symbol;
    temporal_mode::Symbol = :occasion,
    causal_role::Union{Nothing, Symbol} = nothing,
    onset_time::Integer = 0,
)
    return TemporalNodeSpec(name, temporal_mode, causal_role, Int(onset_time))
end

"""
    TemporalDAGSpec(; entity, nodes, edges)

Time-invariant temporal graph specification over [`TemporalNodeSpec`](@ref)s.

`entity` is an optional display label. Every node must have a unique name.
"""
struct TemporalDAGSpec
    entity::Union{Nothing, Symbol}
    nodes::Vector{TemporalNodeSpec}
    edges::Vector{LaggedEdge}

    function TemporalDAGSpec(
        entity::Union{Nothing, Symbol},
        nodes::Vector{TemporalNodeSpec},
        edges::Vector{LaggedEdge},
    )
        names = getfield.(nodes, :name)
        length(unique(names)) == length(names) || throw(ArgumentError(
            "TemporalDAGSpec node names must be unique",
        ))
        return new(entity, nodes, edges)
    end
end

function _as_lagged_edge(e::LaggedEdge)
    return e
end

function _as_lagged_edge(e::Tuple{Symbol, Symbol, <:Integer})
    return LaggedEdge(e[1], e[2], Int(e[3]))
end

function _as_lagged_edge(e)
    throw(ArgumentError(
        "edge must be a LaggedEdge or (parent::Symbol, child::Symbol, lag::Int) tuple, got $(typeof(e))",
    ))
end

function TemporalDAGSpec(
    ; entity::Union{Nothing, Symbol} = nothing,
    nodes::AbstractVector{<:TemporalNodeSpec},
    edges::AbstractVector = Any[],
)
    return TemporalDAGSpec(
        entity,
        collect(TemporalNodeSpec, nodes),
        LaggedEdge[_as_lagged_edge(edge) for edge in edges],
    )
end

"""Construct an all-occasion specification from the pre-descriptor form."""
function TemporalDAGSpec(variables::AbstractVector{Symbol}, edges::AbstractVector)
    return TemporalDAGSpec(
        nodes = [TemporalNodeSpec(variable) for variable in variables],
        edges = edges,
    )
end

function Base.getproperty(spec::TemporalDAGSpec, property::Symbol)
    property === :variables && return _temporal_node_names(spec)
    return getfield(spec, property)
end

function Base.propertynames(spec::TemporalDAGSpec, private::Bool = false)
    fields = fieldnames(typeof(spec))
    return private ? (fields..., :variables) : (fields..., :variables)
end

"""Return the node descriptor named `name`, or throw an informative error."""
function _temporal_node_spec(spec::TemporalDAGSpec, name::Symbol)
    for node in spec.nodes
        node.name == name && return node
    end
    throw(ArgumentError("unknown temporal node :$name"))
end

"""Return the names declared by a temporal specification."""
_temporal_node_names(spec::TemporalDAGSpec) = Symbol[node.name for node in spec.nodes]

"""Return whether a descriptor is active at occasion `t`."""
_active_at(node::TemporalNodeSpec, t::Int) = t ≥ node.onset_time

"""Result of unrolling a [`TemporalDAGSpec`](@ref) over occasions `0:T`."""
struct TemporalUnrolling
    T::Int
    spec::TemporalDAGSpec
    graph::Graphs.DiGraph
    node_index::Dict{Tuple{Symbol, Union{Nothing, Int}}, Int}
    index_node::Vector{Tuple{Symbol, Union{Nothing, Int}}}
end

"""Return the node index for an enduring variable."""
function enduring_node(unrolling::TemporalUnrolling, variable::Symbol)
    descriptor = _temporal_node_spec(unrolling.spec, variable)
    descriptor.temporal_mode == :enduring || throw(ArgumentError(
        ":$variable is an occasion node, not an enduring node",
    ))
    return unrolling.node_index[(variable, nothing)]
end

"""
    temporal_node(unrolling, variable, t)

Return the node for `variable` at occasion `t`. Enduring variables resolve to
their single node once active at `t`.
"""
function temporal_node(unrolling::TemporalUnrolling, variable::Symbol, t::Int)
    0 ≤ t ≤ unrolling.T || throw(ArgumentError(
        "occasion t=$t is outside unrolling range 0:$(unrolling.T)",
    ))
    descriptor = _temporal_node_spec(unrolling.spec, variable)
    _active_at(descriptor, t) || throw(ArgumentError(
        ":$variable is not active at t=$t; onset_time=$(descriptor.onset_time)",
    ))
    key = descriptor.temporal_mode == :enduring ? (variable, nothing) : (variable, t)
    haskey(unrolling.node_index, key) || throw(ArgumentError(
        "no node for :$variable at t=$t in unrolling with T=$(unrolling.T)",
    ))
    return unrolling.node_index[key]
end

"""Return a human-readable label for an unrolled node index."""
function temporal_node_label(unrolling::TemporalUnrolling, node::Int)
    variable, time = unrolling.index_node[node]
    return time === nothing ? string(variable) : string(variable, "[", time, "]")
end

function _validate_lagged_edge(edge::LaggedEdge, spec::TemporalDAGSpec)
    edge.lag < 0 && throw(ArgumentError(
        "lag must be ≥ 0, got $(edge.lag) for $(edge.parent)→$(edge.child)",
    ))
    parent = _temporal_node_spec(spec, edge.parent)
    child = _temporal_node_spec(spec, edge.child)
    if child.temporal_mode == :enduring && parent.temporal_mode == :enduring &&
       parent.onset_time > child.onset_time
        throw(ArgumentError(
            "enduring parent :$(edge.parent) is not active when enduring child :$(edge.child) starts",
        ))
    end
    return parent, child
end

function _add_temporal_edge!(graph, node_index, parent_key, child_key)
    Graphs.add_edge!(graph, node_index[parent_key], node_index[child_key])
end

"""
    unroll_temporal_dag(spec, T)

Unroll `spec` over occasions `t = 0:T`.

Enduring variables contribute one node. An occasion-to-enduring edge is an
assignment into persistence: with enduring child onset `a`, lag `ℓ` connects
`parent[a - ℓ]` to the enduring node.
"""
function unroll_temporal_dag(spec::TemporalDAGSpec, T::Integer)
    T = Int(T)
    T ≥ 0 || throw(ArgumentError("T must be ≥ 0, got $T"))
    for node in spec.nodes
        node.onset_time ≤ T || throw(ArgumentError(
            "onset_time $(node.onset_time) for :$(node.name) exceeds unrolling horizon T=$T",
        ))
    end
    validated_edges = [(_validate_lagged_edge(edge, spec), edge) for edge in spec.edges]

    node_index = Dict{Tuple{Symbol, Union{Nothing, Int}}, Int}()
    index_node = Tuple{Symbol, Union{Nothing, Int}}[]
    for descriptor in spec.nodes
        if descriptor.temporal_mode == :enduring
            key = (descriptor.name, nothing)
            push!(index_node, key)
            node_index[key] = length(index_node)
        else
            for t in descriptor.onset_time:T
                key = (descriptor.name, t)
                push!(index_node, key)
                node_index[key] = length(index_node)
            end
        end
    end

    graph = Graphs.DiGraph(length(index_node))
    for ((parent, child), edge) in validated_edges
        if child.temporal_mode == :enduring
            if parent.temporal_mode == :enduring
                _add_temporal_edge!(
                    graph, node_index,
                    (parent.name, nothing), (child.name, nothing),
                )
            else
                source_time = child.onset_time - edge.lag
                source_time ≥ parent.onset_time || throw(ArgumentError(
                    "edge :$(edge.parent) → :$(edge.child) requires unavailable parent occasion t=$source_time",
                ))
                _add_temporal_edge!(
                    graph, node_index,
                    (parent.name, source_time), (child.name, nothing),
                )
            end
        else
            for target_time in child.onset_time:T
                target_key = (child.name, target_time)
                parent_key = if parent.temporal_mode == :enduring
                    parent.onset_time ≤ target_time || continue
                    (parent.name, nothing)
                else
                    source_time = target_time - edge.lag
                    source_time ≥ parent.onset_time || continue
                    (parent.name, source_time)
                end
                _add_temporal_edge!(graph, node_index, parent_key, target_key)
            end
        end
    end

    is_dag(graph) || throw(ArgumentError("unrolled temporal graph must be acyclic"))
    return TemporalUnrolling(T, spec, graph, node_index, index_node)
end

"""Apply d-separation to two nodes in an unrolled temporal graph."""
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
    Z = Int[temporal_node(unrolling, variable, time) for (variable, time) in conditioned]
    return d_separated(unrolling.graph, X, Y, Z)
end

"""Return a backdoor adjustment set of node indices for a temporal query."""
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

"""Return a temporal backdoor adjustment set as `(variable, time)` pairs."""
function temporal_backdoor_adjustment_nodes(
    unrolling::TemporalUnrolling,
    treatment::Symbol,
    t_treat::Int,
    outcome::Symbol,
    t_outcome::Int,
)
    adjustment = temporal_backdoor_adjustment_set(
        unrolling, treatment, t_treat, outcome, t_outcome,
    )
    adjustment === nothing && return nothing
    return Set(unrolling.index_node[index] for index in adjustment)
end

"""
    temporal_edge_role(unrolling, parent, child) -> Symbol

Classify an edge in a temporal unrolling as `:constitutive` when its child is
an enduring node, `:recurrent_influence` when an enduring node points to an
occasion, or `:occasion_influence` otherwise. The classification is derived
from temporal identity and does not alter the graph used for identification.
"""
function temporal_edge_role(unrolling::TemporalUnrolling, parent::Integer, child::Integer)
    1 ≤ parent ≤ length(unrolling.index_node) || throw(BoundsError(unrolling.index_node, parent))
    1 ≤ child ≤ length(unrolling.index_node) || throw(BoundsError(unrolling.index_node, child))
    parent_time = unrolling.index_node[parent][2]
    child_time = unrolling.index_node[child][2]
    child_time === nothing && return :constitutive
    parent_time === nothing && return :recurrent_influence
    return :occasion_influence
end

"""
    temporal_edge_records(unrolling) -> Vector{NamedTuple}

Return serialisable provenance records for every edge in a temporal
unrolling. Each record contains the source and target temporal keys and the
derived role returned by [`temporal_edge_role`](@ref).
"""
function temporal_edge_records(unrolling::TemporalUnrolling)
    return [
        (
            parent = unrolling.index_node[Graphs.src(edge)],
            child = unrolling.index_node[Graphs.dst(edge)],
            role = temporal_edge_role(unrolling, Graphs.src(edge), Graphs.dst(edge)),
        ) for edge in Graphs.edges(unrolling.graph)
    ]
end

export LaggedEdge, TemporalNodeSpec, TemporalDAGSpec, TemporalUnrolling
export unroll_temporal_dag, temporal_node, enduring_node, temporal_node_label
export d_separated_temporal, temporal_backdoor_adjustment_set, temporal_backdoor_adjustment_nodes
export temporal_edge_role, temporal_edge_records
