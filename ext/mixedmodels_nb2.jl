"""Dedicated subject-integrated NB2/log/random-intercept fitting backend."""

struct _NB2FitData
    y::Vector{Float64}
    X::Matrix{Float64}
    groups::Vector{Vector{Int}}
    nodes::Vector{Float64}
    logweights::Vector{Float64}
    logfactorials::Vector{Float64}
    quadrature_method::Symbol
end

@inline function _softplus(x::Float64)
    x > 0 ? x + log1p(exp(-x)) : log1p(exp(x))
end

@inline function _logistic(x::Float64)
    if x >= 0
        z = exp(-x)
        return 1 / (1 + z)
    end
    z = exp(x)
    return z / (1 + z)
end

function _stable_logsumexp(values::AbstractVector{Float64})
    maximum_value = maximum(values)
    isfinite(maximum_value) || return maximum_value
    return maximum_value + log(sum(exp(value - maximum_value) for value in values))
end

function _nb2_logpmf(y::Real, eta::Real, theta::Real)
    y >= 0 || throw(DomainError(y, "NB2 counts must be nonnegative"))
    theta > 0 || throw(DomainError(theta, "NB2 theta must be positive"))
    yf = Float64(y)
    etaf = Float64(eta)
    thetaf = Float64(theta)
    logtheta = log(thetaf)
    logdenominator = logtheta + _softplus(etaf - logtheta)
    return loggamma(yf + thetaf) - loggamma(thetaf) - loggamma(yf + 1) +
        thetaf * (logtheta - logdenominator) + yf * (etaf - logdenominator)
end

function _nb2_likelihood_fixed(
    fitdata::_NB2FitData,
    parameters::AbstractVector{<:Real};
    fixed_logtheta::Union{Nothing, Float64} = nothing,
    gradient::Bool = true,
)
    p = size(fitdata.X, 2)
    expected_length = p + (fixed_logtheta === nothing ? 2 : 1)
    length(parameters) == expected_length || throw(DimensionMismatch(
        "parameter vector has length $(length(parameters)); expected $expected_length",
    ))
    beta = view(parameters, 1:p)
    logsigma = Float64(parameters[p + 1])
    logtheta = fixed_logtheta === nothing ? Float64(parameters[p + 2]) : fixed_logtheta
    sigma = exp(logsigma)
    theta_value = exp(logtheta)
    if !(isfinite(sigma) && sigma > 0 && isfinite(theta_value) && theta_value > 0)
        return -Inf, fill(NaN, expected_length)
    end

    eta_fixed = fitdata.X * beta
    all(isfinite, eta_fixed) || return -Inf, fill(NaN, expected_length)
    psi_theta = digamma(theta_value)
    gamma_terms = similar(fitdata.y)
    psi_differences = gradient ? similar(fitdata.y) : Float64[]
    for observation in eachindex(fitdata.y)
        y = fitdata.y[observation]
        gamma_terms[observation] =
            loggamma(y + theta_value) - loggamma(theta_value) -
            fitdata.logfactorials[observation]
        gradient && (psi_differences[observation] = digamma(y + theta_value) - psi_theta)
    end

    q = length(fitdata.nodes)
    log_terms = Vector{Float64}(undef, q)
    score_beta = gradient ? Matrix{Float64}(undef, q, p) : Matrix{Float64}(undef, 0, 0)
    score_logsigma = gradient ? Vector{Float64}(undef, q) : Float64[]
    score_logtheta = gradient ? Vector{Float64}(undef, q) : Float64[]
    total_loglikelihood = 0.0
    total_gradient = gradient ? zeros(Float64, expected_length) : Float64[]
    root_two_sigma = sqrt(2.0) * sigma

    for indices in fitdata.groups
        for k in 1:q
            b = root_two_sigma * fitdata.nodes[k]
            conditional_loglikelihood = 0.0
            gradient && fill!(view(score_beta, k, :), 0.0)
            eta_score_sum = 0.0
            theta_score_sum = 0.0
            for observation in indices
                y = fitdata.y[observation]
                eta = eta_fixed[observation] + b
                difference = eta - logtheta
                mean_fraction = _logistic(difference)
                logdenominator = logtheta + _softplus(difference)
                conditional_loglikelihood += gamma_terms[observation] +
                    theta_value * (logtheta - logdenominator) +
                    y * (eta - logdenominator)
                if gradient
                    eta_score = y - (theta_value + y) * mean_fraction
                    for column in 1:p
                        score_beta[k, column] +=
                            eta_score * fitdata.X[observation, column]
                    end
                    eta_score_sum += eta_score
                    theta_score_sum += theta_value * (
                        psi_differences[observation] + logtheta - logdenominator + 1 -
                        (1 + y / theta_value) * (1 - mean_fraction)
                    )
                end
            end
            log_terms[k] = fitdata.logweights[k] + conditional_loglikelihood
            if gradient
                score_logsigma[k] = eta_score_sum * b
                score_logtheta[k] = theta_score_sum
            end
        end

        subject_logsum = _stable_logsumexp(log_terms)
        isfinite(subject_logsum) || return -Inf, fill(NaN, expected_length)
        total_loglikelihood += subject_logsum - 0.5log(pi)
        if gradient
            for k in 1:q
                posterior_weight = exp(log_terms[k] - subject_logsum)
                for column in 1:p
                    total_gradient[column] += posterior_weight * score_beta[k, column]
                end
                total_gradient[p + 1] += posterior_weight * score_logsigma[k]
                fixed_logtheta === nothing &&
                    (total_gradient[p + 2] += posterior_weight * score_logtheta[k])
            end
        end
    end
    return total_loglikelihood, total_gradient
end

