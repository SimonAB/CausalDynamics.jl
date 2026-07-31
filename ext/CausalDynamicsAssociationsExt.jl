"""
    CausalDynamicsAssociationsExt

Optional integration: [Associations.jl](https://juliadynamics.github.io/Associations.jl/stable/)
for constraint-based (PC) and time-series (OCE) structure learning, bridged to
CausalDynamics identification APIs.
"""
module CausalDynamicsAssociationsExt

using Associations: Associations, PC, OCE, infer_graph, CorrTest,
    SurrogateAssociationTest, LocalPermutationTest, PearsonCorrelation, PartialCorrelation,
    association, KSG1, MIShannon, StateSpaceSet
using CausalDynamics: CausalDynamics,
    digraph_with_names,
    oce_parents_to_temporal_spec,
    prepare_from_discovery,
    DiscoveryGraphMetadata,
    TemporalDAGSpec
using Graphs: SimpleDiGraph, DiGraph, nv
using DataFrames: DataFrames
using Random: Random

export infer_pc_digraph,
    infer_pc_graph,
    infer_oce_parents,
    infer_oce_temporal_spec,
    discover_and_prepare,
    iee_mi_associations

"""
    default_pc_algorithm(; α=0.05) -> PC

Default PC configuration: Gaussian correlation tests (fast, reliable on linear data).
"""
function default_pc_algorithm(; α = 0.05)
    return PC(CorrTest(), CorrTest(); α)
end

"""
    _discovery_columns(data) -> Vector{Vector{Float64}}

Coerce tabular input to column vectors for Associations `infer_graph` (PC).
"""
function _discovery_columns(data)
    if data isa DataFrames.DataFrame
        return [Vector{Float64}(data[!, j]) for j in 1:DataFrames.ncol(data)]
    elseif data isa AbstractMatrix
        return [Vector{Float64}(data[:, j]) for j in 1:size(data, 2)]
    elseif data isa AbstractVector{<:AbstractVector}
        return [Vector{Float64}(v) for v in data]
    else
        error("Unsupported data type $(typeof(data)). Use DataFrame, Matrix, or Vector{Vector}.")
    end
end

"""
    infer_pc_digraph(data; α=0.05, algorithm=nothing, verbose=false) -> SimpleDiGraph

Run the PC algorithm via Associations.jl on `data`.
"""
function infer_pc_digraph(data; α = 0.05, algorithm = nothing, verbose = false, kwargs...)
    !isempty(kwargs) && @warn "ignoring unsupported keyword arguments to infer_pc_digraph" keys=collect(keys(kwargs))
    alg = algorithm === nothing ? default_pc_algorithm(; α) : algorithm
    X = _discovery_columns(data)
    return infer_graph(alg, X; verbose=verbose)
end

"""
    infer_pc_graph(data, names::AbstractVector{Symbol}; kwargs...) -> CausalGraph

PC discovery with node names stored on a `CausalGraph`.
"""
function infer_pc_graph(data, names::AbstractVector{Symbol}; kwargs...)
    pc_kwargs = (; α=get(kwargs, :α, 0.05),
        algorithm=get(kwargs, :algorithm, nothing),
        verbose=get(kwargs, :verbose, false))
    g = infer_pc_digraph(data; pc_kwargs...)
    length(names) == nv(g) || throw(ArgumentError(
        "length(names) ($(length(names))) must equal number of discovered nodes ($(nv(g)))",
    ))
    return digraph_with_names(DiGraph(g), collect(Symbol, names))
end

"""
    default_oce_algorithm(; α=0.05, rng=Random.default_rng()) -> OCE

Lightweight OCE defaults for examples (correlation-based tests).
"""
function default_oce_algorithm(; α = 0.05, rng = Random.default_rng())
    utest = SurrogateAssociationTest(PearsonCorrelation(); nshuffles = 20, rng)
    ctest = LocalPermutationTest(PartialCorrelation(); nshuffles = 20, rng)
    return OCE(; utest, ctest, τmax = 1, α)
end

