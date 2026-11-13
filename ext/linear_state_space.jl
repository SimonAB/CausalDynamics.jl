using LinearAlgebra: I, Symmetric, cholesky, issymmetric, PosDefException, rank
using Statistics: mean, cov
using RxInfer: MvNormal

"""
    LinearStateSpaceResult

Exact Gaussian state marginals with known, constant model matrices. Means have
time in rows; covariance vectors hold one state covariance per time. `posterior`
is the final filtering distribution, used by `update_state_posterior`.
`smoothing_gains` reconstruct cross-time covariances without storing a dense
trajectory covariance. `backend` identifies `:rxinfer` or `:analytic_rts`.
`raw` retains the RxInfer batch inference result when that backend is used.
Rank-deficient or incomplete measurements use an exact analytic smoother because
RxInfer's covariance-form backward messages require nonsingular information.
"""
struct LinearStateSpaceResult{M,R}
    filtering_means::Matrix{Float64}
    filtering_covariances::Vector{Matrix{Float64}}
    smoothing_means::Matrix{Float64}
    smoothing_covariances::Vector{Matrix{Float64}}
    smoothing_gains::Vector{Matrix{Float64}}
    filtering_gains::Vector{Matrix{Float64}}
    posterior::NamedTuple{(:mean, :covariance),Tuple{Vector{Float64},Matrix{Float64}}}
    model::M
    raw::R
    n::Int
    backend::Symbol
    certificate::NamedTuple
end

# The latent chain remains jointly Gaussian: no mean-field constraints or
# variational iteration are used. Observed components are subset before graph
# construction so missing values never enter numerical messages.
@model function linear_gaussian_state_model(y, n, F, Q, μ, P, b, H, R, c, times)
    x[1] ~ MvNormal(μ = μ, Σ = P)
    for t in 2:n
        x[t] ~ MvNormal(μ = F * x[t - 1] + b, Σ = Q)
    end
    for k in 1:length(times)
        y[k] ~ MvNormal(μ = H[k] * x[times[k]] + c[k], Σ = R[k])
    end
end

function _linear_matrix(value, name)
    matrix = value isa Real ? reshape([Float64(value)], 1, 1) : Matrix{Float64}(value)
    all(isfinite, matrix) || throw(ArgumentError("$name must contain finite real values"))
    return matrix
end

function _linear_vector(value, name)
    vector = value isa Real ? [Float64(value)] : Vector{Float64}(value)
    all(isfinite, vector) || throw(ArgumentError("$name must contain finite real values"))
    return vector
end

function _linear_covariance(value, dimension, name)
    matrix = _linear_matrix(value, name)
    size(matrix) == (dimension, dimension) || throw(DimensionMismatch("$name must be $dimension × $dimension"))
    issymmetric(matrix) || throw(ArgumentError("$name must be symmetric"))
    try
        cholesky(Symmetric(matrix))
    catch error
        error isa PosDefException || rethrow()
        throw(ArgumentError("$name must be positive definite"))
    end
    return matrix
end

function _linear_model(; transition, observation, process_covariance,
    observation_covariance, initial_mean, initial_covariance,
    transition_offset = nothing, observation_offset = nothing)
    μ = _linear_vector(initial_mean, "initial_mean")
    d = length(μ)
    d > 0 || throw(ArgumentError("initial_mean must be nonempty"))
    F, H = _linear_matrix(transition, "transition"), _linear_matrix(observation, "observation")
    size(F) == (d, d) || throw(DimensionMismatch("transition must be $d × $d"))
    size(H, 2) == d || throw(DimensionMismatch("observation must have $d state columns"))
    m = size(H, 1)
    m > 0 || throw(ArgumentError("observation must have at least one measurement row"))
    Q = _linear_covariance(process_covariance, d, "process_covariance")
    R = _linear_covariance(observation_covariance, m, "observation_covariance")
    P = _linear_covariance(initial_covariance, d, "initial_covariance")
    b = isnothing(transition_offset) ? zeros(d) : _linear_vector(transition_offset, "transition_offset")
    c = isnothing(observation_offset) ? zeros(m) : _linear_vector(observation_offset, "observation_offset")
    length(b) == d || throw(DimensionMismatch("transition_offset must have $d entries"))
    length(c) == m || throw(DimensionMismatch("observation_offset must have $m entries"))
    return (transition = F, observation = H, process_covariance = Q,
        observation_covariance = R, initial_mean = μ, initial_covariance = P,
        transition_offset = b, observation_offset = c)
end

