"""
    Discovery integration (Associations.jl optional)

Core graph converters bridge discovered structure to CausalDynamics identification.
Load `Associations` and `DataFrames` to activate the `CausalDynamicsAssociationsExt` package extension.
`infer_pc_graph` and related discovery helpers.
"""

"""
    DiscoveryGraphMetadata

Lightweight record of how a candidate graph was obtained (for logging and reproducibility).
"""
struct DiscoveryGraphMetadata
    method::Symbol
    α::Union{Real, Nothing}
    n::Union{Int, Nothing}
    variables::Vector{Symbol}
end

"""
    has_associations() -> Bool

Return `true` when the `CausalDynamicsAssociationsExt` extension is loaded (`using Associations`).
"""
function has_associations()
    return !isnothing(Base.get_extension(@__MODULE__, :CausalDynamicsAssociationsExt))
end

function _require_associations!(f::Symbol)
    ext = Base.get_extension(@__MODULE__, :CausalDynamicsAssociationsExt)
    ext === nothing && error(
        "Associations.jl extension is not loaded. Run: using Associations\n" *
        "Then call CausalDynamics.$f(...). See docs/ASSOCIATIONS_INTEGRATION.md.",
    )
    return ext
end

"""
    digraph_with_names(g::AbstractGraph, names::AbstractVector{Symbol}) -> CausalGraph

Wrap `g` in a `CausalGraph` and attach `:name` properties from `names`.

`length(names)` must equal `nv(g)`.
"""
function digraph_with_names(g::Graphs.AbstractGraph, names::AbstractVector{Symbol})
    n = Graphs.nv(g)
    length(names) == n || throw(ArgumentError(
        "length(names) ($(length(names))) must equal nv(g) ($n)",
    ))
    cg = CausalGraph(g)
    for (i, name) in pairs(names)
        set_node_prop!(cg, i, :name, name)
    end
    return cg
end

"""
    _oce_lag(τ::Integer) -> Int

Map Associations OCE embedding lag `τ` (negative in `parents_τs`) to
[`TemporalDAGSpec`](@ref) lag (non-negative; `1` means parent at `t-1`).
"""
function _oce_lag(τ::Integer)
    lag = abs(τ)
    lag < 0 && throw(ArgumentError("invalid OCE lag τ = $τ"))
    return lag
end

"""
    oce_parents_to_temporal_spec(parents, variables::AbstractVector{Symbol}) -> TemporalDAGSpec

Convert OCE [`OCESelectedParents`](https://juliadynamics.github.io/Associations.jl/stable/)
output to a [`TemporalDAGSpec`](@ref).

# Arguments
- `parents`: vector of parent selections (one per variable), e.g. from `infer_graph(OCE(), ts)`
- `variables`: symbol name for each series index (`variables[i]` is variable `i`)

# Lag convention

OCE stores embedding lags in `parents_τs` (typically negative, e.g. `-1` for `xⱼ(-1)`).
These map to `LaggedEdge` lags as `lag = abs(τ)`, so `τ = -1` becomes `lag = 1`
(parent at `t-1` causes child at `t`), matching Ch. 28 unrolling.
"""
function oce_parents_to_temporal_spec(
    parents::AbstractVector,
    variables::AbstractVector{Symbol},
)
    length(parents) == length(variables) || throw(ArgumentError(
        "length(parents) ($(length(parents))) must equal length(variables) ($(length(variables)))",
    ))
    edges = LaggedEdge[]
    for (i, sel) in pairs(parents)
        child = variables[i]
        child in variables || throw(ArgumentError("unknown child index $i"))
        js = _discovery_field(sel, :parents_js)
        τs = _discovery_field(sel, :parents_τs)
        length(js) == length(τs) || throw(ArgumentError(
            "parents_js and parents_τs length mismatch for variable :$child",
        ))
        for (j, τ) in zip(js, τs)
            parent = variables[j]
            lag = _oce_lag(τ)
            lag == 0 && parent == child &&
                throw(ArgumentError("contemporaneous self-loop :$parent → :$child at lag 0"))
            push!(edges, LaggedEdge(parent, child, lag))
        end
    end
    return TemporalDAGSpec(collect(Symbol, variables), edges)
end

function _discovery_field(x, field::Symbol)
    if hasproperty(x, field)
        return getproperty(x, field)
    end
    if x isa NamedTuple && haskey(x, field)
        return x[field]
    end
    throw(ArgumentError("parent selection object must have field :$field, got $(typeof(x))"))
end

function _name_to_index(node_names::AbstractDict{Int, Symbol})
    return Dict{Symbol, Int}(name => idx for (idx, name) in node_names)
end

function _resolve_discovery_nodes(
    g::Graphs.AbstractGraph,
    treatment,
    outcome;
    node_names::Union{Nothing, AbstractDict{Int, Symbol}} = nothing,
)
    if treatment isa Int && outcome isa Int
        for v in (treatment, outcome)
            (1 <= v <= Graphs.nv(g)) || throw(ArgumentError("node index $v out of range 1:$(nv(g))"))
        end
        return treatment, outcome, node_names
    end
    node_names === nothing && throw(ArgumentError(
        "node_names required when treatment/outcome are symbols",
    ))
    inv = _name_to_index(node_names)
    haskey(inv, Symbol(treatment)) || throw(ArgumentError("unknown treatment node :$treatment"))
    haskey(inv, Symbol(outcome)) || throw(ArgumentError("unknown outcome node :$outcome"))
    X = inv[Symbol(treatment)]
    Y = inv[Symbol(outcome)]
    return X, Y, node_names