function _adaptive_mode(
    fitdata::_NB2FitData,
    indices::Vector{Int},
    eta_fixed::Vector{Float64},
    sigma::Float64,
    logtheta::Float64,
    theta_value::Float64,
)
    inverse_variance = inv(sigma^2)
    score_curvature = function (b::Float64)
        score = -b * inverse_variance
        curvature = inverse_variance
        for observation in indices
            y = fitdata.y[observation]
            fraction = _logistic(eta_fixed[observation] + b - logtheta)
            score += y - (theta_value + y) * fraction
            curvature += (theta_value + y) * fraction * (1 - fraction)
        end
        isfinite(score) && isfinite(curvature) && curvature > 0 || throw(ArgumentError(
            "could not compute a finite positive conditional curvature for a subject",
        ))
        return score, curvature
    end

    lower = -max(1.0, sigma)
    upper = max(1.0, sigma)
    lower_score, _ = score_curvature(lower)
    upper_score, _ = score_curvature(upper)
    for expansion in 1:60
        lower_score >= 0 && upper_score <= 0 && break
        if lower_score < 0
            lower *= 2
            lower_score, _ = score_curvature(lower)
        end
        if upper_score > 0
            upper *= 2
            upper_score, _ = score_curvature(upper)
        end
    end
    lower_score >= 0 && upper_score <= 0 || throw(ArgumentError(
        "could not bracket a subject's conditional random-intercept mode",
    ))

    mode = clamp(0.0, lower, upper)
    for iteration in 1:80
        score, curvature = score_curvature(mode)
        abs(score) <= 1.0e-10 * (1 + length(indices)) && return mode, curvature
        if score > 0
            lower = mode
        else
            upper = mode
        end
        candidate = mode + score / curvature
        if !(isfinite(candidate) && lower < candidate < upper)
            candidate = (lower + upper) / 2
        end
        if abs(candidate - mode) <= 1.0e-12 * (1 + abs(mode))
            final_score, final_curvature = score_curvature(candidate)
            abs(final_score) <= 1.0e-8 * (1 + length(indices)) &&
                return candidate, final_curvature
        end
        mode = candidate
    end
    throw(ArgumentError(
        "conditional random-intercept mode did not converge within 80 safeguarded Newton steps",
    ))
end

function _nb2_likelihood_adaptive(
    fitdata::_NB2FitData,
    parameters::AbstractVector{<:Real};
    fixed_logtheta::Union{Nothing, Float64} = nothing,
    gradient::Bool = true,
)
    p = size(fitdata.X, 2)
    expected_length = p + (fixed_logtheta === nothing ? 2 : 1)
    length(parameters) == expected_length || throw(DimensionMismatch(
        "parameter vector has length $(length(parameters)); expected $expected_length",
    ))
    beta = view(parameters, 1:p)
    logsigma = Float64(parameters[p + 1])
    logtheta = fixed_logtheta === nothing ? Float64(parameters[p + 2]) : fixed_logtheta
    sigma = exp(logsigma)
    theta_value = exp(logtheta)
    if !(isfinite(sigma) && sigma > 0 && isfinite(theta_value) && theta_value > 0)
        return -Inf, fill(NaN, expected_length)
    end
    eta_fixed = Vector{Float64}(fitdata.X * beta)
    all(isfinite, eta_fixed) || return -Inf, fill(NaN, expected_length)
    psi_theta = digamma(theta_value)
    gamma_terms = similar(fitdata.y)
    psi_differences = gradient ? similar(fitdata.y) : Float64[]
    for observation in eachindex(fitdata.y)
        y = fitdata.y[observation]
        gamma_terms[observation] =
            loggamma(y + theta_value) - loggamma(theta_value) -
            fitdata.logfactorials[observation]
        gradient && (psi_differences[observation] = digamma(y + theta_value) - psi_theta)
    end

    q = length(fitdata.nodes)
    log_terms = Vector{Float64}(undef, q)
    score_beta = gradient ? Matrix{Float64}(undef, q, p) : Matrix{Float64}(undef, 0, 0)
    score_logsigma = gradient ? Vector{Float64}(undef, q) : Float64[]
    score_logtheta = gradient ? Vector{Float64}(undef, q) : Float64[]
    total_loglikelihood = 0.0
    total_gradient = gradient ? zeros(Float64, expected_length) : Float64[]
    inverse_variance = inv(sigma^2)

    for indices in fitdata.groups
        mode, curvature = _adaptive_mode(
            fitdata, indices, eta_fixed, sigma, logtheta, theta_value,
        )
        local_scale = sqrt(2 / curvature)
        for k in 1:q
            b = mode + local_scale * fitdata.nodes[k]
            conditional_loglikelihood = 0.0
            gradient && fill!(view(score_beta, k, :), 0.0)
            theta_score_sum = 0.0
            for observation in indices
                y = fitdata.y[observation]
                eta = eta_fixed[observation] + b
                difference = eta - logtheta
                mean_fraction = _logistic(difference)
                logdenominator = logtheta + _softplus(difference)
                conditional_loglikelihood += gamma_terms[observation] +
                    theta_value * (logtheta - logdenominator) +
                    y * (eta - logdenominator)
                if gradient
                    eta_score = y - (theta_value + y) * mean_fraction
                    for column in 1:p
                        score_beta[k, column] +=
                            eta_score * fitdata.X[observation, column]
                    end
                    theta_score_sum += theta_value * (
                        psi_differences[observation] + logtheta - logdenominator + 1 -
                        (1 + y / theta_value) * (1 - mean_fraction)
                    )
                end
            end
            log_integrand = conditional_loglikelihood -
                0.5b^2 * inverse_variance - logsigma - 0.5log(2pi)
            log_terms[k] = fitdata.logweights[k] + log_integrand + fitdata.nodes[k]^2
            if gradient
                # Exact marginal score identity. This includes the sigma derivative
                # of the Gaussian random-effect density without differentiating the
                # adaptive node transformation.
                score_logsigma[k] = -1 + b^2 * inverse_variance
                score_logtheta[k] = theta_score_sum
            end
        end
        subject_logsum = _stable_logsumexp(log_terms)
        isfinite(subject_logsum) || return -Inf, fill(NaN, expected_length)
        total_loglikelihood += subject_logsum + 0.5log(2 / curvature)
        if gradient
            for k in 1:q
                posterior_weight = exp(log_terms[k] - subject_logsum)
                for column in 1:p
                    total_gradient[column] += posterior_weight * score_beta[k, column]
                end
                total_gradient[p + 1] += posterior_weight * score_logsigma[k]
                fixed_logtheta === nothing &&
                    (total_gradient[p + 2] += posterior_weight * score_logtheta[k])
            end
        end
    end
    return total_loglikelihood, total_gradient
