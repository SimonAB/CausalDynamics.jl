"""
    Interventional Embedding Entropy (IEE)

Port of Shi et al.'s IntDC criterion from observational time series
(reference MATLAB: https://github.com/smsxiaomayi/IEE).

IEE estimates interventional dynamical causality in delay-embedding space via
local neighbourhood geometry and a k-NN mutual-information estimator. It is a
**discovery / ranking** tool: feed ranked edges into [`TemporalDAGSpec`](@ref)
and run identification separately.
"""

"""
    _digamma_int(n) -> Float64

Digamma `ψ(n)` for positive integers via harmonic numbers (`ψ(1) = -γ`).
"""
function _digamma_int(n::Integer)
    n < 1 && throw(ArgumentError("digamma requires n ≥ 1; got n = $n"))
    γ = 0.5772156649015328606
    s = -γ
    @inbounds for i in 1:(n - 1)
        s += 1 / i
    end
    return s
end

"""
    _chebyshev(a, b) -> Float64

Chebyshev (L∞) distance between equal-length vectors.
"""
function _chebyshev(a::AbstractVector{<:Real}, b::AbstractVector{<:Real})
    d = 0.0
    @inbounds for i in eachindex(a, b)
        d = max(d, abs(Float64(a[i]) - Float64(b[i])))
    end
    return d
end

"""
    _knn_indices(data, query, K; exclude) -> Vector{Int}

Brute-force Euclidean k-NN indices into rows of `data` (matrix with observations in rows).
`exclude` is a set of row indices to skip (Theiler window).
"""
function _knn_indices(
    data::AbstractMatrix{<:Real},
    query::AbstractVector{<:Real},
    K::Integer;
    exclude::AbstractSet{<:Integer} = Set{Int}(),
)
    n = size(data, 1)
    dists = Vector{Tuple{Float64, Int}}(undef, 0)
    sizehint!(dists, n)
    @inbounds for i in 1:n
        i in exclude && continue
        d = 0.0
        for j in axes(data, 2)
            δ = Float64(data[i, j]) - Float64(query[j])
            d += δ * δ
        end
        push!(dists, (d, i))
    end
    length(dists) < K && throw(ArgumentError(
        "need at least $K neighbours after Theiler exclusion; got $(length(dists))",
    ))
    partialsort!(dists, 1:K; by = first)
    return [dists[i][2] for i in 1:K]
end

"""
    _mi_knn(Xp, Yp, k) -> Float64

Kraskov-style MI on paired neighbour residuals (Chebyshev metric), matching the
reference `MIknn` routine.
"""
function _mi_knn(Xp::AbstractMatrix{<:Real}, Yp::AbstractMatrix{<:Real}, k::Integer)
    Np = size(Xp, 1)
    Np < k + 1 && return 0.0
    # Deduplicate joint rows (stable unique)
    seen = Dict{Vector{Float64}, Int}()
    keep = Int[]
    @inbounds for i in 1:Np
        key = vcat(Float64.(Xp[i, :]), Float64.(Yp[i, :]))
        if !haskey(seen, key)
            seen[key] = i
            push!(keep, i)
        end
    end
    Xp = Xp[keep, :]
    Yp = Yp[keep, :]
    Np = size(Xp, 1)
    Np < k + 1 && return 0.0

    nX = zeros(Int, Np)
    nY = zeros(Int, Np)
    joint = hcat(Xp, Yp)
    @inbounds for i in 1:Np
        # Distances to all points in Chebyshev metric on joint space
        ds = Vector{Float64}(undef, Np)
        for j in 1:Np
            ds[j] = _chebyshev(view(joint, i, :), view(joint, j, :))
        end
        # k+1 because distance 0 to self is included
        partialsort!(ds, 1:(k + 1))
        ε = ds[k + 1]
        nx = 0
        ny = 0
        for j in 1:Np
            if _chebyshev(view(Xp, i, :), view(Xp, j, :)) < ε
                nx += 1
            end
            if _chebyshev(view(Yp, i, :), view(Yp, j, :)) < ε
                ny += 1
            end
        end
        nX[i] = nx
        nY[i] = ny
    end
    idN = (nX .!= 0) .& (nY .!= 0)
    count(idN) == 0 && return 0.0
    nX_ok = nX[idN]
    nY_ok = nY[idN]
    mean_ψx = sum(_digamma_int, nX_ok) / length(nX_ok)
    mean_ψy = sum(_digamma_int, nY_ok) / length(nY_ok)
    return abs(_digamma_int(k) - mean_ψx - mean_ψy + _digamma_int(Np))
end

