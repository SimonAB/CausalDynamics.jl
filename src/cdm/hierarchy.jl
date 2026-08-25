"""Hierarchical / nested exogenous structure for CDM panels.

Generative nesting (cluster → unit) lives here. Cluster-robust IF estimation
belongs in CausalTargeted; LMM/BLUP partial pooling belongs in application
code (or optional RxInfer heads), not in this package.
"""

"""
Assumption symbols for nested units (attach to certificates when relevant).

- `:nested_exogenous` — shared cluster-level exogenous draws
- `:no_interference_across_clusters` — no cross-cluster causal pathways
"""
const HIERARCHY_ASSUMPTIONS = (:nested_exogenous, :no_interference_across_clusters)

"""
    RandomEffectSpec

Specification for nested exogenous noise when simulating hierarchical panels.

# Fields
- `cluster_col`: column name for the cluster id in the panel (`Float64` codes)
- `n_clusters`: number of clusters
- `σ_cluster`: standard deviation of the cluster-level intercept
- `σ_unit`: standard deviation of the unit-level residual (added to named outcomes)
- `outcome_vars`: symbols that receive ``U_j + U_{ij}`` (wide panel columns)

Cluster ids are stored as ``1, 2, …`` encoded in `Float64` to match
[`CDMPanel`](@ref) column types.
"""
struct RandomEffectSpec
    cluster_col::Symbol
    n_clusters::Int
    σ_cluster::Float64
    σ_unit::Float64
    outcome_vars::Vector{Symbol}
end

"""
    RandomEffectSpec(; cluster_col=:cluster, n_clusters, σ_cluster=1.0, σ_unit=0.0, outcome_vars=[:y])

Construct a [`RandomEffectSpec`](@ref).
"""
function RandomEffectSpec(;
    cluster_col::Symbol = :cluster,
    n_clusters::Integer,
    σ_cluster::Real = 1.0,
    σ_unit::Real = 0.0,
    outcome_vars::AbstractVector{Symbol} = Symbol[:y],
)
    n_clusters = Int(n_clusters)
    n_clusters >= 1 || throw(ArgumentError("n_clusters must be ≥ 1; got $n_clusters"))
    σ_cluster >= 0 || throw(ArgumentError("σ_cluster must be ≥ 0"))
    σ_unit >= 0 || throw(ArgumentError("σ_unit must be ≥ 0"))
    outs = collect(Symbol, outcome_vars)
    isempty(outs) && throw(ArgumentError("outcome_vars must be nonempty"))
    return RandomEffectSpec(
        cluster_col, n_clusters, Float64(σ_cluster), Float64(σ_unit), outs,
    )
end

"""
    assign_cluster_ids(n, n_clusters; rng) -> Vector{Float64}

Assign units to clusters as evenly as possible (ids ``1…n_clusters`` as `Float64`).
"""
function assign_cluster_ids(
    n::Integer,
    n_clusters::Integer;
    rng::Random.AbstractRNG = Random.default_rng(),
)
    n = Int(n)
    n_clusters = Int(n_clusters)
    n >= 1 || throw(ArgumentError("n must be ≥ 1"))
    n_clusters >= 1 || throw(ArgumentError("n_clusters must be ≥ 1"))
    n_clusters > n && throw(ArgumentError(
        "n_clusters ($n_clusters) cannot exceed n ($n)",
    ))
    ids = Float64[mod1(i, n_clusters) for i in 1:n]
    Random.shuffle!(rng, ids)
    return ids
end

"""
    draw_nested_effects(cluster_ids, spec; rng) -> NamedTuple

Draw cluster intercepts and unit residuals aligned to `cluster_ids`.

Returns `(u_cluster, u_unit, cluster_levels)` where `u_cluster[i]` is the
shared draw for unit ``i``'s cluster.
"""
function draw_nested_effects(
    cluster_ids::AbstractVector{<:Real},
    spec::RandomEffectSpec;
    rng::Random.AbstractRNG = Random.default_rng(),
)
    n = length(cluster_ids)
    levels = sort!(unique(Float64.(cluster_ids)))
    length(levels) == spec.n_clusters || throw(ArgumentError(
        "cluster_ids has $(length(levels)) unique values; RandomEffectSpec.n_clusters=$(spec.n_clusters)",
    ))
    u_j = Dict{Float64, Float64}(
        j => spec.σ_cluster * randn(rng) for j in levels
    )
    u_cluster = [u_j[Float64(c)] for c in cluster_ids]
    u_unit = spec.σ_unit .* randn(rng, n)
    return (u_cluster = u_cluster, u_unit = u_unit, cluster_levels = levels)