function _linear_observations(observations, measurement_dimension)
    observations isa Union{AbstractVector,AbstractMatrix} ||
        throw(ArgumentError("observations must be a matrix with time in rows or a scalar-observation vector"))
    data = observations isa AbstractVector ? reshape(observations, :, 1) : observations
    size(data, 1) > 0 || throw(ArgumentError("observations must contain at least one time"))
    size(data, 2) == measurement_dimension || throw(DimensionMismatch("observations must have $measurement_dimension columns"))
    all(value -> ismissing(value) || (value isa Real && isfinite(value)), data) ||
        throw(ArgumentError("observations must contain finite real values or missing"))
    return data
end

_linear_symmetric(matrix) = Matrix(Symmetric((matrix + matrix') / 2))

function _linear_filter(data, model)
    F, H = model.transition, model.observation
    Q, R = model.process_covariance, model.observation_covariance
    μ, P = model.initial_mean, model.initial_covariance
    b, c = model.transition_offset, model.observation_offset
    n, d = size(data, 1), length(μ)
    means, covariances = zeros(n, d), Vector{Matrix{Float64}}(undef, n)
    predicted = Vector{Matrix{Float64}}(undef, n)
    gains = Vector{Matrix{Float64}}(undef, n)
    current_mean, current_covariance = copy(μ), copy(P)
    for t in 1:n
        if t > 1
            current_mean = F * current_mean + b
            current_covariance = _linear_symmetric(F * current_covariance * F' + Q)
        end
        predicted[t] = current_covariance
        indices = findall(!ismissing, data[t, :])
        H_t, R_t = H[indices, :], R[indices, indices]
        if isempty(indices)
            gains[t] = zeros(d, 0)
        else
            innovation_covariance = _linear_symmetric(H_t * current_covariance * H_t' + R_t)
            K = (current_covariance * H_t') / cholesky(Symmetric(innovation_covariance))
            current_mean += K * (Float64.(data[t, indices]) - H_t * current_mean - c[indices])
            residual_map = Matrix{Float64}(I, d, d) - K * H_t
            current_covariance = _linear_symmetric(residual_map * current_covariance * residual_map' + K * R_t * K')
            gains[t] = K
        end
        means[t, :] = current_mean
        covariances[t] = current_covariance
    end
    smoothing_gains = [covariances[t] * F' / cholesky(Symmetric(predicted[t + 1])) for t in 1:(n - 1)]
    return means, covariances, gains, smoothing_gains, predicted
end

function _linear_rts(means, covariances, smoothing_gains, predicted, model)
    smoothed_means = copy(means)
    smoothed_covariances = copy(covariances)
    for t in (size(means, 1) - 1):-1:1
        J = smoothing_gains[t]
        predicted_mean = model.transition * means[t, :] + model.transition_offset
        smoothed_means[t, :] = means[t, :] + J * (smoothed_means[t + 1, :] - predicted_mean)
        smoothed_covariances[t] = _linear_symmetric(covariances[t] + J * (smoothed_covariances[t + 1] - predicted[t + 1]) * J')
    end
    return smoothed_means, smoothed_covariances
end

"""
    infer_linear_state_space(observations; transition, observation,
        process_covariance, observation_covariance, initial_mean,
        initial_covariance, transition_offset=nothing, observation_offset=nothing)

Infer exact state marginals for a linear Gaussian model with known, constant
matrices. The prior is for the first represented state `x[1]`; transitions follow
`x[t+1] = transition*x[t] + transition_offset + ε[t]`. Measurements obey
`y[t] = observation*x[t] + observation_offset + η[t]`.

Supply observations as time × measurement rows, or a vector for scalar
measurements. `missing` components remove only their corresponding measurement
likelihood; correlated measurement errors are subset jointly. All covariance
matrices must be symmetric positive definite. Scalars are accepted in one
dimension. RxInfer Gaussian sum-product messages produce smoothed marginals for
fully observed, full-column-rank measurement matrices. Incomplete or
rank-deficient measurements use exact analytic Rauch–Tung–Striebel smoothing,
reported by `result.backend == :analytic_rts` and `result.raw === nothing`.
This avoids singular backward-message conversion in RxInfer's covariance-form
Gaussian rules. The filtering recursion retains the posterior needed for
incremental updates. Exactness conditions on the supplied known matrices.
"""
function infer_linear_state_space(observations; kwargs...)
    model = _linear_model(; kwargs...)
    data = _linear_observations(observations, size(model.observation, 1))
    n, d = size(data, 1), length(model.initial_mean)
    filtering_means, filtering_covariances, filtering_gains, smoothing_gains, predicted = _linear_filter(data, model)
    fallback_reason = any(ismissing, data) ? :incomplete_measurements :
        rank(model.observation) < d ? :rank_deficient_observation : nothing
    if !isnothing(fallback_reason)
        smoothed_means, smoothed_covariances = _linear_rts(filtering_means,
            filtering_covariances, smoothing_gains, predicted, model)
        posterior = (mean = copy(filtering_means[end, :]), covariance = copy(filtering_covariances[end]))
        certificate = (exact = true, matrices = :known, backend = :analytic_rts,
            reason = fallback_reason, missing_measurements = :omit_likelihood_components)
        return LinearStateSpaceResult(filtering_means, filtering_covariances,
            smoothed_means, smoothed_covariances, smoothing_gains,
            filtering_gains, posterior, model, nothing, n, :analytic_rts, certificate)
    end
    times, values = Int[], Vector{Float64}[]
    H, R, c = Matrix{Float64}[], Matrix{Float64}[], Vector{Float64}[]
    for t in 1:n
        indices = findall(!ismissing, data[t, :])
        isempty(indices) && continue
        push!(times, t)
        push!(values, Float64.(data[t, indices]))
        push!(H, model.observation[indices, :])
        push!(R, model.observation_covariance[indices, indices])
        push!(c, model.observation_offset[indices])
    end
    raw = infer(
        model = linear_gaussian_state_model(n = n, F = model.transition,
            Q = model.process_covariance, μ = model.initial_mean,
            P = model.initial_covariance, b = model.transition_offset,
            H = H, R = R, c = c, times = times),
        data = isempty(times) ? (;) : (y = values,),
        returnvars = (x = KeepLast(),), options = (limit_stack_depth = 500,))
    marginals = raw.posteriors[:x]
    smoothed_means = zeros(n, d)
    smoothed_covariances = Vector{Matrix{Float64}}(undef, n)
    for t in 1:n
        smoothed_means[t, :] = mean(marginals[t])
        smoothed_covariances[t] = _linear_symmetric(cov(marginals[t]))
    end
    posterior = (mean = copy(filtering_means[end, :]), covariance = copy(filtering_covariances[end]))
    certificate = (exact = true, matrices = :known, backend = :rxinfer,
        reason = :gaussian_sum_product, missing_measurements = :omit_likelihood_components)
    return LinearStateSpaceResult(filtering_means, filtering_covariances,
        smoothed_means, smoothed_covariances, smoothing_gains, filtering_gains,
        posterior, model, raw, n, :rxinfer, certificate)
end

"""
    update_state_posterior(previous::LinearStateSpaceResult, new_observations; kwargs...)

Infer states for new observations only, starting one transition after the final
filtering posterior in `previous`. Reuse the stored model unless model keywords
are supplied. Returned smoothing covers the new segment; past states are not
recomputed or assimilated twice. Initial-prior keywords are rejected because
continuation must start from the previous filtering posterior.
"""
function update_state_posterior(previous::LinearStateSpaceResult, new_observations; kwargs...)
    any(key -> haskey(kwargs, key), (:initial_mean, :initial_covariance)) &&
        throw(ArgumentError("continuation derives its initial prior from the previous filtering posterior; initial_mean and initial_covariance cannot be overridden"))
    model = _linear_model(; merge(previous.model, (; kwargs...))...)
    F, Q, b = model.transition, model.process_covariance, model.transition_offset
    prior = (initial_mean = F * previous.posterior.mean + b,
        initial_covariance = _linear_symmetric(F * previous.posterior.covariance * F' + Q))
    return infer_linear_state_space(new_observations; merge(model, prior)...)
end

"""
    state_crosscovariance(result::LinearStateSpaceResult, t, s)

Return `Cov(x[t], x[s] | all observations)` as a state × state matrix. State
indices are one-based, matching result rows. Covariance orientation follows the
argument order; reversing the indices transposes the returned block.
"""
function state_crosscovariance(result::LinearStateSpaceResult, t::Integer, s::Integer)
    1 <= t <= result.n || throw(BoundsError(result.smoothing_covariances, t))
    1 <= s <= result.n || throw(BoundsError(result.smoothing_covariances, s))
    t > s && return Matrix(state_crosscovariance(result, s, t)')
    covariance = copy(result.smoothing_covariances[s])
    for k in (s - 1):-1:t
        covariance = result.smoothing_gains[k] * covariance
    end
    return covariance
end

"""
    trajectory_covariance(result::LinearStateSpaceResult)

Materialise the full smoothed trajectory covariance in time-major order
`[x[1]; x[2]; …]`. Storage is quadratic in the number of states and times;
use `state_crosscovariance` when only selected blocks are needed.
"""
function trajectory_covariance(result::LinearStateSpaceResult)
    d = size(result.smoothing_means, 2)
    covariance = zeros(result.n * d, result.n * d)
    for s in 1:result.n
        block = copy(result.smoothing_covariances[s])
        cols = ((s - 1) * d + 1):(s * d)
        for t in s:-1:1
            rows = ((t - 1) * d + 1):(t * d)
            covariance[rows, cols] = block
            covariance[cols, rows] = block'
            t > 1 && (block = result.smoothing_gains[t - 1] * block)
        end
    end
    return covariance
end