end

function _nb2_likelihood(
    fitdata::_NB2FitData,
    parameters::AbstractVector{<:Real};
    fixed_logtheta::Union{Nothing, Float64} = nothing,
    gradient::Bool = true,
)
    if fitdata.quadrature_method == :adaptive_gauss_hermite
        return _nb2_likelihood_adaptive(
            fitdata, parameters; fixed_logtheta, gradient,
        )
    end
    return _nb2_likelihood_fixed(fitdata, parameters; fixed_logtheta, gradient)
end

function _conditional_beta_information(
    fitdata::_NB2FitData,
    beta::Vector{Float64},
    logsigma::Float64,
    logtheta::Float64,
)
    p = length(beta)
    q = length(fitdata.nodes)
    sigma = exp(logsigma)
    theta_value = exp(logtheta)
    eta_fixed = fitdata.X * beta
    log_terms = Vector{Float64}(undef, q)
    scores = zeros(Float64, q, p)
    hessians = [zeros(Float64, p, p) for _ in 1:q]
    information = zeros(Float64, p, p)
    root_two_sigma = sqrt(2.0) * sigma
    inverse_variance = inv(sigma^2)

    for indices in fitdata.groups
        mode, curvature = if fitdata.quadrature_method == :adaptive_gauss_hermite
            _adaptive_mode(fitdata, indices, eta_fixed, sigma, logtheta, theta_value)
        else
            (0.0, NaN)
        end
        local_scale = fitdata.quadrature_method == :adaptive_gauss_hermite ?
            sqrt(2 / curvature) : root_two_sigma
        for k in 1:q
            fill!(view(scores, k, :), 0.0)
            fill!(hessians[k], 0.0)
            b = mode + local_scale * fitdata.nodes[k]
            conditional_loglikelihood = 0.0
            for observation in indices
                y = fitdata.y[observation]
                eta = eta_fixed[observation] + b
                difference = eta - logtheta
                fraction = _logistic(difference)
                logdenominator = logtheta + _softplus(difference)
                conditional_loglikelihood +=
                    loggamma(y + theta_value) - loggamma(theta_value) -
                    fitdata.logfactorials[observation] +
                    theta_value * (logtheta - logdenominator) +
                    y * (eta - logdenominator)
                eta_score = y - (theta_value + y) * fraction
                eta_second = -(theta_value + y) * fraction * (1 - fraction)
                for a in 1:p
                    xa = fitdata.X[observation, a]
                    scores[k, a] += eta_score * xa
                    for c in 1:p
                        hessians[k][a, c] +=
                            eta_second * xa * fitdata.X[observation, c]
                    end
                end
            end
            log_terms[k] = if fitdata.quadrature_method == :adaptive_gauss_hermite
                log_integrand = conditional_loglikelihood -
                    0.5b^2 * inverse_variance - logsigma - 0.5log(2pi)
                fitdata.logweights[k] + log_integrand + fitdata.nodes[k]^2
            else
                fitdata.logweights[k] + conditional_loglikelihood
            end
        end
        subject_logsum = _stable_logsumexp(log_terms)
        mean_score = zeros(Float64, p)
        expected_hessian_and_outer = zeros(Float64, p, p)
        for k in 1:q
            weight = exp(log_terms[k] - subject_logsum)
            score = view(scores, k, :)
            mean_score .+= weight .* score
            expected_hessian_and_outer .+=
                weight .* (hessians[k] .+ score * transpose(score))
        end
        subject_hessian = expected_hessian_and_outer .-
            mean_score * transpose(mean_score)
        information .-= subject_hessian
    end
    information = Matrix(Symmetric((information .+ transpose(information)) ./ 2))
    eigenvalues = eigvals(Symmetric(information))
    minimum(eigenvalues) > 0 || throw(ArgumentError(
        "fixed-effect observed information is not positive definite; minimum " *
        "eigenvalue is $(minimum(eigenvalues))",
    ))
    covariance = inv(Symmetric(information))
    all(isfinite, covariance) || throw(ArgumentError(
        "fixed-effect covariance contains non-finite values",
    ))
    return Matrix{Float64}((covariance .+ transpose(covariance)) ./ 2)
end