end

"""
    add_nested_effects!(panel, cluster_ids, effects, spec) -> CDMPanel

Add ``U_j + U_{ij}`` to `spec.outcome_vars` and store `cluster_ids` under
`spec.cluster_col`. Mutates `panel.data` / `column_order`.
"""
function add_nested_effects!(
    panel::CDMPanel,
    cluster_ids::AbstractVector{<:Real},
    effects::NamedTuple,
    spec::RandomEffectSpec,
)
    n = panel.n
    length(cluster_ids) == n || throw(ArgumentError("cluster_ids length must equal panel.n"))
    length(effects.u_cluster) == n || throw(ArgumentError("u_cluster length must equal panel.n"))
    length(effects.u_unit) == n || throw(ArgumentError("u_unit length must equal panel.n"))
    add = effects.u_cluster .+ effects.u_unit
    for v in spec.outcome_vars
        haskey(panel.data, v) || throw(ArgumentError(
            "outcome :$v missing from panel; available: $(panel.column_order)",
        ))
        panel.data[v] .+= add
    end
    if haskey(panel.data, spec.cluster_col)
        panel.data[spec.cluster_col] .= Float64.(cluster_ids)
    else
        panel.data[spec.cluster_col] = Float64.(cluster_ids)
        push!(panel.column_order, spec.cluster_col)
    end
    return panel
end

"""
    simulate_hierarchical_panel(cdm, n, T; hierarchy, rng, kwargs...) -> CDMPanel

Simulate a [`CDMPanel`](@ref) then inject nested cluster/unit intercepts on
`hierarchy.outcome_vars`, writing the cluster id column.

Other keywords are forwarded to [`simulate_panel`](@ref).
"""
function simulate_hierarchical_panel(
    cdm::DiscreteTimeCDM,
    n::Integer,
    T::Integer;
    hierarchy::RandomEffectSpec,
    rng::Random.AbstractRNG = Random.default_rng(),
    kwargs...,
)
    n = Int(n)
    n >= hierarchy.n_clusters || throw(ArgumentError(
        "n ($n) must be ≥ hierarchy.n_clusters ($(hierarchy.n_clusters))",
    ))
    panel = simulate_panel(cdm, n, T; rng = rng, kwargs...)
    cluster_ids = assign_cluster_ids(n, hierarchy.n_clusters; rng = rng)
    effects = draw_nested_effects(cluster_ids, hierarchy; rng = rng)
    return add_nested_effects!(panel, cluster_ids, effects, hierarchy)
end

"""
    simulate_hierarchical_intercept_ate(n; n_clusters, σ_cluster, β_a, β_w, σ_y, rng)
        -> (columns, truth)

Binary point-treatment DGP with a shared cluster intercept:

- assign ``n`` units to `n_clusters` clusters
- ``U_j \\sim N(0, σ_cluster^2)`` per cluster; ``ε_i \\sim N(0, σ_y^2)``
- ``W_i \\sim N(0,1)``, ``A_i \\sim Bernoulli(logistic(0.5 W_i))``
- ``Y_i = β_a A_i + β_w W_i + U_{c(i)} + ε_i``

Returns a column dict suitable for `DataFrame` (when loaded) and `truth` with
`ate = β_a`, `σ_cluster`, and hierarchy assumption symbols.

This is a **generative** gate for nested ``U``, not an LMM fit.
"""
function simulate_hierarchical_intercept_ate(
    n::Integer;
    n_clusters::Integer = 10,
    σ_cluster::Real = 1.0,
    β_a::Real = 0.5,
    β_w::Real = 1.0,
    σ_y::Real = 0.5,
    rng::Random.AbstractRNG = Random.default_rng(),
)
    n = Int(n)
    n_clusters = Int(n_clusters)
    n >= n_clusters || throw(ArgumentError("n must be ≥ n_clusters"))
    σ_cluster >= 0 || throw(ArgumentError("σ_cluster must be ≥ 0"))
    σ_y >= 0 || throw(ArgumentError("σ_y must be ≥ 0"))

    spec = RandomEffectSpec(;
        n_clusters = n_clusters,
        σ_cluster = σ_cluster,
        σ_unit = 0.0,
        outcome_vars = [:Y],
    )
    cluster = assign_cluster_ids(n, n_clusters; rng = rng)
    effects = draw_nested_effects(cluster, spec; rng = rng)
    W = randn(rng, n)
    p = 1.0 ./ (1.0 .+ exp.(-0.5 .* W))
    A = Float64.(rand(rng, n) .< p)
    ε = Float64(σ_y) .* randn(rng, n)
    Y = Float64(β_a) .* A .+ Float64(β_w) .* W .+ effects.u_cluster .+ ε
    cols = Dict{Symbol, Vector{Float64}}(
        :cluster => cluster,
        :W => W,
        :A => A,
        :Y => Y,
    )
    truth = (
        name = "hierarchical_intercept_ate",
        ate = Float64(β_a),
        β_w = Float64(β_w),
        σ_cluster = Float64(σ_cluster),
        σ_y = Float64(σ_y),
        n_clusters = n_clusters,
        assumptions = collect(HIERARCHY_ASSUMPTIONS),
    )
    return cols, truth
