"""
Time-indexed causal graphs for discrete-time causal dynamical models.

`unroll_temporal_dag` expands a [`TemporalDAGSpec`](@ref) over ``t = 0:T``.
Node multiplicity follows [`TemporalSupport`](@ref) and [`GraphKind`](@ref),
not `ontological_character` or deprecated `temporal_mode`.
"""

"""
    LaggedEdge(parent, child, lag; relation_kind=:causal_influence)

Directed edge from `parent` at `child_time - lag` to `child`.

For a single-node child, `child_time` is its onset; for a single-node parent,
the edge is emitted to every active time of the child.
"""
struct LaggedEdge
    parent::Symbol
    child::Symbol
    lag::Int
    relation_kind::Symbol
end

function LaggedEdge(
    parent::Symbol,
    child::Symbol,
    lag::Integer;
    relation_kind::Symbol = :causal_influence,
)
    return LaggedEdge(parent, child, Int(lag), normalise_relation_kind(relation_kind))
end

LaggedEdge((parent, child, lag)::Tuple{Symbol, Symbol, Int}) =
    LaggedEdge(parent, child, lag)

"""
    TemporalNodeSpec(name; kwargs...)

Describe one variable in a [`TemporalDAGSpec`](@ref).

Declare [`temporal_support`](@ref TemporalSupport) and
`value_representation`. Deprecated `temporal_mode = :occasion | :enduring`
only selects a support pattern and does **not** set
`ontological_character`.
"""
struct TemporalNodeSpec
    name::Symbol
    temporal_mode::Symbol
    causal_role::Union{Nothing, Symbol}
    onset_time::Int
    temporal_support::TemporalSupport
    value_representation::Symbol
    referent_id::Union{Nothing, Symbol}
    identity_criterion::Union{Nothing, Symbol}
    ontological_character::Symbol

    function TemporalNodeSpec(
        name::Symbol,
        temporal_mode::Symbol,
        causal_role::Union{Nothing, Symbol},
        onset_time::Int,
        temporal_support::TemporalSupport,
        value_representation::Symbol,
        referent_id::Union{Nothing, Symbol},
        identity_criterion::Union{Nothing, Symbol},
        ontological_character::Symbol,
    )
        onset_time ≥ 0 || throw(ArgumentError("onset_time must be ≥ 0, got $onset_time"))
        if identity_criterion !== nothing && referent_id === nothing
            throw(ArgumentError("identity_criterion requires referent_id"))
        end
        if ontological_character === :enduring && identity_criterion === nothing
            # metadata only; warn is deferred to require_semantics on gated ops
        end
        return new(
            name,
            temporal_mode,
            causal_role,
            onset_time,
            temporal_support,
            value_representation,
            referent_id,
            identity_criterion,
            ontological_character,
        )
    end
end

function TemporalNodeSpec(
    name::Symbol;
    temporal_mode::Union{Nothing, Symbol} = nothing,
    causal_role::Union{Nothing, Symbol} = nothing,
    onset_time::Integer = 0,
    temporal_support = nothing,
    value_representation::Symbol = :unspecified,
    referent_id::Union{Nothing, Symbol} = nothing,
    referent::Union{Nothing, ReferentSpec} = nothing,
    identity_criterion::Union{Nothing, Symbol} = nothing,
    ontological_character::Symbol = :unspecified,
)
    onset = Int(onset_time)
    if referent !== nothing
        referent_id = referent.id
        identity_criterion = something(identity_criterion, referent.identity_criterion)
    end
    support = if temporal_support !== nothing
        parse_temporal_support(temporal_support; onset = onset)
    elseif temporal_mode !== nothing
        temporal_mode === :occasion || temporal_mode === :enduring ||
            throw(ArgumentError("temporal_mode must be :occasion or :enduring, got :$temporal_mode"))
        Base.depwarn(
            "TemporalNodeSpec(...; temporal_mode=:$temporal_mode) is deprecated; " *
            "declare temporal_support instead. The flag does not set ontological_character.",
            :TemporalNodeSpec,
        )
        support_from_temporal_mode(temporal_mode, onset)
    else
        PointwiseSupport()
    end
    if support isa FromOnsetSupport
        onset = Int(support.onset)
    end
    mode = legacy_temporal_mode(support)
    return TemporalNodeSpec(
        name,
        mode,
        causal_role,
        onset,
        support,
        normalise_value_representation(value_representation),
        referent_id,
        identity_criterion,
        normalise_ontological_character(ontological_character),
    )
