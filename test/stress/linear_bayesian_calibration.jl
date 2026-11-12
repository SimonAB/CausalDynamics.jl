# Run from an environment containing CausalDynamics and its RxInfer test extras:
# julia --project=. --threads=auto test/stress/linear_bayesian_calibration.jl
# An optional first argument selects the plain-text report path.
const STATE_IMPORT_START_NS = time_ns()
using CausalDynamics, RxInfer, GraphPPL, DataFrames, Random, Statistics, LinearAlgebra, Printf
# Separate top-level timestamps include package loading and precompilation.
const STATE_IMPORT_SECONDS = (time_ns() - STATE_IMPORT_START_NS) / 1e9

const STATE_CALIBRATION_MODEL = (
    transition = 0.85, observation = 1.2,
    process_covariance = 0.15, observation_covariance = 0.4,
    initial_mean = -0.2, initial_covariance = 0.9,
    transition_offset = 0.08, observation_offset = -0.15)

"""Simulate a trajectory from the model's stated initial prior and mechanisms."""
function prior_predictive_states(rng, n, model)
    x, y = zeros(n), zeros(n)
    x[1] = model.initial_mean + sqrt(model.initial_covariance) * randn(rng)
    for t in 1:n
        if t > 1
            x[t] = model.transition * x[t - 1] + model.transition_offset +
                sqrt(model.process_covariance) * randn(rng)
        end
        y[t] = model.observation * x[t] + model.observation_offset +
            sqrt(model.observation_covariance) * randn(rng)
    end
    return x, y
end

"""Construct independent dense information-form trajectory covariances."""
function state_oracle_covariances(n, observed, model)
    covariances = Matrix{Float64}[]
    F, H, Q, R = model.transition, model.observation,
        model.process_covariance, model.observation_covariance
    for horizon in 1:n
        precision = zeros(horizon, horizon)
        precision[1, 1] = 1 / model.initial_covariance
        for t in 2:horizon
            precision[t - 1, t - 1] += F^2 / Q
            precision[t, t] += 1 / Q
            precision[t - 1, t] -= F / Q
            precision[t, t - 1] -= F / Q
        end
        for t in 1:horizon
            observed[t] && (precision[t, t] += H^2 / R)
        end
        push!(covariances, inv(Symmetric(precision)))
    end
    return covariances
end

"""Construct the dense oracle's information vector independently of the API."""
function state_oracle_information(y, observed, model, horizon)
    information = zeros(horizon)
    information[1] = model.initial_mean / model.initial_covariance
    for t in 2:horizon
        information[t - 1] -= model.transition * model.transition_offset / model.process_covariance
        information[t] += model.transition_offset / model.process_covariance
    end
    for t in 1:horizon
        if observed[t]
            information[t] += model.observation * (y[t] - model.observation_offset) /
                model.observation_covariance
        end
    end
    return information
end

function state_moment_errors(result, y, observed, covariances, model)
    n = length(y)
    smooth_mean = covariances[end] * state_oracle_information(y, observed, model, n)
    errors = [maximum(abs.(result.smoothing_means[:, 1] - smooth_mean)),
        maximum(abs.([result.smoothing_covariances[t][1, 1] - covariances[end][t, t] for t in 1:n]))]
    for t in 1:n
        filtered_mean = (covariances[t] * state_oracle_information(y, observed, model, t))[end]
        push!(errors, abs(result.filtering_means[t, 1] - filtered_mean))
        push!(errors, abs(result.filtering_covariances[t][1, 1] - covariances[t][end, end]))
    end
    push!(errors, maximum(abs.(CausalDynamics.trajectory_covariance(result) - covariances[end])))
    return maximum(errors)
end

"""Report independent-replicate coverage and dependence-aware aggregate MCSE."""
function print_state_coverage(io, name, standardised_errors)
    repetitions, n = size(standardised_errors)
    covered = abs.(standardised_errors) .<= 1.959963984540054
    for t in (n ÷ 2, n)
        coverage = mean(covered[:, t])
        mcse = sqrt(coverage * (1 - coverage) / repetitions)
        @printf(io, "%s t=%d: coverage=%.4f MCSE=%.4f (replicates=%d)\n",
            name, t, coverage, mcse, repetitions)
        # A broad Monte Carlo tolerance diagnoses gross calibration errors.
        @assert abs(coverage - 0.95) <= 4 * sqrt(0.95 * 0.05 / repetitions)
    end
    replicate_coverage = vec(mean(covered; dims = 2))
    @printf(io, "%s across-time coverage=%.4f cluster-MCSE=%.4f\n", name,
        mean(replicate_coverage), std(replicate_coverage) / sqrt(repetitions))
    @printf(io, "%s standardised errors t=%d: mean=%.4f variance=%.4f\n", name,
        n ÷ 2, mean(standardised_errors[:, n ÷ 2]), var(standardised_errors[:, n ÷ 2]))
end

function state_warmed_benchmark(observations, model; samples = 20)
    infer_once() = CausalDynamics.infer_linear_state_space(observations; model...)
    infer_once()
    GC.gc()
    timings = [@timed infer_once() for _ in 1:samples]
    allocations = [@allocations infer_once() for _ in 1:samples]
    return (seconds = median(getproperty.(timings, :time)),
        bytes = median(getproperty.(timings, :bytes)), allocations = median(allocations),
        compile_seconds = sum(getproperty.(timings, :compile_time)), samples = samples)
