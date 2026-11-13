"""
    NonlinearGaussianStateResult

Scalar extended Kalman filtering and extended RTS smoothing for a known-noise
nonlinear transition. Gaussian moments describe the surrogate obtained by
linearising at filtering means, not an exact nonlinear posterior. Time is in
rows; the final filtering posterior supplies continuation. Slopes and offsets
have one entry per transition; predicted moments include the initial prior.
"""
struct NonlinearGaussianStateResult{M,R} <: AbstractGaussianStateResult
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
    linearisation_slopes::Vector{Float64}
    linearisation_offsets::Vector{Float64}
    predicted_means::Matrix{Float64}
    predicted_variances::Vector{Float64}
end

# Matrix-valued scalar factors reuse RxInfer's established multivariate Gaussian
# rules. Every coefficient is a declared constant in this surrogate graph.
@model function nonlinear_gaussian_surrogate(y, n, F, b, Q, μ, P, H, R, c)
    x[1] ~ MvNormal(μ = μ, Σ = P)
    for j in 2:n
        x[j] ~ MvNormal(μ = F[j - 1] * x[j - 1] + b[j - 1], Σ = Q)
    end
    for j in 1:n
        y[j] ~ MvNormal(μ = H * x[j] + c, Σ = R)
    end
end

_nonlinear_matrix(x) = reshape([x], 1, 1)

function _nonlinear_scalar(value, name; positive = false)
    value isa Real || throw(ArgumentError("$name must be a finite real scalar"))
    scalar = try
        Float64(value)
    catch
        throw(ArgumentError("$name must be representable as a finite Float64 scalar"))
    end
    isfinite(scalar) || throw(ArgumentError("$name must be a finite real scalar"))
    positive && scalar <= 0 && throw(ArgumentError("$name must be strictly positive"))
    return scalar
end

function _nonlinear_time(value, n)
    value isa Integer && !(value isa Bool) || throw(ArgumentError("initial_time must be an integer"))
    # Leave room for all represented times, including the end time consumed by
    # a subsequent continuation. Arithmetic must never wrap to another time.
    typemin(Int) <= value <= typemax(Int) - n ||
        throw(ArgumentError("initial_time and observation count exceed the supported integer time range"))
    return Int(value)
end

function _nonlinear_model(; transition, transition_derivative, process_variance,
    observation_variance, initial_mean, initial_variance, observation = 1.0,
    observation_offset = 0.0, initial_time = 0)
    μ = _nonlinear_scalar(initial_mean, "initial_mean")
    P = _nonlinear_scalar(initial_variance, "initial_variance"; positive = true)
    Q = _nonlinear_scalar(process_variance, "process_variance"; positive = true)
    R = _nonlinear_scalar(observation_variance, "observation_variance"; positive = true)
    h = _nonlinear_scalar(observation, "observation")
    c = _nonlinear_scalar(observation_offset, "observation_offset")
    t = _nonlinear_time(initial_time, 1)
    applicable(transition, μ, t) || throw(ArgumentError("transition must accept (state, model_time)"))
    applicable(transition_derivative, μ, t) || throw(ArgumentError("transition_derivative must accept (state, model_time)"))
    return (transition = transition, transition_derivative = transition_derivative,
        process_variance = Q, observation_variance = R, initial_mean = μ,
        initial_variance = P, observation = h, observation_offset = c, initial_time = t)
end

function _nonlinear_data(observations)
    observations isa AbstractVector || throw(ArgumentError("observations must be a nonempty scalar-observation vector"))
    isempty(observations) && throw(ArgumentError("observations must contain at least one time"))
    return Union{Missing,Float64}[ismissing(y) ? missing : _nonlinear_scalar(y, "observation value") for y in observations]
end

function _nonlinear_callback(callback, x, t, name)
    value = try
        callback(x, t)
    catch exception
        exception isa InterruptException && rethrow()
        throw(ArgumentError("$name failed at model time $t: $(sprint(showerror, exception))"))
    end
    return _nonlinear_scalar(value, "$name at model time $t")