"""
    delay_embed_cause(x, p) -> Matrix

Cause embedding `X_t = (x_t, …, x_{t-p+1})` with rows as time (length `T-p`).
`x` may be a vector (univariate) or `dx × T` matrix (variables × time).
"""
function delay_embed_cause(x::AbstractVector{<:Real}, p::Integer)
    T = length(x)
    T > p || throw(ArgumentError("series length must exceed embedding order p=$p"))
    X = zeros(T - p, p)
    @inbounds for i in 1:p
        X[:, i] .= @view x[(p + 1 - i):(T - i)]
    end
    return X
end

function delay_embed_cause(x::AbstractMatrix{<:Real}, p::Integer)
    dx, T = size(x)
    T > p || throw(ArgumentError("series length must exceed embedding order p=$p"))
    X = zeros(T - p, dx * p)
    @inbounds for i in 1:p
        cols = ((i - 1) * dx + 1):(i * dx)
        X[:, cols] .= transpose(@view x[:, (p + 1 - i):(T - i)])
    end
    return X
end

"""
    delay_embed_effect(y, p) -> Matrix

Effect embedding `Y_{t+1} = (y_{t+1}, y_t, …, y_{t-p+1})` (rows as time).
"""
function delay_embed_effect(y::AbstractVector{<:Real}, p::Integer)
    T = length(y)
    T > p || throw(ArgumentError("series length must exceed embedding order p=$p"))
    Y = zeros(T - p, p + 1)
    Y[:, 1] .= @view y[(p + 1):T]
    @inbounds for i in 1:p
        Y[:, i + 1] .= @view y[(p + 1 - i):(T - i)]
    end
    return Y
end

function delay_embed_effect(y::AbstractMatrix{<:Real}, p::Integer)
    dy, T = size(y)
    T > p || throw(ArgumentError("series length must exceed embedding order p=$p"))
    Y = zeros(T - p, dy * (p + 1))
    Y[:, 1:dy] .= transpose(@view y[:, (p + 1):T])
    @inbounds for i in 1:p
        cols = (i * dy + 1):((i + 1) * dy)
        Y[:, cols] .= transpose(@view y[:, (p + 1 - i):(T - i)])
    end
    return Y
end

"""
    interventional_embedding_entropy(x, y; p=1, k=2, theiler=nothing, n_delta=10, mi=:auto) -> Float64

Compute IEE from cause series `x` to effect series `y` (IntDC ranking score).

# Arguments
- `x`, `y`: univariate vectors, or `d × T` matrices (variables × time)
- `p`: embedding order (delay length)
- `k`: k-NN order for MI (`k ≥ 2`)
- `theiler`: half-width of Theiler window (defaults to `p`)
- `n_delta`: number of neighbours used as local perturbation proxies
- `mi`: mutual-information estimator — `:auto` (Associations KSG1 when loaded,
  else reference), `:associations` (requires `using Associations`), or
  `:reference` (MATLAB-faithful `MIknn` port for concordance tests)
- `backend`: deprecated alias for `mi` (kept for notebook sessions that still
  expect the old keyword)

# References
- Shi et al. (2026), *The Innovation*; arXiv:2407.01621
- Reference code: https://github.com/smsxiaomayi/IEE
"""
function interventional_embedding_entropy(
    x,
    y;
    p::Integer = 1,
    k::Integer = 2,
    theiler::Union{Nothing, Integer} = nothing,
    n_delta::Integer = 10,
    mi::Union{Nothing, Symbol} = nothing,
    backend::Union{Nothing, Symbol} = nothing,
)
    p < 1 && throw(ArgumentError("p must be ≥ 1"))
    k < 2 && throw(ArgumentError("k must be ≥ 2"))
    Thei = theiler === nothing ? p : Int(theiler)
    Thei < p && throw(ArgumentError("theiler half-width must be ≥ p"))

    est = _resolve_iee_mi(mi, backend)
    mi_fn = _iee_mi_estimator(est, k)

    X = delay_embed_cause(x, p)
    Y = delay_embed_effect(y, p)
    N = size(Y, 1)
    scores = Vector{Float64}(undef, N)
    @inbounds for i in 1:N
        ids = max(1, i - Thei)
        idf = min(i + Thei, N)
        exclude = Set(ids:idf)
        nn = _knn_indices(Y, view(Y, i, :), n_delta; exclude = exclude)
        Yp = Matrix{Float64}(undef, n_delta, size(Y, 2))
        Xp = Matrix{Float64}(undef, n_delta, size(X, 2))
        for (r, j) in enumerate(nn)
            @inbounds for c in axes(Y, 2)
                Yp[r, c] = Float64(Y[j, c]) - Float64(Y[i, c])
            end
            @inbounds for c in axes(X, 2)
                Xp[r, c] = Float64(X[j, c]) - Float64(X[i, c])
            end
        end
        scores[i] = mi_fn(Xp, Yp)
    end
    return sum(scores) / N