function _optimize_nb2(
    fitdata::_NB2FitData,
    initial::Vector{Float64};
    fixed_logtheta::Union{Nothing, Float64} = nothing,
    theta_bounds::Tuple{Float64, Float64} = (1.0e-3, 1.0e3),
    sigma_bounds::Tuple{Float64, Float64} = (1.0e-6, 1.0e2),
    maxeval::Int = 2_000,
)
    dimension = length(initial)
    optimizer = NLopt.Opt(:LD_LBFGS, dimension)
    lower = fill(-Inf, dimension)
    upper = fill(Inf, dimension)
    p = size(fitdata.X, 2)
    lower[p + 1] = log(sigma_bounds[1])
    upper[p + 1] = log(sigma_bounds[2])
    if fixed_logtheta === nothing
        lower[p + 2] = log(theta_bounds[1])
        upper[p + 2] = log(theta_bounds[2])
    end
    NLopt.lower_bounds!(optimizer, lower)
    NLopt.upper_bounds!(optimizer, upper)
    NLopt.ftol_rel!(optimizer, 1.0e-10)
    NLopt.xtol_rel!(optimizer, 1.0e-8)
    NLopt.maxeval!(optimizer, maxeval)
    evaluations = Ref(0)
    objective_function = function (parameters, gradient_storage)
        evaluations[] += 1
        loglikelihood_value, score = _nb2_likelihood(
            fitdata, parameters; fixed_logtheta, gradient = !isempty(gradient_storage),
        )
        if !isempty(gradient_storage)
            gradient_storage .= .-score
        end
        return -loglikelihood_value
    end
    NLopt.min_objective!(optimizer, objective_function)
    minimum_value, minimizer, return_code = NLopt.optimize(optimizer, initial)
    final_loglikelihood, final_score = _nb2_likelihood(
        fitdata, minimizer; fixed_logtheta, gradient = true,
    )
    success = return_code in (:SUCCESS, :STOPVAL_REACHED, :FTOL_REACHED, :XTOL_REACHED)
    return (
        parameters = Vector{Float64}(minimizer),
        objective = Float64(minimum_value),
        loglikelihood = Float64(final_loglikelihood),
        return_code,
        converged = success,
        evaluations = evaluations[],
        gradient_norm = maximum(abs, final_score),
    )
end

function _prepare_nb2_data(
    formula_term,
    data::DataFrame,
    id::Symbol,
    quadrature_points::Int;
    treatment::Union{Nothing, Symbol} = nothing,
    quadrature_method::Symbol = :adaptive_gauss_hermite,
)
    quadrature_points >= 5 || throw(ArgumentError(
        "quadrature_points must be at least 5; got $quadrature_points",
    ))
    quadrature_method in (:adaptive_gauss_hermite, :gauss_hermite) ||
        throw(ArgumentError(
            "quadrature_method must be :adaptive_gauss_hermite or :gauss_hermite",
        ))
    id in propertynames(data) || throw(ArgumentError("grouping column :$id is missing"))
    nrow(data) > 0 || throw(ArgumentError("data must contain at least one row"))
    any(ismissing, data[!, id]) && throw(ArgumentError("grouping column :$id contains missing values"))
    occursin("offset", lowercase(string(formula_term))) && throw(ArgumentError(
        "offsets are not supported by the dedicated NB2 random-intercept fitter",
    ))

    template = try
        LinearMixedModel(formula_term, data)
    catch error
        throw(ArgumentError("could not construct the mixed-model formula/design: $error"))
    end
    grouping = collect(fnames(template))
    grouping == [id] || throw(ArgumentError(
        "exactly one random-intercept grouping factor :$id is supported; detected $grouping",
    ))
    applied_formula = formula(template)
    rhs_terms = applied_formula.rhs isa Tuple ? applied_formula.rhs : (applied_formula.rhs,)
    random_terms = [term for term in rhs_terms if term isa MixedModels.RandomEffectsTerm]
    length(random_terms) == 1 || throw(ArgumentError(
        "exactly one random-effects term is supported; detected $(length(random_terms))",
    ))
    random_names = MixedModels.StatsModels.coefnames(only(random_terms).lhs)
    random_names = random_names isa AbstractString ? [String(random_names)] : String.(random_names)
    random_names == ["(Intercept)"] || throw(ArgumentError(
        "random slopes are unsupported; detected random-effect columns $random_names",
    ))
    fixed_terms = [term for term in rhs_terms if !(term isa MixedModels.RandomEffectsTerm)]
    length(fixed_terms) == 1 || throw(ArgumentError(
        "could not identify one fixed-effect matrix term in the formula",
    ))
    fixed_term = only(fixed_terms)
    X = Matrix{Float64}(MixedModels.StatsModels.modelcols(fixed_term, data))
    all(isfinite, X) || throw(ArgumentError("fixed-effect design contains non-finite values"))
    matrix_rank = rank(X)
    matrix_rank == size(X, 2) || throw(ArgumentError(
        "fixed-effect design is rank deficient (rank $matrix_rank for $(size(X, 2)) columns)",
    ))

    outcome = Symbol(responsename(template))
    outcome in propertynames(data) || throw(ArgumentError("outcome column :$outcome is missing"))
    any(ismissing, data[!, outcome]) && throw(ArgumentError(
        "outcome column :$outcome contains missing values",
    ))
    y = Float64.(data[!, outcome])
    all(isfinite, y) || throw(ArgumentError("outcome column :$outcome contains non-finite values"))
    minimum(y) >= 0 || throw(ArgumentError("NB2 outcomes must be nonnegative counts"))
    integer_tolerance = 64eps(Float64) .* max.(1.0, abs.(y))
    all(abs.(y .- round.(y)) .<= integer_tolerance) || throw(ArgumentError(
        "NB2 outcomes must be integer-valued counts",
    ))

    treatment === nothing || _validate_static_treatment(data, treatment, id)
    identifiers = unique(data[!, id])
    length(identifiers) >= 2 || throw(ArgumentError(
        "at least two nonempty :$id groups are required",
    ))
    groups = [findall(value -> isequal(value, identifier), data[!, id]) for identifier in identifiers]
    any(isempty, groups) && throw(ArgumentError("empty grouping levels are unsupported"))
    nodes, weights = gausshermite(quadrature_points)
    all(weights .> 0) || throw(ArgumentError("Gauss-Hermite weights must be positive"))
    fitdata = _NB2FitData(
        y,
        X,
        groups,
        Float64.(nodes),
        log.(Float64.(weights)),
        loggamma.(y .+ 1),
        quadrature_method,
    )
    return fitdata, applied_formula, fixed_term, outcome, String.(coefnames(template))
