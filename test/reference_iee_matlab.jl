# Faithful port of https://github.com/smsxiaomayi/IEE `IEE.m` / `MIknn`
# (MATLAB Statistics Toolbox knnsearch + psi). Used only in tests for concordance.

"""Euclidean k-NN indices into rows of `data`, excluding Theiler window around `i`."""
function _matlab_knn_euclid(data::Matrix{Float64}, i::Int, K::Int, theiler::Int)
    N = size(data, 1)
    ids = max(1, i - theiler)
    idf = min(i + theiler, N)
    candidates = Int[]
    dists = Float64[]
    @inbounds for j in 1:N
        (ids ≤ j ≤ idf) && continue
        d = 0.0
        for c in axes(data, 2)
            δ = data[j, c] - data[i, c]
            d += δ * δ
        end
        push!(candidates, j)
        push!(dists, d)
    end
    length(candidates) < K && error("not enough neighbours")
    ord = partialsortperm(dists, 1:K)
    return candidates[ord]
end

function _matlab_chebyshev(a::AbstractVector, b::AbstractVector)
    d = 0.0
    @inbounds for i in eachindex(a, b)
        d = max(d, abs(a[i] - b[i]))
    end
    return d
end

function _matlab_digamma_int(n::Int)
    γ = 0.5772156649015328606
    s = -γ
    for i in 1:(n - 1)
        s += 1 / i
    end
    return s
end

"""MATLAB-faithful `MIknn` on residual matrices (rows = neighbours)."""
function matlab_miknn(XpNN::Matrix{Float64}, YpNN::Matrix{Float64}, k::Int)
    # unique(..., 'rows', 'stable')
    Np0 = size(XpNN, 1)
    keep = Int[]
    seen = Set{Vector{Float64}}()
    @inbounds for i in 1:Np0
        key = vcat(XpNN[i, :], YpNN[i, :])
        if !(key in seen)
            push!(seen, key)
            push!(keep, i)
        end
    end
    Xp = XpNN[keep, :]
    Yp = YpNN[keep, :]
    Np = size(Xp, 1)
    Np < k + 1 && return 0.0
    joint = hcat(Xp, Yp)
    nX = zeros(Int, Np)
    nY = zeros(Int, Np)
    @inbounds for i in 1:Np
        ds = [_matlab_chebyshev(view(joint, i, :), view(joint, j, :)) for j in 1:Np]
        partialsort!(ds, 1:(k + 1))
        ε = ds[k + 1]
        nX[i] = count(j -> _matlab_chebyshev(view(Xp, i, :), view(Xp, j, :)) < ε, 1:Np)
        nY[i] = count(j -> _matlab_chebyshev(view(Yp, i, :), view(Yp, j, :)) < ε, 1:Np)
    end
    idN = (nX .!= 0) .& (nY .!= 0)
    count(idN) == 0 && return 0.0
    return abs(
        _matlab_digamma_int(k) -
        sum(_matlab_digamma_int, nX[idN]) / count(idN) -
        sum(_matlab_digamma_int, nY[idN]) / count(idN) +
        _matlab_digamma_int(Np),
    )
end

"""
MATLAB-faithful `IEE(x, y, p, k, Thei, Ndelta)` for univariate series
(`x`, `y` as length-`T` vectors ≡ 1×T matrices in MATLAB).
"""
function matlab_iee(
    x::AbstractVector{<:Real},
    y::AbstractVector{<:Real};
    p::Int = 1,
    k::Int = 2,
    theiler::Int = p,
    n_delta::Int = 10,
)
    T = length(x)
    length(y) == T || throw(ArgumentError("x and y must have equal length"))
    # Embeddings as in IEE.m (rows = time)
    X = zeros(T - p, p)
    for i in 1:p
        X[:, i] .= x[(p + 1 - i):(T - i)]
    end
    Y = zeros(T - p, p + 1)
    Y[:, 1] .= y[(p + 1):T]
    for i in 1:p
        Y[:, i + 1] .= y[(p + 1 - i):(T - i)]
    end
    N = T - p
    out = zeros(N)
    for i in 1:N
        nn = _matlab_knn_euclid(Y, i, n_delta, theiler)
        Yp = Matrix{Float64}(undef, n_delta, size(Y, 2))
        Xp = Matrix{Float64}(undef, n_delta, size(X, 2))
        for (r, j) in enumerate(nn)
            Yp[r, :] .= Y[j, :] .- Y[i, :]
            Xp[r, :] .= X[j, :] .- X[i, :]
        end
        out[i] = matlab_miknn(Xp, Yp, k)
    end
    return sum(out) / N
end
