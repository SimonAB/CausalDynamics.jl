"""
    BoostedControlFunctionFit

Fitted linear boosted control-function predictor. `M` is the estimated
reduced-form coefficient in `X = M * Z + V`; `R` spans the left null space
of `M`; and `f_coefficients` and `δ_coefficients` define the fitted BCF.

This is a dependency-free linear reference implementation of the estimator in
Gnecco et al. (2026). Nonlinear learners can be layered on the same three
stages, but are deliberately not hidden behind this small API.
"""
struct BoostedControlFunctionFit{T<:Real}
    M::Matrix{T}
    R::Matrix{T}
    V::Matrix{T}
    x_mean::Vector{T}
    y_mean::T
    f_coefficients::Vector{T}
    δ_coefficients::Vector{T}
end

"""
    boosted_control_function(X, Y, Z; ridge=0.0)

Fit the linear boosted control function (BCF) from observations of endogenous
covariates `X`, outcome `Y`, and exogenous shift variables `Z`.

The implementation follows Algorithm 1 of Gnecco, Peters, Engelke and Pfister
(2026): estimate `M`, form the control variable `V = X - M Z`, fit an additive
regression of `Y` on `(X, V)`, then project its control-function contribution
onto the invariant coordinates `R'X`. `ridge` provides optional Tikhonov
regularisation for ill-conditioned design matrices.

The returned object predicts the BCF target, which is a robust predictive
function under the paper's SIMDG assumptions; it is not automatically a causal
effect estimator.
"""
function boosted_control_function(
    X::AbstractMatrix{<:Real},
    Y::AbstractVector{<:Real},
    Z::AbstractMatrix{<:Real};
    ridge::Real = 0.0,
)
    n, p = size(X)
    size(Z, 1) == n || throw(DimensionMismatch("X and Z must have the same number of rows"))
    length(Y) == n || throw(DimensionMismatch("Y must have one value per row of X"))
    ridge >= 0 || throw(ArgumentError("ridge must be non-negative"))
    n > 0 || throw(ArgumentError("X, Y and Z must not be empty"))

    T = Float64
    x_mean = vec(mean(Matrix{T}(X), dims = 1))
    z_mean = vec(mean(Matrix{T}(Z), dims = 1))
    y_mean = T(mean(Y))
    Xc = Matrix{T}(X) .- reshape(x_mean, 1, p)
    Zc = Matrix{T}(Z) .- reshape(z_mean, 1, size(Z, 2))
    yc = T.(Y) .- y_mean
    rank(Zc) > 0 || throw(ArgumentError("Z must vary to identify a control variable"))

    # Reduced form and control variable, with M shaped p × r as in the paper.
    M = Xc' * Zc * _regularised_pinv(Zc' * Zc, ridge)
    V = Xc - Zc * M'

    # R spans ker(M'). SVD is stable when M is rank deficient.
    svd_M = svd(M'; full = true)
    tolerance = maximum(size(M')) * eps(T) * (isempty(svd_M.S) ? zero(T) : maximum(svd_M.S))
    q = count(>(tolerance), svd_M.S)
    R = q < p ? svd_M.V[:, (q + 1):p] : zeros(T, p, 0)

    additive = hcat(Xc, V)
    coefficients = _ridge_coefficients(additive, yc, ridge)
    f_coefficients = coefficients[1:p]
    γ_coefficients = coefficients[(p + 1):(2p)]
    γ̂ = V * γ_coefficients

    δ_coefficients = if size(R, 2) == 0
        [T(mean(γ̂))]
    else
        W = Xc * R
        _ridge_coefficients(W, γ̂, ridge)
    end

    return BoostedControlFunctionFit(M, R, V, x_mean, y_mean, f_coefficients, δ_coefficients)
end

"""
    predict(fit::BoostedControlFunctionFit, X)

Predict outcomes with a fitted boosted control function. Call
`CausalDynamics.predict(fit, X)` (`predict` is not exported, to avoid clashing
with StatsAPI / GLM). New rows of `X` must have the same covariate ordering
and number of columns as the training data.
"""
function predict(fit::BoostedControlFunctionFit, X::AbstractMatrix{<:Real})
    size(X, 2) == length(fit.x_mean) ||
        throw(DimensionMismatch("X has the wrong number of covariates"))
    Xc = Matrix{Float64}(X) .- reshape(fit.x_mean, 1, length(fit.x_mean))
    prediction = fit.y_mean .+ Xc * fit.f_coefficients
    if size(fit.R, 2) == 0
        prediction .+= fit.δ_coefficients[1]
    else
        prediction .+= (Xc * fit.R) * fit.δ_coefficients
    end
    return vec(prediction)
end

function _regularised_pinv(A::AbstractMatrix{T}, ridge::Real) where {T<:Real}
    ridge == 0 && return pinv(A)
    return pinv(A + T(ridge) * I)
end

function _ridge_coefficients(A::AbstractMatrix{T}, y::AbstractVector{T}, ridge::Real) where {T<:Real}
    gram = A' * A
    rhs = A' * y
    ridge == 0 && return pinv(A) * y
    return (gram + T(ridge) * I) \ rhs
end

export BoostedControlFunctionFit, boosted_control_function