end

function _initial_nb2_parameters(
    fitdata::_NB2FitData;
    theta_initial::Union{Nothing, Real} = nothing,
)
    beta = fitdata.X \ log.(fitdata.y .+ 0.5)
    all(isfinite, beta) || fill!(beta, 0.0)
    response_mean = sum(fitdata.y) / length(fitdata.y)
    response_variance = sum((fitdata.y .- response_mean) .^ 2) /
        max(1, length(fitdata.y) - 1)
    moment_theta = response_variance > response_mean ?
        response_mean^2 / (response_variance - response_mean) : 10.0
    initial_theta = theta_initial === nothing ? clamp(moment_theta, 0.1, 100.0) :
        Float64(theta_initial)
    isfinite(initial_theta) && initial_theta > 0 || throw(ArgumentError(
        "theta_initial must be positive and finite; got $theta_initial",
    ))
    return vcat(Vector{Float64}(beta), log(0.5), log(initial_theta))
end


function CausalDynamics.fit_profiled_nb2(
    formula_term,
    data::DataFrame;
    id::Symbol,
    family::Symbol = :nb2,
    link = LogLink(),
    treatment::Union{Nothing, Symbol} = nothing,
    weights = nothing,
    offset = nothing,
    theta_initial::Union{Nothing, Real} = nothing,
    theta_bounds = (1.0e-3, 1.0e3),
    quadrature_points::Int = 25,
    quadrature_method::Symbol = :adaptive_gauss_hermite,
    optimizer = nothing,
    progress::Bool = true,
    maxeval::Int = 2_000,
    multiple_starts::Int = 3,
    profile::Bool = true,
    uncertainty::Symbol = :delta_fixed,
    initial_parameters::Union{Nothing, AbstractVector{<:Real}} = nothing,
)
    family == :nb2 || throw(ArgumentError(
        "unsupported family $(repr(family)); only NB2 is supported",
    ))
    link isa LogLink || throw(ArgumentError(
        "unsupported NB2 link $(typeof(link)); only LogLink is supported",
    ))
    weights === nothing || throw(ArgumentError(
        "prior or frequency weights are not supported by the dedicated NB2 fitter",
    ))
    offset === nothing || throw(ArgumentError(
        "offsets are not supported by the dedicated NB2 fitter",
    ))
    optimizer === nothing || throw(ArgumentError(
        "custom optimizers are not yet supported; the dedicated fitter uses NLopt L-BFGS",
    ))
    uncertainty in (:delta_fixed, :parametric_bootstrap) || throw(ArgumentError(
        "uncertainty must be :delta_fixed or :parametric_bootstrap",
    ))
    multiple_starts >= 1 || throw(ArgumentError("multiple_starts must be positive"))
    bounds = Tuple(Float64.(theta_bounds))
    length(bounds) == 2 && 0 < bounds[1] < bounds[2] || throw(ArgumentError(
        "theta_bounds must be two positive increasing values",
    ))
    fitdata, applied_formula, fixed_term, outcome, coefficient_names =
        _prepare_nb2_data(
            formula_term,
            data,
            id,
            quadrature_points;
            treatment,
            quadrature_method,
        )
    initial = if initial_parameters === nothing
        _initial_nb2_parameters(fitdata; theta_initial)
    else
        length(initial_parameters) == size(fitdata.X, 2) + 2 || throw(ArgumentError(
            "initial_parameters must contain beta, log(sigma_b), and log(theta)",
        ))
        Float64.(initial_parameters)
    end
    all(isfinite, initial) || throw(ArgumentError("initial_parameters must be finite"))
    initial[end] = clamp(initial[end], log(bounds[1]) + 0.1, log(bounds[2]) - 0.1)
    starts = Vector{Vector{Float64}}([copy(initial)])
    start_multipliers = ((0.5, 0.5), (2.0, 2.0), (0.5, 2.0), (2.0, 0.5))
    for (sigma_multiplier, theta_multiplier) in start_multipliers
        length(starts) >= multiple_starts && break
        candidate = copy(initial)
        candidate[end - 1] += log(sigma_multiplier)
        candidate[end] = clamp(
            candidate[end] + log(theta_multiplier),
            log(bounds[1]) + 0.1,
            log(bounds[2]) - 0.1,
        )
        push!(starts, candidate)
    end

    runs = map(starts) do start
        _optimize_nb2(fitdata, start; theta_bounds = bounds, maxeval)
    end
    successful = findall(run -> run.converged && isfinite(run.objective), runs)
    isempty(successful) && throw(ErrorException(
        "NB2 optimization failed from all $multiple_starts starting values; return codes " *
        "were $([run.return_code for run in runs])",
    ))
    best_index = successful[argmin([runs[index].objective for index in successful])]
    best = runs[best_index]
    p = size(fitdata.X, 2)
    beta = best.parameters[1:p]
    logsigma = best.parameters[p + 1]
    logtheta = best.parameters[p + 2]

    profile_offsets = profile ? [-0.5, -0.25, 0.0, 0.25, 0.5] : [0.0]
    profile_rows = NamedTuple[]
    fixed_start = vcat(beta, logsigma)
    for offset in profile_offsets
        candidate_logtheta = clamp(logtheta + offset, log(bounds[1]), log(bounds[2]))
        profile_fit = if offset == 0
            (
                objective = best.objective,
                loglikelihood = best.loglikelihood,
                converged = best.converged,
                parameters = fixed_start,
                gradient_norm = best.gradient_norm,
                return_code = best.return_code,
            )
        else
            _optimize_nb2(
                fitdata,
                fixed_start;
                fixed_logtheta = candidate_logtheta,
                theta_bounds = bounds,
                maxeval,
            )
        end
        push!(profile_rows, (;
            log_theta = candidate_logtheta,
            theta = exp(candidate_logtheta),
            objective = profile_fit.objective,
            loglikelihood = profile_fit.loglikelihood,
            converged = profile_fit.converged,
            random_intercept_variance = exp(2profile_fit.parameters[p + 1]),
            gradient_norm = profile_fit.gradient_norm,
        ))
    end
    theta_profile = DataFrame(profile_rows)
    profile_curvature = if profile
        center = findfirst(==(0.0), profile_offsets)
        h = 0.25
        (theta_profile.objective[center - 1] - 2theta_profile.objective[center] +
            theta_profile.objective[center + 1]) / h^2
    else
        NaN
    end
    objective_spread = maximum(run.objective for run in runs[successful]) -
        minimum(run.objective for run in runs[successful])
    theta_spread = maximum(run.parameters[end] for run in runs[successful]) -
        minimum(run.parameters[end] for run in runs[successful])
    starts_agree = length(successful) == length(runs) &&
        objective_spread <= 1.0e-7 * (1 + abs(best.objective)) &&
        theta_spread <= 1.0e-3
    interior = logtheta > log(bounds[1]) + 1.0e-4 &&
        logtheta < log(bounds[2]) - 1.0e-4
    profile_identified = !profile || (
        all(theta_profile.converged) && isfinite(profile_curvature) && profile_curvature > 0 &&
        all(theta_profile.objective[[1, 2, 4, 5]] .> theta_profile.objective[3])
    )
    beta_vcov = _conditional_beta_information(fitdata, beta, logsigma, logtheta)
    diagnostics = (;
        backend = :dedicated_subject_integrated_likelihood,
        optimizer = :NLopt_LD_LBFGS,
        return_code = best.return_code,
        evaluations = best.evaluations,
        gradient_norm = best.gradient_norm,
        multiple_starts,
        successful_starts = length(successful),
        objective_spread,
        logtheta_spread = theta_spread,
        starts_agree,
        theta_bounds = bounds,
        theta_interior = interior,
        profile_curvature,
        profile_identified,
        random_effect_boundary = exp(logsigma) <= 1.01e-6,
        quadrature_method,
        quadrature_points,
        response = outcome,
    )
    gradient_tolerance = max(1.0e-3, 1.0e-5 * length(fitdata.y))
    diagnostics = merge(diagnostics, (; gradient_tolerance))
    passed = best.converged && interior && profile_identified && starts_agree &&
        isfinite(best.gradient_norm) && best.gradient_norm <= gradient_tolerance
    progress && @info(
        "fitted dedicated NB2/log random-intercept model",
        theta = exp(logtheta),
        random_intercept_variance = exp(2logsigma),
        loglikelihood = best.loglikelihood,
        gradient_norm = best.gradient_norm,
        converged = passed,
    )
    return NB2RandomInterceptModel(
        applied_formula,
        fixed_term,
        id,
        beta,
        coefficient_names,
        exp(logtheta),
        exp(2logsigma),
        best.loglikelihood,
        passed,
        diagnostics,
        theta_profile,
        beta_vcov,
        uncertainty,
        quadrature_method,
        quadrature_points,
        length(fitdata.y),
        copy(data),
    )
