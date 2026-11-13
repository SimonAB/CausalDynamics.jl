# Run from the package checkout with its optional integration dependencies:
# julia --project=. --threads=auto test/stress/nonlinear_state_validation.jl
using Test, LinearAlgebra, Statistics, Printf
BLAS.set_num_threads(1)
include(joinpath(@__DIR__, "..", "nonlinear_state_reference.jl"))
using .NonlinearStateReference

"""Check the numerical reference against independent exact Gaussian conditioning."""
function validate_affine_reference()
    model = (transition = (x, t) -> (0.75 + 0.01t) * x + 0.08 - 0.02t,
        process_variance = 0.17, observation_variance = 0.23,
        initial_mean = 0.15, initial_variance = 0.8,
        observation = 1.2, observation_offset = -0.1, initial_time = 3)
    observations = [0.2, missing, -0.1, 0.4, 0.3, -0.2]
    exact = dense_affine_reference(observations;
        slopes = [0.75 + 0.01t for t in 3:7],
        offsets = [0.08 - 0.02t for t in 3:7],
        process_variance = model.process_variance,
        observation_variance = model.observation_variance,
        initial_mean = model.initial_mean, initial_variance = model.initial_variance,
        observation = model.observation, observation_offset = model.observation_offset)
    reference = grid_reference(observations; model..., bounds = (-7.0, 7.0), points = 401)
    @testset "Independent grid affine limit" begin
        @test maximum(abs.(reference.filtering_means - exact.filtering_means)) < 1e-6
        @test maximum(abs.(reference.filtering_variances - exact.filtering_variances)) < 1e-6
        @test maximum(abs.(reference.smoothing_means - exact.smoothing_means)) < 1e-6
        @test maximum(abs.(reference.trajectory_covariance - exact.trajectory_covariance)) < 1e-6
        @test reference.prior_lost_mass < 1e-10
        @test maximum(reference.predictive_lost_mass) < 1e-10
        bounded = grid_reference(fill(missing, 2);
            transition = (x, t) -> x + 0.4, process_variance = 0.3,
            observation_variance = 1.0, initial_mean = 0.0, initial_variance = 0.2,
            bounds = (-0.5, 0.5), points = 201)
        # Column-normalising the forward transition would erase this deficit.
        @test bounded.predictive_lost_mass[1] > 0.3
        @test isapprox(sum(reference.smoothing_mass[:, end]), 1; atol = 1e-12)
        radius = 1.959963984540054sqrt(reference.smoothing_variances[end])
        centre = reference.smoothing_means[end]
        @test abs(interval_content(reference, 6, centre - radius, centre + radius) - 0.95) < 1e-3
    end
    return (; reference, exact, model, observations)
end

"""Remove only the derivative callback, which the original-model grid never uses."""
reference_parameters(model) = (; (key => value for (key, value) in pairs(model)
    if key != :transition_derivative)...)

"""Print separate spacing and domain refinements and numerical boundary diagnostics."""
function reference_refinement(io, name, observations, model;
    bounds = (-6.0, 6.0), coarse_points = 201, fine_points = 401,
    wide_bounds = (-9.0, 9.0), wide_points = 601)
    parameters = reference_parameters(model)
    coarse = grid_reference(observations; parameters..., bounds, points = coarse_points)
    fine = grid_reference(observations; parameters..., bounds, points = fine_points)
    wide = grid_reference(observations; parameters..., bounds = wide_bounds, points = wide_points)
    @assert isapprox(fine.spacing, wide.spacing; rtol = 1e-12)
    spacing_error = moment_disagreement(coarse.smoothing_means, coarse.trajectory_covariance, fine)
    domain_error = moment_disagreement(fine.smoothing_means, fine.trajectory_covariance, wide)
    @printf(io, "%s grids: coarse=%d [%.1f,%.1f] dx=%.6g; fine=%d dx=%.6g; wider=%d [%.1f,%.1f] dx=%.6g\n",
        name, coarse_points, bounds..., coarse.spacing, fine_points, fine.spacing,
        wide_points, wide_bounds..., wide.spacing)
    for (label, error) in (("spacing", spacing_error), ("domain", domain_error))
        @printf(io, "%s %s refinement: max mean change/reference SD=%.6g; relative joint covariance Frobenius change=%.6g\n",
            name, label, error.standardised_mean, error.relative_covariance)
    end
    @printf(io, "%s wider-domain truncation diagnostics: prior lost mass=%.6g; maximum predictive transition lost mass=%.6g; maximum posterior outer-three-grid-point mass=%.6g\n",
        name, wide.prior_lost_mass, maximum(wide.predictive_lost_mass; init = 0.0),
        maximum(wide.posterior_boundary_mass))
    return (; reference = wide, spacing_error, domain_error)