end

function run_state_calibration(report_path; repetitions = 500, n = 20, seed = 20261112)
    model = STATE_CALIBRATION_MODEL
    rng = MersenneTwister(seed)
    complete = trues(n)
    observed = trues(n)
    observed[[3, 7, 12, 18]] .= false
    complete_oracle = state_oracle_covariances(n, complete, model)
    missing_oracle = state_oracle_covariances(n, observed, model)
    _, timing_y = prior_predictive_states(MersenneTwister(seed + 1), n, model)
    timing_missing = Union{Missing,Float64}[observed[t] ? timing_y[t] : missing for t in 1:n]

    # First calls are measured separately; their wall time includes compilation.
    cold_native = @timed CausalDynamics.infer_linear_state_space(timing_y; model...)
    cold_missing = @timed CausalDynamics.infer_linear_state_space(timing_missing; model...)
    @assert cold_native.value.backend == :rxinfer
    @assert cold_missing.value.backend == :analytic_rts
    native_timing = state_warmed_benchmark(timing_y, model)
    missing_timing = state_warmed_benchmark(timing_missing, model)

    z = Dict(key => zeros(repetitions, n) for key in
        (:native_filter, :native_smoother, :missing_filter, :missing_smoother))
    max_oracle_error = 0.0
    calibration_seconds = @elapsed for repetition in 1:repetitions
        x, y = prior_predictive_states(rng, n, model)
        incomplete = Union{Missing,Float64}[observed[t] ? y[t] : missing for t in 1:n]
        native = CausalDynamics.infer_linear_state_space(y; model...)
        analytic = CausalDynamics.infer_linear_state_space(incomplete; model...)
        @assert native.backend == :rxinfer && analytic.backend == :analytic_rts
        max_oracle_error = max(max_oracle_error,
            state_moment_errors(native, y, complete, complete_oracle, model),
            state_moment_errors(analytic, y, observed, missing_oracle, model))
        for (prefix, result) in ((:native, native), (:missing, analytic))
            for (label, means, covariances) in
                ((:filter, result.filtering_means, result.filtering_covariances),
                 (:smoother, result.smoothing_means, result.smoothing_covariances))
                key = Symbol(prefix, :_, label)
                z[key][repetition, :] = [(x[t] - means[t, 1]) / sqrt(covariances[t][1, 1]) for t in 1:n]
            end
        end
        repetition % 100 == 0 && println("Calibration trajectories completed: ", repetition, "/", repetitions)
    end
    @assert max_oracle_error < 1e-9

    open(report_path, "w") do io
        println(io, "Linear Gaussian prior-predictive state calibration")
        println(io, "Julia ", VERSION, "; threads=", Threads.nthreads(),
            "; RxInfer ", pkgversion(RxInfer), "; CausalDynamics ", pkgversion(CausalDynamics))
        println(io, "Seed=", seed, "; independent trajectories=", repetitions,
            "; states per trajectory=", n, "; nominal marginal interval=95%")
        println(io, "Known model: ", model)
        println(io, "Analytic design omits measurement likelihoods at t=3,7,12,18; native design observes every time.")
        println(io, "Intervals condition on known parameters; calibration averages over the stated initial prior and generative mechanisms.")
        println(io, "Pointwise MCSE treats trajectories as independent, never the repeated times within a trajectory.")
        println(io, "Across-time MCSE uses one mean coverage fraction per independent trajectory.")
        for key in (:native_filter, :native_smoother, :missing_filter, :missing_smoother)
            print_state_coverage(io, string(key), z[key])
        end
        @printf(io, "Maximum absolute posterior mean/covariance error against dense information oracle: %.3e\n", max_oracle_error)
        @printf(io, "Package/helper import wall seconds: %.6f\n", STATE_IMPORT_SECONDS)
        for (label, cold, warm) in (("native_complete", cold_native, native_timing),
            ("analytic_missing", cold_missing, missing_timing))
            @printf(io, "%s first-call wall=%.6fs compile=%.6fs bytes=%d\n",
                label, cold.time, cold.compile_time, cold.bytes)
            @printf(io, "%s warmed medians: wall=%.6fs bytes=%.0f allocation_count=%.0f samples=%d; summed compile=%.6fs\n",
                label, warm.seconds, warm.bytes, warm.allocations, warm.samples, warm.compile_seconds)
        end
        @printf(io, "Calibration loop wall seconds: %.6f\n", calibration_seconds)
        println(io, "Timings describe this local process and include complete API/result construction; they compare different observation patterns and are not a controlled backend speed ratio.")
        println(io, "PASS: all exact-moment checks and prespecified four-MCSE pointwise calibration tolerances.")
    end
    print(read(report_path, String))
    return report_path
end

if abspath(PROGRAM_FILE) == @__FILE__
    run_state_calibration(isempty(ARGS) ? "/private/tmp/cdcs-state-calibration.txt" : ARGS[1])
end