end

function _empirical_covariance(samples::Matrix{Float64})
    n = size(samples, 1)
    n >= 2 || throw(ArgumentError("at least two successful bootstrap samples are required"))
    centered = samples .- sum(samples; dims = 1) ./ n
    covariance = transpose(centered) * centered / (n - 1)
    return Matrix{Float64}((covariance .+ transpose(covariance)) ./ 2)
end

function _replace_uncertainty(
    result::MixedGComputationResult,
    covariance::Matrix{Float64},
    diagnostics,
)
    diagonal = diag(covariance)
    all(diagonal .>= -1024eps(Float64) * max(1.0, maximum(abs, covariance))) ||
        throw(ArgumentError("bootstrap covariance has a negative diagonal"))
    standard_errors = sqrt.(max.(diagonal, 0.0))
    return MixedGComputationResult(;
        treatment = result.treatment,
        outcome = result.outcome,
        time = result.time,
        id = result.id,
        times = result.times,
        values = result.values,
        mean_reference = result.mean_reference,
        mean_comparison = result.mean_comparison,
        adjustment = result.adjustment,
        vcov = covariance,
        se = standard_errors,
        random_effects = result.random_effects,
        uncertainty = :parametric_bootstrap,
        uncertainty_diagnostics = diagnostics,
    )
end

function _replace_uncertainty(
    result::StratifiedMixedGComputationResult,
    covariances::Vector{Matrix{Float64}},
    diagnostics,
)
    trajectories = [
        _replace_uncertainty(result.results[index], covariances[index], diagnostics)
        for index in eachindex(result.results)
    ]
    return StratifiedMixedGComputationResult(result.strata, result.levels, trajectories)
end

function _simulate_nb2_response(
    rng::AbstractRNG,
    model::NB2RandomInterceptModel,
    data::DataFrame,
)
    design = _fixed_effect_design(model, data)
    eta = design * model.coefficients
    random_intercepts = Dict{Any, Float64}()
    sigma = sqrt(model.random_intercept_variance)
    response = Vector{Int}(undef, nrow(data))
    for row_index in 1:nrow(data)
        identifier = data[row_index, model.id]
        b = get!(random_intercepts, identifier) do
            sigma * randn(rng)
        end
        mean_value = exp(eta[row_index] + b)
        isfinite(mean_value) || throw(ArgumentError(
            "bootstrap response mean overflowed for row $row_index",
        ))
        probability = model.theta / (model.theta + mean_value)
        response[row_index] = rand(
            rng,
            MixedModels.Distributions.NegativeBinomial(model.theta, probability),
        )
    end
    return response
