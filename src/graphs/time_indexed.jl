"""
Time-indexed causal graphs for discrete-time causal dynamical models.

`unroll_temporal_dag` expands a [`TemporalDAGSpec`](@ref) over ``t = 0:T``.
Node multiplicity follows [`TemporalSupport`](@ref) and [`GraphKind`](@ref),
never referent identity or `ontological_character`.
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
    TemporalNodeSpec(name; temporal_support=PointwiseSupport(),
        value_representation=:unspecified, referent=nothing, causal_role=nothing)

Describe one variable in a [`TemporalDAGSpec`](@ref) by three orthogonal
declarations:

- `temporal_support`: a [`TemporalSupport`](@ref) (or the symbol shorthands
  accepted by [`parse_temporal_support`](@ref)). It alone decides how many nodes
  the variable contributes when unrolled. A from-onset attribute must name its
  onset: `FromOnsetSupport(t₀)`.
- `value_representation`: what a node's value is (`:state`, `:event`,
  `:attribute`, `:trajectory`, `:interval_summary`, …).
- `referent`: an optional [`ReferentSpec`](@ref) naming what the variable is
  about, together with any `identity_criterion` and `ontological_character`.
  `referent_id = :sheep` is shorthand for `referent = ReferentSpec(:sheep)`.
  Identity and ontology are declared on the referent, never on the node.

`causal_role` is optional descriptive metadata (`:assigned`, `:mediator`, …)
read by downstream planners; it does not alter the graph.

Derived read-only properties: `onset_time` (from the support; `0` for
pointwise and global supports), `referent_id`, `identity_criterion`,
`ontological_character`.
"""
struct TemporalNodeSpec
    name::Symbol
    temporal_support::TemporalSupport
    value_representation::Symbol
    referent::Union{Nothing, ReferentSpec}
    causal_role::Union{Nothing, Symbol}

    function TemporalNodeSpec(
        name::Symbol,
        temporal_support::TemporalSupport,
        value_representation::Symbol,
        referent::Union{Nothing, ReferentSpec},
        causal_role::Union{Nothing, Symbol},
    )
        return new(
            name,
            temporal_support,
            normalise_value_representation(value_representation),
            referent,
            causal_role,
        )
    end
end

function TemporalNodeSpec(
    name::Symbol;
    temporal_support = PointwiseSupport(),
    value_representation::Symbol = :unspecified,
    referent::Union{Nothing, ReferentSpec} = nothing,
    referent_id::Union{Nothing, Symbol} = nothing,
    causal_role::Union{Nothing, Symbol} = nothing,
    identity_criterion = nothing,
    ontological_character = nothing,
)
    if identity_criterion !== nothing || ontological_character !== nothing
        throw(ArgumentError(
            "identity_criterion and ontological_character are declared on the " *
            "ReferentSpec, not the node: TemporalNodeSpec(:$name; referent = " *
            "ReferentSpec(id; identity_criterion, ontological_character))",
        ))
    end
    if referent !== nothing && referent_id !== nothing && referent_id !== referent.id
        throw(ArgumentError(
            "referent_id :$referent_id conflicts with referent.id :$(referent.id)",
        ))
    end
    if referent === nothing && referent_id !== nothing
        referent = ReferentSpec(referent_id)
    end
    support = parse_temporal_support(temporal_support)
    return TemporalNodeSpec(name, support, value_representation, referent, causal_role)
end

function Base.getproperty(node::TemporalNodeSpec, property::Symbol)
    property === :onset_time && return onset_from_support(getfield(node, :temporal_support), 0)
    if property in (:referent_id, :identity_criterion, :ontological_character)
        referent = getfield(node, :referent)
        property === :referent_id && return referent === nothing ? nothing : referent.id
        property === :identity_criterion &&
            return referent === nothing ? nothing : referent.identity_criterion
        return referent === nothing ? :unspecified : referent.ontological_character
    end
    return getfield(node, property)
end

function Base.propertynames(node::TemporalNodeSpec, private::Bool = false)
    return (
        fieldnames(TemporalNodeSpec)...,
        :onset_time, :referent_id, :identity_criterion, :ontological_character,
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
    return (fieldnames(TemporalDAGSpec)..., :variables)
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

"""Return whether a descriptor is active at time index `t`."""
_active_at(node::TemporalNodeSpec, t::Int) = t ≥ node.onset_time

"""Result of unrolling a [`TemporalDAGSpec`](@ref) over time indices `0:T`."""
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

Return the semantic role of an edge in a temporal unrolling.

If the edge was declared with a `relation_kind` other than `:causal_influence`
(`:constitutive_persistence`, `:constitutive_dependence`, `:participation`,
`:measurement`, …), that declared kind is returned. Otherwise the role is a
**construction-pattern label** for a causal-influence edge, describing only the
supports of its endpoints:

- `:onset_assignment` — pointwise parent assigns into a single-node child
- `:recurrent_influence` — single-node parent influences a pointwise child
- `:pointwise_influence` — pointwise to pointwise
- `:causal_influence` — single-node to single-node

Support patterns never make an edge constitutive: an onset assignment is an
ordinary causal edge unless declared otherwise. Derived roles do not alter
the unrolled topology used for display.
"""
function temporal_edge_role(unrolling::TemporalUnrolling, parent::Integer, child::Integer)
    1 ≤ parent ≤ length(unrolling.index_node) || throw(BoundsError(unrolling.index_node, parent))
    1 ≤ child ≤ length(unrolling.index_node) || throw(BoundsError(unrolling.index_node, child))
    declared = _declared_relation_kind(unrolling, parent, child)
    declared === :causal_influence || return declared
    parent_time = unrolling.index_node[parent][2]
    child_time = unrolling.index_node[child][2]
    if child_time === nothing && parent_time !== nothing
        return :onset_assignment
    elseif parent_time === nothing && child_time !== nothing
        return :recurrent_influence
    elseif parent_time === nothing && child_time === nothing
        return :causal_influence
    end
    return :pointwise_influence
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
non-causal constraints (constitution, participation, measurement, …) that
remain relevant for intervention admissibility.

Membership is decided **only** by the declared `relation_kind` of each edge.
Support patterns (pointwise → single-node onset assignments, and so on) are
construction facts and never demote a declared causal edge to a constraint:
a diagnosis that assigns a subsequently maintained treatment is a causal
parent of that treatment. To record a constitutive relation, declare it with
`LaggedEdge(...; relation_kind = :constitutive_persistence)` or
`:constitutive_dependence`.
"""
function causal_projection(unrolling::TemporalUnrolling)
    g = unrolling.graph
    causal = Graphs.DiGraph(Graphs.nv(g))
    constraints = NamedTuple[]
    for edge in Graphs.edges(g)
        src = Graphs.src(edge)
        dst = Graphs.dst(edge)
        declared = _declared_relation_kind(unrolling, src, dst)
        if declared === :causal_influence
            Graphs.add_edge!(causal, src, dst)
        else
            push!(constraints, (
                parent = unrolling.index_node[src],
                child = unrolling.index_node[dst],
                relation_kind = declared,
            ))
        end
    end
    return (graph = causal, constraints = constraints)
end

export LaggedEdge, TemporalNodeSpec, TemporalDAGSpec, TemporalUnrolling
export unroll_temporal_dag, temporal_node, enduring_node, temporal_node_label, is_single_node
export d_separated_temporal, temporal_backdoor_adjustment_set, temporal_backdoor_adjustment_nodes
export temporal_edge_role, temporal_edge_records, causal_projection
