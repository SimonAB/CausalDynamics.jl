using Test, LinearAlgebra, CausalDynamics, RxInfer, GraphPPL, DataFrames
isdefined(@__MODULE__, :NonlinearStateReference) || include("nonlinear_state_reference.jl")

# The shared dense information-form oracle is defined by test_linear_state_space.jl.
# A deterministic translation removes the time-dependent transition offset,
# leaving a constant affine Gaussian model for that independent oracle.
@testset "Known-noise nonlinear Gaussian states" begin
    n, initial_time = 5, 3
    parameters = (transition = (x, t) -> 0.8x + 0.07t,
        transition_derivative = (x, t) -> 0.8,
        process_variance = 0.15, observation_variance = 0.25,
        observation = 1.2, observation_offset = -0.3,
        initial_mean = 0.2, initial_variance = 0.8, initial_time = initial_time)
    shift = zeros(n)
    for j in 2:n
        shift[j] = 0.8shift[j - 1] + 0.07(initial_time + j - 2)
    end
    y = [0.2, -0.1, 0.4, 0.3, -0.2]
    for missing_data in (false, true)
        data = missing_data ? Union{Missing,Float64}[y...] : copy(y)
        missing_data && (data[3] = missing)
        centred = reshape(data .- parameters.observation .* shift, :, 1)
        oracle_parameters = (transition = reshape([0.8], 1, 1),
            observation = reshape([parameters.observation], 1, 1),
            process_covariance = reshape([0.15], 1, 1),
            observation_covariance = reshape([0.25], 1, 1),
            initial_mean = [0.2], initial_covariance = reshape([0.8], 1, 1),
            observation_offset = [-0.3])
        expected_mean, expected_covariance = dense_linear_state_oracle(centred; oracle_parameters...)
        fit = CausalDynamics.infer_nonlinear_state_space(data; parameters...)
        @test fit.smoothing_means[:, 1] ≈ expected_mean[:, 1] + shift atol=1e-8
        @test CausalDynamics.trajectory_covariance(fit) ≈ expected_covariance atol=1e-8
        for t in 1:n, s in 1:n
            @test only(CausalDynamics.state_crosscovariance(fit, t, s)) ≈ expected_covariance[t, s] atol=1e-8
        end
        for j in 1:n
            prefix_mean, prefix_covariance = dense_linear_state_oracle(centred[1:j, :]; oracle_parameters...)
            @test fit.filtering_means[j, 1] ≈ prefix_mean[end] + shift[j] atol=1e-8
            @test only(fit.filtering_covariances[j]) ≈ prefix_covariance[end, end] atol=1e-8
        end
        @test fit.n == n
        @test fit.certificate.exact === false
        @test fit.certificate.parameters == :known
        @test fit.certificate.approximation == :extended_kalman_rts
        @test fit.certificate.linearisation == :filtering_means
        @test fit.certificate.covariance == :local_gaussian
        @test fit.certificate.initial_time == initial_time
        @test fit.certificate.surrogate_exact === true
        @test fit.backend == (missing_data ? :analytic_rts : :rxinfer)
        @test isnothing(fit.raw) == missing_data
        @test fit.linearisation_slopes ≈ fill(0.8, n - 1)
        @test fit.linearisation_offsets ≈ 0.07 .* collect(initial_time:(initial_time + n - 2))
        @test size(fit.predicted_means) == (n, 1)
        @test length(fit.predicted_variances) == n
        first = CausalDynamics.infer_nonlinear_state_space(data[1:2]; parameters...)
        continued = CausalDynamics.update_state_posterior(first, data[3:end])
        @test continued.model.initial_time == initial_time + 2
        @test continued.filtering_means ≈ fit.filtering_means[3:end, :] atol=1e-8
        @test continued.smoothing_means ≈ fit.smoothing_means[3:end, :] atol=1e-8
        @test CausalDynamics.trajectory_covariance(continued) ≈ expected_covariance[3:end, 3:end] atol=1e-8
        sequential = first
        for j in 3:n
            sequential = CausalDynamics.update_state_posterior(sequential, data[j:j])
            @test sequential.posterior.mean ≈ fit.filtering_means[j, :] atol=1e-8
            @test sequential.posterior.covariance ≈ fit.filtering_covariances[j] atol=1e-8
        end
    end

    @testset "Time-varying affine slope and offset" begin
        varying = merge(parameters, (transition = (x,t) -> (0.75 + 0.01t)*x + 0.08 - 0.02t,
            transition_derivative = (x,t) -> 0.75 + 0.01t))
        times = initial_time:(initial_time + n - 2)
        for data in (y, Union{Missing,Float64}[y[1], missing, y[3], y[4], y[5]])
            oracle = NonlinearStateReference.dense_affine_reference(data;
                slopes = 0.75 .+ 0.01 .* times, offsets = 0.08 .- 0.02 .* times,
                process_variance = 0.15, observation_variance = 0.25,
                initial_mean = 0.2, initial_variance = 0.8,
                observation = 1.2, observation_offset = -0.3)
            fit = CausalDynamics.infer_nonlinear_state_space(data; varying...)
            @test vec(fit.filtering_means) ≈ oracle.filtering_means atol=1e-8
            @test only.(fit.filtering_covariances) ≈ oracle.filtering_variances atol=1e-8
            @test vec(fit.smoothing_means) ≈ oracle.smoothing_means atol=1e-8
            @test CausalDynamics.trajectory_covariance(fit) ≈ oracle.trajectory_covariance atol=1e-8
            for t in 1:n, s in 1:n
                @test only(CausalDynamics.state_crosscovariance(fit, t, s)) ≈ oracle.trajectory_covariance[t,s] atol=1e-8
            end
            first = CausalDynamics.infer_nonlinear_state_space(data[1:2]; varying...)
            continued = CausalDynamics.update_state_posterior(first, data[3:end])
            @test vec(continued.smoothing_means) ≈ oracle.smoothing_means[3:end] atol=1e-8
            @test CausalDynamics.trajectory_covariance(continued) ≈ oracle.trajectory_covariance[3:end,3:end] atol=1e-8
        end
    end

    @testset "Nonlinear filtering linearisation and Gaussian surrogate" begin
        nonlinear = merge(parameters, (transition = (x,t) -> 0.8x + 0.05sin(x),
            transition_derivative = (x,t) -> 0.8 + 0.05cos(x)))
        for data in (y, Union{Missing,Float64}[y[1], missing, y[3], y[4], y[5]])
            fit = CausalDynamics.infer_nonlinear_state_space(data; nonlinear...)
            for j in 1:(n - 1)
                μ = fit.filtering_means[j,1]
                @test fit.linearisation_slopes[j] ≈ 0.8 + 0.05cos(μ)
                @test fit.linearisation_offsets[j] ≈ 0.8μ + 0.05sin(μ) - fit.linearisation_slopes[j]*μ
                @test fit.predicted_means[j+1,1] ≈ 0.8μ + 0.05sin(μ)
            end
            # This oracle conditions the stored surrogate, independently of the
            # RTS recursion. Original-model accuracy has separate grid gates.
            oracle = NonlinearStateReference.dense_affine_reference(data;
                slopes=fit.linearisation_slopes, offsets=fit.linearisation_offsets,
                process_variance=0.15, observation_variance=0.25,
                initial_mean=0.2, initial_variance=0.8,
                observation=1.2, observation_offset=-0.3)
            @test vec(fit.filtering_means) ≈ oracle.filtering_means atol=1e-8
            @test vec(fit.smoothing_means) ≈ oracle.smoothing_means atol=1e-8
            @test CausalDynamics.trajectory_covariance(fit) ≈ oracle.trajectory_covariance atol=1e-8
        end
    end

    @testset "Initial timing, missing observations and zero observation" begin
        # No callback is evaluated for an initial observation without transition.
        no_transition = merge(parameters, (transition = (x,t) -> error("unexpected transition"),
            transition_derivative = (x,t) -> error("unexpected derivative")))
        one = CausalDynamics.infer_nonlinear_state_space([missing]; no_transition...)
        @test only(one.posterior.mean) == parameters.initial_mean
        @test only(one.posterior.covariance) == parameters.initial_variance
        observed = CausalDynamics.infer_nonlinear_state_space([0.4]; parameters...)
        expected_variance = inv(inv(0.8) + 1.2^2 / 0.25)
        @test only(observed.posterior.covariance) ≈ expected_variance
        @test only(observed.posterior.mean) ≈ expected_variance * (0.2 / 0.8 + 1.2 * (0.4 + 0.3) / 0.25)
        zero = CausalDynamics.infer_nonlinear_state_space(y; merge(parameters, (observation=0.0,))...)
        absent = CausalDynamics.infer_nonlinear_state_space(fill(missing, n); parameters...)
        @test zero.backend == :analytic_rts
        @test zero.certificate.reason == :zero_observation
        @test zero.raw === nothing
        @test zero.smoothing_means ≈ absent.smoothing_means
        @test CausalDynamics.trajectory_covariance(zero) ≈ CausalDynamics.trajectory_covariance(absent)
        @test all(size(K) == (1, 0) for K in absent.filtering_gains)
        changed = CausalDynamics.update_state_posterior(observed, [missing]; transition=(x,t)->x+t,
            transition_derivative=(x,t)->1.0, process_variance=0.4)
        @test only(changed.posterior.mean) ≈ only(observed.posterior.mean) + initial_time
        @test only(changed.posterior.covariance) ≈ only(observed.posterior.covariance) + 0.4
    end

    @testset "Validation and numerical failure" begin
        infer_with(data; kwargs...) = CausalDynamics.infer_nonlinear_state_space(data; merge(parameters, (;kwargs...))...)
        for data in (Float64[], [Inf], [NaN], ["bad"], zeros(2,1))
            @test_throws ArgumentError infer_with(data)
        end
        for key in (:process_variance, :observation_variance, :initial_variance)
            for value in (0.0, -1.0, Inf, NaN, [1.0])
                @test_throws ArgumentError infer_with(y; NamedTuple{(key,)}((value,))...)
            end
        end
        for key in (:initial_mean, :observation, :observation_offset)
            for value in (Inf, NaN, [1.0])
                @test_throws ArgumentError infer_with(y; NamedTuple{(key,)}((value,))...)
            end
        end
        @test_throws ArgumentError infer_with(y; initial_time=1.5)
        @test_throws ArgumentError infer_with(y; initial_time=typemax(Int))
        for key in (:transition, :transition_derivative)
            for callback in ((x,t)->Inf, (x,t)->NaN, (x,t)->[1.0], (x,t)->error("callback failed"), x->x)
                @test_throws ArgumentError infer_with(y; NamedTuple{(key,)}((callback,))...)
            end
        end
        @test_throws ArgumentError infer_with([missing, missing]; transition=(x,t)->1e308,
            transition_derivative=(x,t)->1e308)
        fit = infer_with(y[1:2])
        for key in (:initial_mean, :initial_variance, :initial_time)
            @test_throws ArgumentError CausalDynamics.update_state_posterior(fit, [0.1]; NamedTuple{(key,)}((1,))...)
        end
        @test_throws ArgumentError CausalDynamics.update_state_posterior(fit, [0.1]; process_variance=-1.0)
        @test_throws BoundsError CausalDynamics.state_crosscovariance(fit, 0, 1)
    end
end