end


function _bootstrap_g_computation(
    model::NB2RandomInterceptModel,
    data::DataFrame,
    point_result;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values,
    adjustment,
    strata,
    random_effects,
    n_boot::Int,
    seed::Integer,
    min_success_rate::Float64,
)
    n_boot >= 2 || throw(ArgumentError("n_boot must be at least 2"))
    0 < min_success_rate <= 1 || throw(ArgumentError(
        "min_success_rate must lie in (0, 1]",
    ))
    rng = MersenneTwister(seed)
    effect_samples = point_result isa MixedGComputationResult ?
        [Vector{Float64}[]] : [Vector{Float64}[] for _ in point_result.results]
    failure_messages = String[]
    start = vcat(
        model.coefficients,
        0.5log(model.random_intercept_variance),
        log(model.theta),
    )
    for replicate in 1:n_boot
        try
            bootstrap_data = copy(data)
            bootstrap_data[!, outcome] = _simulate_nb2_response(rng, model, data)
            bootstrap_model = CausalDynamics.fit_profiled_nb2(
                model.formula,
                bootstrap_data;
                id,
                treatment,
                theta_initial = model.theta,
                theta_bounds = model.optimizer_diagnostics.theta_bounds,
                quadrature_points = model.quadrature_points,
                quadrature_method = model.quadrature_method,
                progress = false,
                maxeval = 2_000,
                multiple_starts = 1,
                profile = false,
                initial_parameters = start,
            )
            bootstrap_model.converged || throw(ErrorException(
                "refit returned converged=false ($(bootstrap_model.optimizer_diagnostics))",
            ))
            bootstrap_result = _mixed_g_computation(
                bootstrap_model,
                bootstrap_data;
                treatment,
                outcome,
                time,
                id,
                values,
                adjustment,
                strata,
                random_effects,
                compute_uncertainty = false,
            )
            if bootstrap_result isa MixedGComputationResult
                push!(only(effect_samples), bootstrap_result.effect)
            else
                bootstrap_result.levels == point_result.levels || throw(ErrorException(
                    "bootstrap stratum ordering changed",
                ))
                for index in eachindex(effect_samples)
                    push!(effect_samples[index], bootstrap_result.results[index].effect)
                end
            end
        catch error
            push!(failure_messages, "replicate $replicate: $(sprint(showerror, error))")
        end
    end
    successful = length(first(effect_samples))
    failed = n_boot - successful
    successful / n_boot >= min_success_rate || throw(ErrorException(
        "only $successful of $n_boot parametric-bootstrap refits succeeded; required " *
        "at least $(ceil(Int, min_success_rate * n_boot)). First failures: " *
        join(first(failure_messages, min(3, length(failure_messages))), " | "),
    ))
    failed > 0 && @warn(
        "$failed of $n_boot parametric-bootstrap refits failed",
        failure_messages,
    )
    effect_draws = map(samples -> reduce(vcat, transpose.(samples)), effect_samples)
    covariances = map(_empirical_covariance, effect_draws)
    diagnostics = (;
        n_boot,
        n_successful = successful,
        n_failed = failed,
        seed = Int(seed),
        failure_messages,
        effect_draws,
        refitted_parameters = (:beta, :random_intercept_variance, :theta),
    )
    return point_result isa MixedGComputationResult ?
        _replace_uncertainty(point_result, only(covariances), diagnostics) :
        _replace_uncertainty(point_result, covariances, diagnostics)
end

function _nb2_g_computation(
    model::NB2RandomInterceptModel,
    data::DataFrame;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values = (0, 1),
    adjustment = Symbol[],
    strata = nothing,
    random_effects = :zero,
    uncertainty = model.uncertainty_method,
    n_boot::Int = 200,
    seed::Integer = 20260825,
    min_success_rate::Float64 = 0.8,
)
    uncertainty in (:delta_fixed, :parametric_bootstrap) || throw(ArgumentError(
        "uncertainty must be :delta_fixed or :parametric_bootstrap; got $(repr(uncertainty))",
    ))
    point_result = _mixed_g_computation(
        model,
        data;
        treatment,
        outcome,
        time,
        id,
        values,
        adjustment,
        strata,
        random_effects,
    )
    uncertainty == :delta_fixed && return point_result
    return _bootstrap_g_computation(
        model,
        data,
        point_result;
        treatment,
        outcome,
        time,
        id,
        values,
        adjustment,
        strata,
        random_effects,
        n_boot,
        seed,
        min_success_rate,
    )
end

function CausalDynamics.mixed_g_computation(
    model::NB2RandomInterceptModel,
    data::DataFrame;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values = (0, 1),
    strata = nothing,
    random_effects = :zero,
    uncertainty = model.uncertainty_method,
    n_boot::Int = 200,
    seed::Integer = 20260825,
    min_success_rate::Float64 = 0.8,
)
    return _nb2_g_computation(
        model,
        data;
        treatment,
        outcome,
        time,
        id,
        values,
        strata,
        random_effects,
        uncertainty,
        n_boot,
        seed,
        min_success_rate,
    )
end

function CausalDynamics.mixed_g_computation(
    graph::AbstractGraph,
    model::NB2RandomInterceptModel,
    data::DataFrame;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values = (0, 1),
    strata = nothing,
    random_effects = :zero,
    uncertainty = model.uncertainty_method,
    n_boot::Int = 200,
    seed::Integer = 20260825,
    min_success_rate::Float64 = 0.8,
    node_names = nothing,
)
    node_names === nothing && throw(ArgumentError(
        "node_names is required when graph nodes are addressed by data-column symbols",
    ))
    adjustment = _identified_adjustment(graph, treatment, outcome, node_names)
    return _nb2_g_computation(
        model,
        data;
        treatment,
        outcome,
        time,
        id,
        values,
        adjustment,
        strata,
        random_effects,
        uncertainty,
        n_boot,
        seed,
        min_success_rate,
    )