end

"""Require all moments in an affine continuation to agree with exact batch conditioning."""
function validate_affine_engine(affine)
    model = merge(affine.model, (transition_derivative = (x, t) -> 0.75 + 0.01t,))
    for observations in (affine.observations, collect(coalesce.(affine.observations, 0.1)))
        exact = dense_affine_reference(observations;
            slopes = [0.75 + 0.01t for t in 3:7], offsets = [0.08 - 0.02t for t in 3:7],
            process_variance = model.process_variance, observation_variance = model.observation_variance,
            initial_mean = model.initial_mean, initial_variance = model.initial_variance,
            observation = model.observation, observation_offset = model.observation_offset)
        batch = CausalDynamics.infer_nonlinear_state_space(observations; model...)
        first = CausalDynamics.infer_nonlinear_state_space(observations[1:3]; model...)
        next = CausalDynamics.update_state_posterior(first, observations[4:6])
        @testset "Affine engine and continuation, missing=$(any(ismissing, observations))" begin
            @test maximum(abs.(vec(batch.filtering_means) - exact.filtering_means)) < 1e-6
            @test maximum(abs.([P[1, 1] for P in batch.filtering_covariances] - exact.filtering_variances)) < 1e-6
            @test maximum(abs.(vec(batch.smoothing_means) - exact.smoothing_means)) < 1e-6
            @test maximum(abs.(CausalDynamics.trajectory_covariance(batch) - exact.trajectory_covariance)) < 1e-6
            @test maximum(abs.(vec(next.filtering_means) - exact.filtering_means[4:6])) < 1e-6
            @test maximum(abs.([P[1, 1] for P in next.filtering_covariances] - exact.filtering_variances[4:6])) < 1e-6
            @test maximum(abs.(vec(next.smoothing_means) - exact.smoothing_means[4:6])) < 1e-6
            @test maximum(abs.(CausalDynamics.trajectory_covariance(next) - exact.trajectory_covariance[4:6, 4:6])) < 1e-6
        end
    end
end

"""Report marginal interval content under the independently conditioned nonlinear model."""
function report_approximation(io, name, observations, model, reference)
    result = CausalDynamics.infer_nonlinear_state_space(observations; model...)
    covariance = CausalDynamics.trajectory_covariance(result)
    error = moment_disagreement(result.smoothing_means, covariance, reference)
    @printf(io, "%s approximation: backend=%s; maximum mean error/reference SD=%.6g; relative joint covariance Frobenius error=%.6g\n",
        name, string(result.backend), error.standardised_mean, error.relative_covariance)
    for t in eachindex(observations)
        μ, σ = result.smoothing_means[t, 1], sqrt(result.smoothing_covariances[t][1, 1])
        content = interval_content(reference, t, μ - 1.959963984540054σ, μ + 1.959963984540054σ)
        @printf(io, "%s t=%d reference modes=%s; Gaussian 95%% interval posterior content=%.6f\n",
            name, model.initial_time + t - 1, string(mode_locations(reference, t)), content)
    end
    return result, error
end