"""
    infer_oce_parents(ts; algorithm=default_oce_algorithm(), verbose=false) -> Vector

Run OCE parent selection on multivariate time series (`Vector{Vector}` or matrix columns).
"""
function infer_oce_parents(ts; algorithm = default_oce_algorithm(), verbose = false)
    if ts isa AbstractMatrix
        cols = [ts[:, j] for j in 1:size(ts, 2)]
        return infer_graph(algorithm, cols; verbose=verbose)
    end
    return infer_graph(algorithm, ts; verbose=verbose)
end

"""
    infer_oce_temporal_spec(ts, variables::AbstractVector{Symbol}; kwargs...) -> TemporalDAGSpec

OCE discovery converted to [`TemporalDAGSpec`](@ref) using `variables` as column names.
"""
function infer_oce_temporal_spec(ts, variables::AbstractVector{Symbol}; kwargs...)
    parents = infer_oce_parents(ts; kwargs...)
    length(parents) == length(variables) || throw(ArgumentError(
        "number of OCE results ($(length(parents))) must match length(variables) ($(length(variables)))",
    ))
    return oce_parents_to_temporal_spec(parents, variables)
end

"""
    discover_and_prepare(data, treatment, outcome;
        method = :pc,
        names = nothing,
        node_names = nothing,
        metadata = false,
        kwargs...,
    )

Discover a candidate graph then call [`prepare_from_discovery`](@ref).

# Arguments
- `method`: `:pc` (iid/tabular) or `:oce` (multivariate time series)
- `names`: variable symbols (required for `:pc`; defaults to `:x1`, `:x2`, …)
- `node_names`: optional `Dict{Int,Symbol}` for `prepare_from_discovery` (inferred from `names` when omitted)
"""
function discover_and_prepare(
    data,
    treatment,
    outcome;
    method = :pc,
    names = nothing,
    node_names = nothing,
    metadata = false,
    kwargs...,
)
    if method == :pc
        cols = _discovery_columns(data)
        p = length(cols)
        sym_names = names === nothing ? [Symbol("x", i) for i in 1:p] : collect(Symbol, names)
        g = infer_pc_graph(data, sym_names; kwargs...)
        dict = node_names === nothing ? Dict(i => sym_names[i] for i in 1:p) : node_names
        confounders, identifiable = prepare_from_discovery(
            g, treatment, outcome;
            node_names=dict,
            complete=get(kwargs, :complete, false),
        )
        meta = DiscoveryGraphMetadata(:pc, get(kwargs, :α, 0.05), length(first(cols)), sym_names)
    elseif method == :oce
        throw(ArgumentError(
            "method=:oce is not supported in discover_and_prepare; use infer_oce_temporal_spec " *
            "then unroll_temporal_dag and temporal_backdoor_adjustment_set",
        ))
    else
        throw(ArgumentError("method must be :pc or :oce, got $method"))
    end
    return metadata ? (confounders, identifiable, meta) : (confounders, identifiable)
end

"""
    iee_mi_associations(Xp, Yp; k=2) -> Float64

Mutual information of neighbour residuals for IEE via Associations `KSG1`
(Chebyshev / Kraskov). Rows of `Xp` / `Yp` are residual vectors.
"""
function iee_mi_associations(
    Xp::AbstractMatrix{<:Real},
    Yp::AbstractMatrix{<:Real};
    k::Integer = 2,
)
    size(Xp, 1) == size(Yp, 1) || throw(ArgumentError("Xp/Yp row mismatch"))
    n = size(Xp, 1)
    n < k + 1 && return 0.0
    # Deduplicate joint rows (match reference IEE behaviour)
    seen = Dict{Vector{Float64}, Int}()
    keep = Int[]
    @inbounds for i in 1:n
        key = vcat(Float64.(Xp[i, :]), Float64.(Yp[i, :]))
        if !haskey(seen, key)
            seen[key] = i
            push!(keep, i)
        end
    end
    length(keep) < k + 1 && return 0.0
    Xset = StateSpaceSet([Xp[i, :] for i in keep])
    Yset = StateSpaceSet([Yp[i, :] for i in keep])
    mi = association(KSG1(MIShannon(); k = k), Xset, Yset)
    return abs(Float64(mi))
end

end # module