end

function CausalDynamics.mixed_g_computation(
    graph::CausalGraph,
    model::NB2RandomInterceptModel,
    data::DataFrame;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values = (0, 1),
    strata = nothing,
    random_effects = :zero,
    uncertainty = model.uncertainty_method,
    n_boot::Int = 200,
    seed::Integer = 20260825,
    min_success_rate::Float64 = 0.8,
    node_names = nothing,
)
    names = node_names === nothing ? get_node_names(graph) : node_names
    isempty(names) && throw(ArgumentError(
        "CausalGraph has no node names; set node :name properties or pass node_names",
    ))
    adjustment = _identified_adjustment(graph, treatment, outcome, names)
    return _nb2_g_computation(
        model,
        data;
        treatment,
        outcome,
        time,
        id,
        values,
        adjustment,
        strata,
        random_effects,
        uncertainty,
        n_boot,
        seed,
        min_success_rate,
    )
end

MixedModels.StatsAPI.coef(model::NB2RandomInterceptModel) = copy(model.coefficients)
MixedModels.fixef(model::NB2RandomInterceptModel) = copy(model.coefficients)
MixedModels.StatsAPI.vcov(model::NB2RandomInterceptModel) = copy(model.beta_vcov)
MixedModels.StatsModels.formula(model::NB2RandomInterceptModel) = model.formula
MixedModels.StatsAPI.loglikelihood(model::NB2RandomInterceptModel) = model.loglikelihood
MixedModels.StatsAPI.deviance(model::NB2RandomInterceptModel) = -2model.loglikelihood
MixedModels.StatsAPI.nobs(model::NB2RandomInterceptModel) = model.observations
MixedModels.StatsAPI.coefnames(model::NB2RandomInterceptModel) = copy(model.coefficient_names)
MixedModels.StatsAPI.responsename(model::NB2RandomInterceptModel) =
    Symbol(model.formula.lhs.sym)
MixedModels.fnames(model::NB2RandomInterceptModel) = (model.id,)
MixedModels.issingular(model::NB2RandomInterceptModel) =
    model.optimizer_diagnostics.random_effect_boundary

_random_intercept_variance(model::NB2RandomInterceptModel) =
    model.random_intercept_variance

function _prediction_components(
    model::NB2RandomInterceptModel,
    prediction_data::DataFrame,
    design::Matrix{Float64},
    random_effects::Symbol,
)
    eta = design * model.coefficients
    all(isfinite, eta) || throw(ArgumentError(
        "dedicated NB2 link-scale predictions contain non-finite values",
    ))
    predictions = exp.(eta)
    all(isfinite, predictions) || throw(ArgumentError(
        "dedicated NB2 response-scale predictions overflowed",
    ))
    if random_effects == :marginal
        predictions .*= exp(0.5model.random_intercept_variance)
    end
    return predictions, true
end

function _refit_with_quadrature(model::NB2RandomInterceptModel, points::Int)
    return CausalDynamics.fit_profiled_nb2(
        model.formula,
        model.fitted_data;
        id = model.id,
        theta_initial = model.theta,
        theta_bounds = model.optimizer_diagnostics.theta_bounds,
        quadrature_points = points,
        quadrature_method = model.quadrature_method,
        progress = false,
        multiple_starts = 2,
        profile = false,
    )
end

function CausalDynamics.quadrature_diagnostics(
    model::NB2RandomInterceptModel;
    points = (15, 25, 41),
)
    rows = NamedTuple[]
    for count in points
        fitted = count == model.quadrature_points ? model : _refit_with_quadrature(model, count)
        push!(rows, (;
            quadrature_points = count,
            loglikelihood = fitted.loglikelihood,
            theta = fitted.theta,
            random_intercept_variance = fitted.random_intercept_variance,
            coefficient_maximum_difference = maximum(abs.(
                fitted.coefficients .- model.coefficients
            )),
            converged = fitted.converged,
        ))
    end
    return DataFrame(rows)
end

function CausalDynamics.validate_fixed_theta_nb2_likelihood(
    formula_term,
    data::DataFrame;
    id::Symbol,
    theta_grid = (0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 5.0),
    quadrature_points::Int = 41,
    tolerance::Float64 = 1.0e-4,
)
    fitdata, _, _, _, _ = _prepare_nb2_data(
        formula_term,
        data,
        id,
        quadrature_points;
        quadrature_method = :adaptive_gauss_hermite,
    )
    rows = NamedTuple[]
    for theta_value in theta_grid
        fixed_model = fit(
            MixedModel,
            formula_term,
            data,
            MixedModels.Distributions.NegativeBinomial(theta_value),
            LogLink();
            progress = false,
        )
        variance = _random_intercept_variance(fixed_model)
        parameters = vcat(Float64.(coef(fixed_model)), 0.5log(variance))
        independent, score = _nb2_likelihood(
            fitdata,
            parameters;
            fixed_logtheta = log(theta_value),
            gradient = true,
        )
        mixedmodels_loglikelihood = Float64(loglikelihood(fixed_model))
        difference = independent - mixedmodels_loglikelihood
        push!(rows, (;
            theta = Float64(theta_value),
            mixedmodels_loglikelihood,
            independent_loglikelihood = independent,
            difference,
            absolute_difference = abs(difference),
            independent_gradient_norm = maximum(abs, score),
            agrees = abs(difference) <= tolerance,
        ))
    end
    result = DataFrame(rows)
    return (validated = all(result.agrees), tolerance, comparisons = result)
end