"""Sweep sine amplitude under a shared design; report when the Gaussian surrogate drifts."""
function report_nonlinearity_sweep(io, observations; amplitudes = (0.0, 0.05, 0.2, 0.5, 1.0),
    process_variance = 0.15, observation_variance = 0.25,
    initial_mean = 0.0, initial_variance = 0.8,
    observation = 1.0, observation_offset = 0.0, initial_time = 0,
    bounds = (-6.0, 6.0), coarse_points = 201, fine_points = 401,
    wide_bounds = (-9.0, 9.0), wide_points = 601)
    println(io, "Increasing-nonlinearity sweep: transition 0.8x + α sin(x); same observations and noise.")
    println(io, "Amplitude α is diagnostic only; the prespecified gate remains α = 0.05.")
    rows = NamedTuple[]
    for α in amplitudes
        model = (transition = (x, t) -> 0.8x + α * sin(x),
            transition_derivative = (x, t) -> 0.8 + α * cos(x),
            process_variance, observation_variance, initial_mean, initial_variance,
            observation, observation_offset, initial_time)
        name = @sprintf("sine_α=%.2f", α)
        refined = reference_refinement(io, name, observations, model;
            bounds, coarse_points, fine_points, wide_bounds, wide_points)
        result, error = report_approximation(io, name, observations, model, refined.reference)
        modes = [mode_locations(refined.reference, t) for t in eachindex(observations)]
        push!(rows, (; α, standardised_mean = error.standardised_mean,
            relative_covariance = error.relative_covariance,
            max_modes = maximum(length, modes), backend = string(result.backend),
            spacing_mean = refined.spacing_error.standardised_mean,
            domain_mean = refined.domain_error.standardised_mean))
    end
    @printf(io, "Nonlinearity sweep summary (α, mean_error/SD, relative_cov, max_modes):\n")
    for row in rows
        @printf(io, "  α=%g: mean=%.6g; cov=%.6g; max_modes=%d; backend=%s\n",
            row.α, row.standardised_mean, row.relative_covariance, row.max_modes, row.backend)
    end
    return rows
end

"""Benchmark warm API calls separately from independent reference computation."""
function report_warm_benchmark(io, observations, model; samples = 20)
    infer_once() = CausalDynamics.infer_nonlinear_state_space(observations; model...)
    first = @timed infer_once()
    infer_once()
    measurements = [@timed infer_once() for _ in 1:samples]
    @printf(io, "API first call at benchmark stage: %.6gs compile=%.6gs (earlier validation may already have compiled this API)\n",
        first.time, first.compile_time)
    @printf(io, "Warm complete-API median: %.6gs; %.0f bytes; samples=%d; BLAS threads=%d\n",
        median(getproperty.(measurements, :time)), median(getproperty.(measurements, :bytes)), samples, BLAS.get_num_threads())
    println(io, "Warm timing excludes independent reference construction; it is not an MCMC or backend speed comparison.")
end