end

"""Return whether this descriptor unrolls to one reused node."""
is_single_node(node::TemporalNodeSpec) = is_single_node_support(node.temporal_support)

"""
    TemporalDAGSpec(; entity, nodes, edges, graph_kind=TimeUnrolledGraph())

Time-invariant temporal graph specification over [`TemporalNodeSpec`](@ref)s.

`entity` is an optional display label. Every node must have a unique name.
`graph_kind` defaults to [`TimeUnrolledGraph`](@ref); process and semantic
graphs are not automatically valid for d-separation or adjustment.
"""
struct TemporalDAGSpec
    entity::Union{Nothing, Symbol}
    nodes::Vector{TemporalNodeSpec}
    edges::Vector{LaggedEdge}
    graph_kind::GraphKind

    function TemporalDAGSpec(
        entity::Union{Nothing, Symbol},
        nodes::Vector{TemporalNodeSpec},
        edges::Vector{LaggedEdge},
        graph_kind::GraphKind = TimeUnrolledGraph(),
    )
        names = getfield.(nodes, :name)
        length(unique(names)) == length(names) || throw(ArgumentError(
            "TemporalDAGSpec node names must be unique",
        ))
        return new(entity, nodes, edges, graph_kind)
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
    graph_kind::GraphKind = TimeUnrolledGraph(),
)
    return TemporalDAGSpec(
        entity,
        collect(TemporalNodeSpec, nodes),
        LaggedEdge[_as_lagged_edge(edge) for edge in edges],
        graph_kind,
    )
end

"""Construct a pointwise-unrolled specification from the pre-descriptor form."""
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

"""Return the node index for a single-node (non-pointwise) variable."""
function enduring_node(unrolling::TemporalUnrolling, variable::Symbol)
    descriptor = _temporal_node_spec(unrolling.spec, variable)
    is_single_node(descriptor) || throw(ArgumentError(
        ":$variable expands pointwise; it has no single reused node",
    ))
    return unrolling.node_index[(variable, nothing)]
end

"""
    temporal_node(unrolling, variable, t)

Return the node for `variable` at time `t`. Single-node supports resolve to
their reused node once active at `t`.
"""
function temporal_node(unrolling::TemporalUnrolling, variable::Symbol, t::Int)
    0 ≤ t ≤ unrolling.T || throw(ArgumentError(
        "time t=$t is outside unrolling range 0:$(unrolling.T)",
    ))
    descriptor = _temporal_node_spec(unrolling.spec, variable)
    _active_at(descriptor, t) || throw(ArgumentError(
        ":$variable is not active at t=$t; onset_time=$(descriptor.onset_time)",
    ))
    key = is_single_node(descriptor) ? (variable, nothing) : (variable, t)
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
    if is_single_node(child) && is_single_node(parent) &&
       parent.onset_time > child.onset_time
        throw(ArgumentError(
            "single-node parent :$(edge.parent) is not active when child :$(edge.child) starts",
        ))
    end
    return parent, child
end

function _add_temporal_edge!(graph, node_index, parent_key, child_key)
    Graphs.add_edge!(graph, node_index[parent_key], node_index[child_key])
end