end

function _nonlinear_forecast(μ, P, model, t)
    F = _nonlinear_callback(model.transition_derivative, μ, t, "transition_derivative")
    a = _nonlinear_callback(model.transition, μ, t, "transition")
    b = _nonlinear_scalar(a - F * μ, "linearisation offset at model time $t")
    variance = _nonlinear_scalar(F^2 * P + model.process_variance,
        "predicted variance at model time $(t + 1)"; positive = true)
    return a, variance, F, b
end

function _nonlinear_filter(data, model)
    n = length(data)
    _nonlinear_time(model.initial_time, n)
    means = zeros(n, 1)
    covariances = Vector{Matrix{Float64}}(undef, n)
    gains = Vector{Matrix{Float64}}(undef, n)
    predicted_means, predicted_variances = zeros(n, 1), zeros(n)
    slopes, offsets = zeros(n - 1), zeros(n - 1)
    μ, P = model.initial_mean, model.initial_variance
    h, c, R = model.observation, model.observation_offset, model.observation_variance
    for j in 1:n
        t = model.initial_time + j - 1
        if j > 1
            μ, P, slopes[j - 1], offsets[j - 1] = _nonlinear_forecast(μ, P, model, t - 1)
        end
        predicted_means[j, 1], predicted_variances[j] = μ, P
        if ismissing(data[j])
            gains[j] = zeros(1, 0)
        else
            S = _nonlinear_scalar(h^2 * P + R, "innovation variance at model time $t"; positive = true)
            K = _nonlinear_scalar(P * h / S, "filter gain at model time $t")
            μ = _nonlinear_scalar(μ + K * (data[j] - h * μ - c), "filtered mean at model time $t")
            P = _nonlinear_scalar((1 - K * h)^2 * P + K^2 * R,
                "filtered variance at model time $t"; positive = true)
            gains[j] = _nonlinear_matrix(K)
        end
        means[j, 1], covariances[j] = μ, _nonlinear_matrix(P)
    end
    smoothing_gains = [_nonlinear_matrix(_nonlinear_scalar(only(covariances[j]) * slopes[j] / predicted_variances[j + 1],
        "smoothing gain at model time $(model.initial_time + j - 1)")) for j in 1:(n - 1)]
    return (; means, covariances, gains, predicted_means, predicted_variances, slopes, offsets, smoothing_gains)
end

function _nonlinear_rts(filtering, model)
    means, covariances = copy(filtering.means), copy(filtering.covariances)
    for j in (size(means, 1) - 1):-1:1
        J = only(filtering.smoothing_gains[j])
        t = model.initial_time + j - 1
        means[j, 1] = _nonlinear_scalar(filtering.means[j, 1] + J * (means[j + 1, 1] - filtering.predicted_means[j + 1, 1]),
            "smoothed mean at model time $t")
        P = _nonlinear_scalar(only(filtering.covariances[j]) + J^2 * (only(covariances[j + 1]) - filtering.predicted_variances[j + 1]),
            "smoothed variance at model time $t"; positive = true)
        covariances[j] = _nonlinear_matrix(P)
    end
    return means, covariances
end

function _nonlinear_surrogate(data, filtering, model)
    n = length(data)
    raw = infer(model = nonlinear_gaussian_surrogate(n = n,
            F = _nonlinear_matrix.(filtering.slopes), b = [[b] for b in filtering.offsets],
            Q = _nonlinear_matrix(model.process_variance), μ = [model.initial_mean],
            P = _nonlinear_matrix(model.initial_variance), H = _nonlinear_matrix(model.observation),
            R = _nonlinear_matrix(model.observation_variance), c = [model.observation_offset]),
        data = (y = [[Float64(y)] for y in data],),
        returnvars = (x = KeepLast(),), options = (limit_stack_depth = 500,))
    marginals = raw.posteriors[:x]
    means, covariances = zeros(n, 1), Vector{Matrix{Float64}}(undef, n)
    for j in 1:n
        means[j, 1] = _nonlinear_scalar(only(mean(marginals[j])), "surrogate smoothed mean at row $j")
        covariances[j] = _nonlinear_matrix(_nonlinear_scalar(only(cov(marginals[j])),
            "surrogate smoothed variance at row $j"; positive = true))
    end
    return means, covariances, raw