end

# --- Hierarchical DAG unroll (Phase 2) ---------------------------------------

"""
    HierarchicalNestingSpec

Unit-level template DAG plus a shared cluster-level node that points into
selected unit variables. Used by [`unroll_hierarchical_dag`](@ref).

# Fields
- `unit_variables`: symbols replicated once per unit
- `unit_edges`: directed edges within each unit copy `(parent, child)`
- `cluster_variable`: symbol for the shared cluster-level node (per cluster)
- `affects`: unit variables that receive an edge from the cluster node
"""
struct HierarchicalNestingSpec
    unit_variables::Vector{Symbol}
    unit_edges::Vector{Tuple{Symbol, Symbol}}
    cluster_variable::Symbol
    affects::Vector{Symbol}
end

"""
    HierarchicalNestingSpec(unit_variables, unit_edges; cluster_variable=:U, affects=[:Y])

Construct a nesting template. `unit_edges` may be `(Symbol, Symbol)` tuples.
"""
function HierarchicalNestingSpec(
    unit_variables::AbstractVector{Symbol},
    unit_edges::AbstractVector;
    cluster_variable::Symbol = :U,
    affects::AbstractVector{Symbol} = Symbol[:Y],
)
    vars = collect(Symbol, unit_variables)
    isempty(vars) && throw(ArgumentError("unit_variables must be nonempty"))
    cluster_variable in vars && throw(ArgumentError(
        "cluster_variable :$cluster_variable must not appear in unit_variables",
    ))
    aff = collect(Symbol, affects)
    isempty(aff) && throw(ArgumentError("affects must be nonempty"))
    for a in aff
        a in vars || throw(ArgumentError("affects symbol :$a is not in unit_variables"))
    end
    edges = Tuple{Symbol, Symbol}[]
    for e in unit_edges
        if e isa Tuple && length(e) == 2
            p, c = Symbol(e[1]), Symbol(e[2])
        else
            throw(ArgumentError("unit_edges entries must be (parent, child) tuples"))
        end
        p in vars || throw(ArgumentError("unknown parent :$p in unit_edges"))
        c in vars || throw(ArgumentError("unknown child :$c in unit_edges"))
        push!(edges, (p, c))
    end
    return HierarchicalNestingSpec(vars, edges, cluster_variable, aff)
end

"""
    HierarchicalUnrolling

Result of [`unroll_hierarchical_dag`](@ref): a flat DAG over unit copies and
cluster nodes, with index maps and hierarchy assumptions.
"""
struct HierarchicalUnrolling
    n_units::Int
    n_clusters::Int
    cluster_of_unit::Vector{Int}
    spec::HierarchicalNestingSpec
    graph::Graphs.DiGraph
    node_index::Dict{Any, Int}
    index_node::Vector{Any}
    assumptions::Vector{Symbol}
end

"""
    hierarchical_node(unrolling, key) -> Int

Look up a node id. Keys are `(:cluster, j)` or `(:unit, i, var::Symbol)`.
"""
function hierarchical_node(unrolling::HierarchicalUnrolling, key)
    haskey(unrolling.node_index, key) || throw(ArgumentError(
        "no node for key $key in hierarchical unrolling",
    ))
    return unrolling.node_index[key]
end

