module NonlinearStateReference

using LinearAlgebra

export grid_reference, dense_affine_reference, moment_disagreement,
    mode_locations, interval_content

"""Evaluate a scalar Gaussian density without external distribution dependencies."""
gaussian_density(x, μ, variance) = exp(-0.5 * (x - μ)^2 / variance) / sqrt(2π * variance)

"""
    grid_reference(observations; transition, process_variance, observation_variance,
        initial_mean, initial_variance, bounds=(-7.0, 7.0), points=401, ...)

Condition the original scalar nonlinear model on a uniform trapezoidal grid.
Forward transition columns contain destination quadrature weights and are never
normalised separately. Reverse conditionals recover all smoothed covariance
blocks. Domain truncation diagnostics are numerical diagnostics, not rigorous
tail-error bounds; independent domain and spacing refinement remain necessary.
"""
function grid_reference(observations; transition, process_variance,
    observation_variance, initial_mean, initial_variance, observation = 1.0,
    observation_offset = 0.0, initial_time = 0, bounds = (-7.0, 7.0), points = 401)
    n = length(observations)
    n > 0 || throw(ArgumentError("reference requires observations"))
    points >= 3 || throw(ArgumentError("reference requires at least three grid points"))
    bounds[1] < bounds[2] || throw(ArgumentError("reference bounds must increase"))
    process_variance > 0 && observation_variance > 0 && initial_variance > 0 ||
        throw(ArgumentError("reference variances must be positive"))
    grid = collect(range(bounds[1], bounds[2]; length = points))
    spacing = grid[2] - grid[1]
    weights = fill(spacing, points)
    weights[[1, end]] ./= 2
    filtering_mass = zeros(points, n)
    reverse_conditionals = Matrix{Float64}[]
    predictive_lost_mass = zeros(n - 1)
    prior_mass = weights .* gaussian_density.(grid, initial_mean, initial_variance)
    prior_retained_mass = sum(prior_mass)
    prediction = prior_mass / prior_retained_mass
    for j in 1:n
        if j > 1
            t = initial_time + j - 2
            centres = transition.(grid, t)
            all(isfinite, centres) || throw(ArgumentError("nonfinite reference transition"))
            kernel = [weights[destination] * gaussian_density(grid[destination],
                centres[source], process_variance) for destination in 1:points, source in 1:points]
            previous = view(filtering_mass, :, j - 1)
            prediction = kernel * previous
            predictive_lost_mass[j - 1] = 1 - sum(prediction)
            reverse = Matrix(transpose(kernel)) .* previous
            for destination in 1:points
                if prediction[destination] > 0
                    reverse[:, destination] ./= prediction[destination]
                else
                    reverse[:, destination] .= 0
                end
            end
            push!(reverse_conditionals, reverse)
        end
        if !ismissing(observations[j])
            log_likelihood = @. -0.5 * (observations[j] - observation * grid - observation_offset)^2 / observation_variance
            prediction = prediction .* exp.(log_likelihood .- maximum(log_likelihood))
        end
        normaliser = sum(prediction)
        isfinite(normaliser) && normaliser > 0 || throw(ArgumentError("reference mass vanished"))
        filtering_mass[:, j] = prediction / normaliser
    end
    smoothing_mass = copy(filtering_mass)
    for j in (n - 1):-1:1
        smoothing_mass[:, j] = reverse_conditionals[j] * smoothing_mass[:, j + 1]
    end
    filtering_means = vec(grid' * filtering_mass)
    filtering_variances = vec((grid .^ 2)' * filtering_mass) - filtering_means .^ 2
    smoothing_means = vec(grid' * smoothing_mass)
    covariance = zeros(n, n)
    for s in 1:n
        joint_first_moment = smoothing_mass[:, s] .* grid
        for t in s:-1:1
            covariance[t, s] = dot(grid, joint_first_moment) - smoothing_means[t] * smoothing_means[s]
            covariance[s, t] = covariance[t, s]
            t > 1 && (joint_first_moment = reverse_conditionals[t - 1] * joint_first_moment)
        end
    end
    boundary_indices = unique(vcat(1:3, (points - 2):points))
    return (; grid, spacing, weights, filtering_mass, smoothing_mass,
        filtering_means, filtering_variances, smoothing_means,
        smoothing_variances = diag(covariance), trajectory_covariance = covariance,
        prior_lost_mass = 1 - prior_retained_mass, predictive_lost_mass,
        posterior_boundary_mass = vec(sum(smoothing_mass[boundary_indices, :]; dims = 1)))
end

"""Condition a scalar affine trajectory by independently assembling its precision."""
function dense_affine_reference(observations; slopes, offsets, process_variance,
    observation_variance, initial_mean, initial_variance, observation = 1.0,
    observation_offset = 0.0)
    n = length(observations)
    length(slopes) == length(offsets) == n - 1 || throw(DimensionMismatch("affine transition count"))
    filtering_means, filtering_variances = zeros(n), zeros(n)
    smoothing_means, covariance = zeros(n), zeros(n, n)
    for horizon in 1:n
        precision, information = zeros(horizon, horizon), zeros(horizon)
        precision[1, 1] = 1 / initial_variance
        information[1] = initial_mean / initial_variance
        for j in 2:horizon
            slope, offset = slopes[j - 1], offsets[j - 1]
            precision[j - 1, j - 1] += slope^2 / process_variance
            precision[j, j] += 1 / process_variance
            precision[j - 1, j] -= slope / process_variance
            precision[j, j - 1] -= slope / process_variance
            information[j - 1] -= slope * offset / process_variance
            information[j] += offset / process_variance
        end
        for j in 1:horizon
            if !ismissing(observations[j])
                precision[j, j] += observation^2 / observation_variance
                information[j] += observation * (observations[j] - observation_offset) / observation_variance
            end
        end
        covariance = inv(Symmetric(precision))
        smoothing_means = covariance * information
        filtering_means[horizon] = smoothing_means[end]
        filtering_variances[horizon] = covariance[end, end]
    end
    return (; filtering_means, filtering_variances, smoothing_means,
        smoothing_variances = diag(covariance), trajectory_covariance = Matrix(covariance))
end

"""Compare joint moments using reference standard deviations and covariance norm."""
function moment_disagreement(means, covariance, reference)
    return (standardised_mean = maximum(abs.(vec(means) - reference.smoothing_means) ./ sqrt.(reference.smoothing_variances)),
        relative_covariance = norm(covariance - reference.trajectory_covariance) / norm(reference.trajectory_covariance))
end

"""Find resolved local maxima of a grid posterior density at one occasion."""
function mode_locations(reference, occasion; relative_height = 0.05)
    density = reference.smoothing_mass[:, occasion] ./ reference.weights
    threshold = relative_height * maximum(density)
    return [reference.grid[j] for j in 2:(length(density) - 1)
        if density[j] > density[j - 1] && density[j] >= density[j + 1] && density[j] >= threshold]
end

"""Integrate posterior mass inside an interval, interpolating its edge cells."""
function interval_content(reference, occasion, lower, upper)
    lower <= upper || throw(ArgumentError("interval must increase"))
    density = reference.smoothing_mass[:, occasion] ./ reference.weights
    content = 0.0
    for j in 1:(length(reference.grid) - 1)
        left, right = reference.grid[j], reference.grid[j + 1]
        a, b = max(left, lower), min(right, upper)
        if a < b
            slope = (density[j + 1] - density[j]) / (right - left)
            content += density[j] * (b - a) + slope * ((b - left)^2 - (a - left)^2) / 2
        end
    end
    return content
end

end