end

"""
    infer_nonlinear_state_space(observations; transition, transition_derivative,
        process_variance, observation_variance, initial_mean, initial_variance,
        observation=1.0, observation_offset=0.0, initial_time=0)

Filter and smooth scalar states with a declared nonlinear transition `f(x,t)`
and its state derivative. The prior belongs to model time `initial_time`; the
first observation updates that prior without a transition. Process and
measurement variances are known positive constants. Missing observations omit
their likelihood. Callbacks must be deterministic and return finite scalars.

Linearisation at successive filtering means defines a Gaussian surrogate.
Complete observations with nonzero observation coefficient use exact RxInfer
sum-product inference for that surrogate. Missing observations or a zero
coefficient use analytic extended RTS smoothing. Both backends approximate the
original nonlinear posterior; `certificate.exact` is always false. No parameters
are fitted and no variational iteration is performed.
"""
function infer_nonlinear_state_space(observations; kwargs...)
    data, model = _nonlinear_data(observations), _nonlinear_model(; kwargs...)
    filtering = _nonlinear_filter(data, model)
    reason = any(ismissing, data) ? :incomplete_measurements :
        iszero(model.observation) ? :zero_observation : :gaussian_sum_product
    backend = reason == :gaussian_sum_product ? :rxinfer : :analytic_rts
    if backend == :rxinfer
        means, covariances, raw = _nonlinear_surrogate(data, filtering, model)
    else
        means, covariances = _nonlinear_rts(filtering, model)
        raw = nothing
    end
    certificate = (exact = false, parameters = :known, approximation = :extended_kalman_rts,
        linearisation = :filtering_means, covariance = :local_gaussian,
        initial_time = model.initial_time, backend = backend, reason = reason,
        surrogate_exact = true, missing_measurements = :omit_likelihood_components)
    posterior = (mean = copy(filtering.means[end, :]), covariance = copy(filtering.covariances[end]))
    return NonlinearGaussianStateResult(filtering.means, filtering.covariances,
        means, covariances, filtering.smoothing_gains, filtering.gains, posterior,
        model, raw, length(data), backend, certificate, filtering.slopes,
        filtering.offsets, filtering.predicted_means, filtering.predicted_variances)
end

"""
    update_state_posterior(previous::NonlinearGaussianStateResult, observations; kwargs...)

Continue one transition after the previous final filtered posterior, reusing
stored callbacks and constants unless explicitly changed. The forecast callback
time is the previous final represented model time. Initial-prior and time
keywords cannot be overridden. Smoothing and joint covariance cover only the
new segment; earlier observations are not assimilated again.
"""
function update_state_posterior(previous::NonlinearGaussianStateResult, observations; kwargs...)
    any(key -> haskey(kwargs, key), (:initial_mean, :initial_variance, :initial_time)) &&
        throw(ArgumentError("continuation derives initial_mean, initial_variance and initial_time from the previous filtering posterior; these cannot be overridden"))
    data = _nonlinear_data(observations)
    model = _nonlinear_model(; merge(previous.model, (;kwargs...))...)
    time = previous.model.initial_time + previous.n - 1
    _nonlinear_time(time, length(data) + 1)
    μ, P, _, _ = _nonlinear_forecast(only(previous.posterior.mean), only(previous.posterior.covariance), model, time)
    prior = (initial_mean = μ, initial_variance = P, initial_time = time + 1)
    return infer_nonlinear_state_space(data; merge(model, prior)...)
end