"""Run fixed numerical gates and emit a reproducible, bounded-scope validation report."""
function run_nonlinear_validation(report_path; reference_only = false)
    affine = validate_affine_reference()
    open(report_path, "w") do io
        println(io, "Scalar known-noise nonlinear state validation")
        println(io, "Julia ", VERSION, "; threads=", Threads.nthreads(), "; BLAS threads=", BLAS.get_num_threads())
        println(io, "Deterministic original-model trapezoidal-grid conditioning; forward transition columns are not normalised.")
        println(io, "Affine reference versus independent dense Gaussian oracle: PASS; all filtering/smoothing moments and joint covariance blocks <1e-6.")
        @printf(io, "Affine reference maximum absolute errors: filtered mean=%.6g; filtered variance=%.6g; smoothed mean=%.6g; joint covariance=%.6g\n",
            maximum(abs.(affine.reference.filtering_means - affine.exact.filtering_means)),
            maximum(abs.(affine.reference.filtering_variances - affine.exact.filtering_variances)),
            maximum(abs.(affine.reference.smoothing_means - affine.exact.smoothing_means)),
            maximum(abs.(affine.reference.trajectory_covariance - affine.exact.trajectory_covariance)))
        weak_model = (transition = (x, t) -> 0.8x + 0.05sin(x),
            transition_derivative = (x, t) -> 0.8 + 0.05cos(x),
            process_variance = 0.15, observation_variance = 0.25,
            initial_mean = 0.0, initial_variance = 0.8,
            observation = 1.0, observation_offset = 0.0, initial_time = 0)
        weak_observations = [0.2, -0.1, 0.4, 0.3, -0.2, 0.1]
        missing_observations = Union{Missing,Float64}[0.2, missing, 0.4, missing, -0.2, 0.1]
        weak = reference_refinement(io, "weak", weak_observations, weak_model)
        absent = reference_refinement(io, "weak_missing", missing_observations, weak_model)
        @testset "Prespecified weak reference refinement" begin
            for error in (weak.spacing_error, weak.domain_error)
                @test error.standardised_mean < 1e-4
                @test error.relative_covariance < 1e-4
            end
        end
        bimodal_model = merge(weak_model, (transition = (x, t) -> 1.5tanh(x),
            transition_derivative = (x, t) -> 1.5 * (1 - tanh(x)^2),
            process_variance = 0.03, observation_variance = 4.0))
        bimodal_observations = fill(missing, 8)
        bimodal = reference_refinement(io, "two_well", bimodal_observations, bimodal_model;
            bounds = (-5.0, 5.0), coarse_points = 201, fine_points = 401,
            wide_bounds = (-7.0, 7.0), wide_points = 561)
        @testset "Reference two-well diagnostic" begin
            @test length(mode_locations(bimodal.reference, 8)) == 2
            @test maximum(bimodal.reference.posterior_boundary_mass) < 1e-8
        end
        println(io, "two_well final reference mode locations: ", mode_locations(bimodal.reference, 8))
        if !reference_only
            validate_affine_engine(affine)
            println(io, "Affine engine/batch/continuation against dense oracle: PASS; every new-segment moment/covariance block <1e-6.")
            _, weak_error = report_approximation(io, "weak", weak_observations, weak_model, weak.reference)
            @testset "Prespecified weak approximation accuracy" begin
                @test weak_error.standardised_mean <= 0.2
                @test weak_error.relative_covariance <= 0.25
            end
            report_approximation(io, "weak_missing", missing_observations, weak_model, absent.reference)
            report_nonlinearity_sweep(io, weak_observations)
            try
                report_approximation(io, "two_well", bimodal_observations, bimodal_model, bimodal.reference)
            catch error
                println(io, "two_well numerical failure: ", sprint(showerror, error))
                rethrow()
            end
            report_warm_benchmark(io, weak_observations, weak_model)
        else
            println(io, "Reference-only run: engine accuracy, continuation and timing were not evaluated.")
        end
        println(io, "Limits: finite grids approximate the original nonlinear posterior. Lost-mass deficits are signed and may be slightly negative at quadrature/roundoff scale. Lost-mass and edge diagnostics are not rigorous error bounds; spacing and wider-domain results quantify observed refinement.")
        println(io, "These deterministic fixtures establish no universal nonlinear coverage or calibration claim. Gaussian interval content is conditional posterior mass, not repeated-sampling coverage.")
        println(io, "PASS: all applicable prespecified gates.")
    end
    print(read(report_path, String))
    return report_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    reference_only = "--reference-only" in ARGS
    report_arguments = filter(!=("--reference-only"), ARGS)
    if !reference_only
        @eval using CausalDynamics, RxInfer, GraphPPL, DataFrames
    end
    run_nonlinear_validation(isempty(report_arguments) ? "/private/tmp/cdcs-nonlinear-validation.txt" : first(report_arguments); reference_only)
end