end

"""
    _resolve_iee_mi(mi, backend) -> Symbol

Resolve the IEE estimator keyword (`mi` preferred; `backend` is a deprecated alias).
"""
function _resolve_iee_mi(
    mi::Union{Nothing, Symbol},
    backend::Union{Nothing, Symbol},
)
    if mi !== nothing && backend !== nothing && mi !== backend
        throw(ArgumentError("conflicting mi=:$mi and backend=:$backend"))
    end
    mi !== nothing && return mi
    backend !== nothing && return backend
    return :auto
end

"""
    _iee_mi_estimator(mi, k) -> Function

Return `(Xp, Yp) -> score` for the chosen IEE mutual-information estimator.
"""
function _iee_mi_estimator(mi::Symbol, k::Integer)
    if mi === :reference
        return (Xp, Yp) -> _mi_knn(Xp, Yp, k)
    elseif mi === :associations
        has_associations() || error(
            "Associations MI estimator requires `using Associations` (and DataFrames).",
        )
        ext = Base.get_extension(@__MODULE__, :CausalDynamicsAssociationsExt)
        return (Xp, Yp) -> ext.iee_mi_associations(Xp, Yp; k = k)
    elseif mi === :auto
        if has_associations()
            ext = Base.get_extension(@__MODULE__, :CausalDynamicsAssociationsExt)
            return (Xp, Yp) -> ext.iee_mi_associations(Xp, Yp; k = k)
        end
        return (Xp, Yp) -> _mi_knn(Xp, Yp, k)
    else
        throw(ArgumentError("unknown IEE mi=:$mi (use :auto, :associations, or :reference)"))
    end
end

"""
    iee_score_matrix(series; variables=nothing, kwargs...) -> Matrix{Float64}

Pairwise IEE matrix for a vector of univariate series (`series[i]` is variable `i`).
Diagonal is zero. Keyword arguments are forwarded to
[`interventional_embedding_entropy`](@ref).
"""
function iee_score_matrix(
    series::AbstractVector{<:AbstractVector{<:Real}};
    kwargs...,
)
    m = length(series)
    S = zeros(m, m)
    for i in 1:m
        for j in 1:m
            i == j && continue
            S[i, j] = interventional_embedding_entropy(series[i], series[j]; kwargs...)
        end
    end
    return S
end

"""
    iee_to_temporal_spec(scores, variables; threshold, lag=1) -> TemporalDAGSpec

Convert an IEE score matrix into a [`TemporalDAGSpec`](@ref) by retaining directed
edges with score `≥ threshold` at lag `lag` (default 1: parent at `t-1`).
"""
function iee_to_temporal_spec(
    scores::AbstractMatrix{<:Real},
    variables::AbstractVector{Symbol};
    threshold::Real,
    lag::Integer = 1,
)
    m = length(variables)
    size(scores) == (m, m) || throw(ArgumentError(
        "scores size $(size(scores)) must be ($m, $m) for $(m) variables",
    ))
    lag < 0 && throw(ArgumentError("lag must be ≥ 0"))
    edges = Tuple{Symbol, Symbol, Int}[]
    for i in 1:m
        for j in 1:m
            i == j && continue
            if scores[i, j] ≥ threshold
                push!(edges, (variables[i], variables[j], Int(lag)))
            end
        end
    end
    return TemporalDAGSpec(collect(Symbol, variables), edges)
end

"""
    infer_iee_temporal_spec(series, variables; threshold, kwargs...) -> TemporalDAGSpec

Compute pairwise IEE and threshold into a [`TemporalDAGSpec`](@ref).
"""
function infer_iee_temporal_spec(
    series::AbstractVector{<:AbstractVector{<:Real}},
    variables::AbstractVector{Symbol};
    threshold::Real,
    lag::Integer = 1,
    kwargs...,
)
    length(series) == length(variables) || throw(ArgumentError(
        "length(series) must equal length(variables)",
    ))
    scores = iee_score_matrix(series; kwargs...)
    return iee_to_temporal_spec(scores, variables; threshold = threshold, lag = lag)
end

export interventional_embedding_entropy,
    iee_score_matrix,
    iee_to_temporal_spec,
    infer_iee_temporal_spec,
    delay_embed_cause,
    delay_embed_effect