"""
    unroll_temporal_dag(spec, T)

Unroll `spec` over times `t = 0:T` under [`TimeUnrolledGraph`](@ref).

Single-node supports (`FromOnsetSupport`, `GlobalSupport`, …) contribute one
node. A pointwise-to-single-node edge is an assignment into persistence: with
child onset `a`, lag `ℓ` connects `parent[a - ℓ]` to the reused child node.
"""
function unroll_temporal_dag(spec::TemporalDAGSpec, T::Integer)
    T = Int(T)
    T ≥ 0 || throw(ArgumentError("T must be ≥ 0, got $T"))
    spec.graph_kind isa TimeUnrolledGraph || throw(ArgumentError(
        "unroll_temporal_dag requires TimeUnrolledGraph; got $(typeof(spec.graph_kind))",
    ))
    for node in spec.nodes
        node.onset_time ≤ T || throw(ArgumentError(
            "onset_time $(node.onset_time) for :$(node.name) exceeds unrolling horizon T=$T",
        ))
    end
    validated_edges = [(_validate_lagged_edge(edge, spec), edge) for edge in spec.edges]

    node_index = Dict{Tuple{Symbol, Union{Nothing, Int}}, Int}()
    index_node = Tuple{Symbol, Union{Nothing, Int}}[]
    for descriptor in spec.nodes
        if is_single_node(descriptor)
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
        if is_single_node(child)
            if is_single_node(parent)
                _add_temporal_edge!(
                    graph, node_index,
                    (parent.name, nothing), (child.name, nothing),
                )
            else
                source_time = child.onset_time - edge.lag
                source_time ≥ parent.onset_time || throw(ArgumentError(
                    "edge :$(edge.parent) → :$(edge.child) requires unavailable parent time t=$source_time",
                ))
                _add_temporal_edge!(
                    graph, node_index,
                    (parent.name, source_time), (child.name, nothing),
                )
            end
        else
            for target_time in child.onset_time:T
                target_key = (child.name, target_time)
                parent_key = if is_single_node(parent)
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

Classify an edge in a temporal unrolling:

- `:constitutive` — pointwise parent assigns into a single-node child
  (compatibility alias for `:constitutive_persistence`)
- `:recurrent_influence` — single-node parent influences a pointwise child
- `:occasion_influence` — pointwise to pointwise
- `:causal_influence` — single-node to single-node (or other non-constitutive cases)

Derived roles do not alter the unrolled topology used for display.
"""
function temporal_edge_role(unrolling::TemporalUnrolling, parent::Integer, child::Integer)
    1 ≤ parent ≤ length(unrolling.index_node) || throw(BoundsError(unrolling.index_node, parent))
    1 ≤ child ≤ length(unrolling.index_node) || throw(BoundsError(unrolling.index_node, child))
    parent_time = unrolling.index_node[parent][2]
    child_time = unrolling.index_node[child][2]
    if child_time === nothing && parent_time !== nothing
        return :constitutive
    elseif parent_time === nothing && child_time !== nothing
        return :recurrent_influence
    elseif parent_time === nothing && child_time === nothing
        return :causal_influence
    end
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

"""Look up the declared `relation_kind` for an unrolled edge's variable pair."""
function _declared_relation_kind(unrolling::TemporalUnrolling, parent::Integer, child::Integer)
    parent_var = unrolling.index_node[parent][1]
    child_var = unrolling.index_node[child][1]
    for edge in unrolling.spec.edges
        if edge.parent === parent_var && edge.child === child_var
            return edge.relation_kind
        end
    end
    return :causal_influence
end

"""
    causal_projection(unrolling) -> NamedTuple

Return the subgraph of causal-influence edges together with binding
non-causal constraints (constitution, participation, …) that remain relevant
for intervention admissibility. Non-`:causal_influence` declarations and
structurally constitutive pointwise→single-node edges are excluded from the
identification graph.
"""
function causal_projection(unrolling::TemporalUnrolling)
    g = unrolling.graph
    causal = Graphs.DiGraph(Graphs.nv(g))
    constraints = NamedTuple[]
    for edge in Graphs.edges(g)
        src = Graphs.src(edge)
        dst = Graphs.dst(edge)
        declared = _declared_relation_kind(unrolling, src, dst)
        role = temporal_edge_role(unrolling, src, dst)
        non_causal = declared !== :causal_influence || role === :constitutive
        if non_causal
            kind = if declared !== :causal_influence
                declared
            else
                :constitutive_persistence
            end
            push!(constraints, (
                parent = unrolling.index_node[src],
                child = unrolling.index_node[dst],
                relation_kind = kind,
            ))
        else
            Graphs.add_edge!(causal, src, dst)
        end
    end
    return (graph = causal, constraints = constraints)
end

export LaggedEdge, TemporalNodeSpec, TemporalDAGSpec, TemporalUnrolling
export unroll_temporal_dag, temporal_node, enduring_node, temporal_node_label, is_single_node
export d_separated_temporal, temporal_backdoor_adjustment_set, temporal_backdoor_adjustment_nodes
export temporal_edge_role, temporal_edge_records, causal_projection