end

"""
    cpdag_to_dag(g::Graphs.DiGraph) -> Graphs.DiGraph

Break remaining bidirectional edges in a PC output (CPDAG) to obtain a DAG.

When both `i → j` and `j → i` are present, drops `j → i` if `i < j`.
Discovery outputs may still be only partially oriented; this is a pragmatic
heuristic before calling backdoor identification.
"""
function cpdag_to_dag(g::Graphs.DiGraph)
    h = copy(g)
    for u in Graphs.vertices(h), v in Graphs.vertices(h)
        u < v || continue
        if has_edge(h, u, v) && has_edge(h, v, u)
            rem_edge!(h, v, u)
        end
    end
    is_dag(h) || throw(ArgumentError(
        "discovered graph is not a DAG after breaking bidirectional edges; " *
        "refine structure or specify a DAG manually",
    ))
    return h
end

"""
    prepare_from_discovery(g, treatment, outcome; node_names=nothing, complete=false)

Run backdoor identification on a **candidate** graph from discovery (PC, OCE, domain knowledge).

The input graph is treated as structural hypothesis, not ground truth. Discovery typically
returns a CPDAG or lag parent set under faithfulness and sufficiency assumptions.

# Returns
- `confounders`: adjustment set (symbols if `node_names` given, else node indices)
- `identifiable`: whether a backdoor adjustment set exists

# See Also
- [`prepare_for_tmle`](@ref)
- [`backdoor_adjustment_set`](@ref)
"""
function prepare_from_discovery(
    g::Graphs.AbstractGraph,
    treatment::Int,
    outcome::Int;
    node_names = nothing,
    complete = false,
)
    graph = complete && g isa Graphs.DiGraph ? cpdag_to_dag(g) : g
    X, Y, names = _resolve_discovery_nodes(graph, treatment, outcome; node_names=node_names)
    return prepare_for_tmle(graph, X, Y; node_names=names)
end

function prepare_from_discovery(
    g::Graphs.AbstractGraph,
    treatment::Symbol,
    outcome::Symbol;
    node_names = nothing,
    complete = false,
)
    graph = complete && g isa Graphs.DiGraph ? cpdag_to_dag(g) : g
    X, Y, names = _resolve_discovery_nodes(graph, treatment, outcome; node_names=node_names)
    return prepare_for_tmle(graph, X, Y; node_names=names)
end

function prepare_from_discovery(g::CausalGraph, treatment::Int, outcome::Int; node_names = nothing, complete = false)
    if node_names === nothing
        detected = get_node_names(g)
        node_names = isempty(detected) ? nothing : detected
    end
    graph = complete ? cpdag_to_dag(g.graph) : g.graph
    return prepare_from_discovery(graph, treatment, outcome; node_names=node_names, complete=false)
end

function prepare_from_discovery(g::CausalGraph, treatment::Symbol, outcome::Symbol; node_names = nothing, complete = false)
    if node_names === nothing
        detected = get_node_names(g)
        node_names = isempty(detected) ? nothing : detected
    end
    graph = complete ? cpdag_to_dag(g.graph) : g.graph
    return prepare_from_discovery(graph, treatment, outcome; node_names=node_names, complete=false)
end

"""
    infer_pc_digraph(data; kwargs...) -> SimpleDiGraph

Run PC via Associations.jl. Requires `using Associations`.
"""
function infer_pc_digraph(args...; kwargs...)
    ext = _require_associations!(:infer_pc_digraph)
    return ext.infer_pc_digraph(args...; kwargs...)
end

"""
    infer_pc_graph(data, names; kwargs...) -> CausalGraph

PC discovery with node names attached. Requires `using Associations`.
"""
function infer_pc_graph(args...; kwargs...)
    ext = _require_associations!(:infer_pc_graph)
    return ext.infer_pc_graph(args...; kwargs...)
end

"""
    infer_oce_parents(ts; kwargs...) -> Vector

OCE parent selection. Requires `using Associations`.
"""
function infer_oce_parents(args...; kwargs...)
    ext = _require_associations!(:infer_oce_parents)
    return ext.infer_oce_parents(args...; kwargs...)
end

"""
    infer_oce_temporal_spec(ts, variables; kwargs...) -> TemporalDAGSpec

OCE discovery converted to [`TemporalDAGSpec`](@ref). Requires `using Associations`.
"""
function infer_oce_temporal_spec(args...; kwargs...)
    ext = _require_associations!(:infer_oce_temporal_spec)
    return ext.infer_oce_temporal_spec(args...; kwargs...)
end

"""
    discover_and_prepare(data, treatment, outcome; method=:pc, kwargs...)

Discover a graph then call [`prepare_from_discovery`](@ref). Requires `using Associations`.
"""
function discover_and_prepare(args...; kwargs...)
    ext = _require_associations!(:discover_and_prepare)
    return ext.discover_and_prepare(args...; kwargs...)
end

export DiscoveryGraphMetadata,
    has_associations,
    digraph_with_names,
    cpdag_to_dag,
    oce_parents_to_temporal_spec,
    prepare_from_discovery,
    infer_pc_digraph,
    infer_pc_graph,
    infer_oce_parents,
    infer_oce_temporal_spec,
    discover_and_prepare