"""
    hierarchical_node_names(unrolling) -> Dict{Int, Symbol}

Stable Symbol labels for Documenter / `identify(...; node_names=)`:
`U_c1`, `W_u3`, `Y_u3`, …
"""
function hierarchical_node_names(unrolling::HierarchicalUnrolling)
    names = Dict{Int, Symbol}()
    for (id, key) in enumerate(unrolling.index_node)
        if key isa Tuple && length(key) == 2 && key[1] === :cluster
            names[id] = Symbol(string(unrolling.spec.cluster_variable), "_c", key[2])
        elseif key isa Tuple && length(key) == 3 && key[1] === :unit
            names[id] = Symbol(string(key[3]), "_u", key[2])
        else
            names[id] = Symbol("n", id)
        end
    end
    return names
end

"""
    unroll_hierarchical_dag(spec, n_units; n_clusters=1, cluster_of_unit=nothing)
        -> HierarchicalUnrolling

Expand a unit template into `n_units` copies and `n_clusters` shared cluster
nodes. Edges within each unit copy follow `spec.unit_edges`; each cluster node
``j`` points to `spec.affects` variables of every unit assigned to cluster ``j``.

When `cluster_of_unit` is omitted, units are assigned round-robin to clusters
(ids ``1:n_clusters``).
"""
function unroll_hierarchical_dag(
    spec::HierarchicalNestingSpec,
    n_units::Integer;
    n_clusters::Integer = 1,
    cluster_of_unit::Union{Nothing, AbstractVector{<:Integer}} = nothing,
)
    n_units = Int(n_units)
    n_clusters = Int(n_clusters)
    n_units >= 1 || throw(ArgumentError("n_units must be ≥ 1"))
    n_clusters >= 1 || throw(ArgumentError("n_clusters must be ≥ 1"))
    n_clusters > n_units && throw(ArgumentError(
        "n_clusters ($n_clusters) cannot exceed n_units ($n_units)",
    ))

    if cluster_of_unit === nothing
        assignment = [mod1(i, n_clusters) for i in 1:n_units]
    else
        length(cluster_of_unit) == n_units || throw(ArgumentError(
            "cluster_of_unit length must equal n_units",
        ))
        assignment = Int.(cluster_of_unit)
        for c in assignment
            (1 <= c <= n_clusters) || throw(ArgumentError(
                "cluster_of_unit entry $c out of range 1:$n_clusters",
            ))
        end
    end

    node_index = Dict{Any, Int}()
    index_node = Any[]
    for j in 1:n_clusters
        push!(index_node, (:cluster, j))
        node_index[(:cluster, j)] = length(index_node)
    end
    for i in 1:n_units, v in spec.unit_variables
        push!(index_node, (:unit, i, v))
        node_index[(:unit, i, v)] = length(index_node)
    end

    g = Graphs.DiGraph(length(index_node))
    for i in 1:n_units
        for (p, c) in spec.unit_edges
            Graphs.add_edge!(g, node_index[(:unit, i, p)], node_index[(:unit, i, c)])
        end
        j = assignment[i]
        for v in spec.affects
            Graphs.add_edge!(g, node_index[(:cluster, j)], node_index[(:unit, i, v)])
        end
    end

    return HierarchicalUnrolling(
        n_units,
        n_clusters,
        assignment,
        spec,
        g,
        node_index,
        index_node,
        collect(HIERARCHY_ASSUMPTIONS),
    )
end

"""
    attach_hierarchy_assumptions(result) -> IdentificationResult

Return a copy of `result` with [`HIERARCHY_ASSUMPTIONS`](@ref) unioned into
`assumptions` (idempotent).
"""
function attach_hierarchy_assumptions(result::IdentificationResult{T}) where {T}
    assumptions = unique(vcat(result.assumptions, collect(HIERARCHY_ASSUMPTIONS)))
    return IdentificationResult{T}(
        result.query,
        result.graph_hash,
        result.adjustment,
        result.mediators,
        result.moc,
        result.strategy,
        result.identifiable,
        assumptions,
        result.temporal_nodes,
        result.missingness,
    )
end

export RandomEffectSpec, HIERARCHY_ASSUMPTIONS
export assign_cluster_ids, draw_nested_effects, add_nested_effects!
export simulate_hierarchical_panel, simulate_hierarchical_intercept_ate
export HierarchicalNestingSpec, HierarchicalUnrolling
export unroll_hierarchical_dag, hierarchical_node, hierarchical_node_names
export attach_hierarchy_assumptions
