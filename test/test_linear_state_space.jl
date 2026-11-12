using Test, LinearAlgebra, Statistics
using CausalDynamics, RxInfer, GraphPPL, DataFrames

# Independent information-form oracle for the full latent trajectory.
function dense_linear_state_oracle(y; transition, observation, process_covariance,
    observation_covariance, initial_mean, initial_covariance,
    transition_offset = zeros(length(initial_mean)),
    observation_offset = zeros(size(observation, 1)))
    n, d = size(y, 1), length(initial_mean)
    block(t) = ((t - 1) * d + 1):(t * d)
    precision = zeros(n * d, n * d)
    information = zeros(n * d)
    P⁻¹, Q⁻¹ = inv(initial_covariance), inv(process_covariance)
    precision[block(1), block(1)] += P⁻¹
    information[block(1)] += P⁻¹ * initial_mean
    for t in 2:n
        before, after = block(t - 1), block(t)
        precision[before, before] += transition' * Q⁻¹ * transition
        precision[after, after] += Q⁻¹
        precision[before, after] -= transition' * Q⁻¹
        precision[after, before] -= Q⁻¹ * transition
        information[before] -= transition' * Q⁻¹ * transition_offset
        information[after] += Q⁻¹ * transition_offset
    end
    for t in 1:n
        observed = findall(!ismissing, y[t, :])
        isempty(observed) && continue
        H = observation[observed, :]
        R⁻¹ = inv(observation_covariance[observed, observed])
        residual = Float64.(y[t, observed]) - observation_offset[observed]
        precision[block(t), block(t)] += H' * R⁻¹ * H
        information[block(t)] += H' * R⁻¹ * residual
    end
    covariance = inv(Symmetric(precision))
    return reshape(covariance * information, d, n)', covariance
end

@testset "Exact linear Gaussian state inference" begin
    model = (transition = [0.8 0.2; -0.1 0.7],
        observation = [1.0 0.3; -0.2 0.9],
        process_covariance = [0.3 0.08; 0.08 0.2],
        observation_covariance = [0.5 0.12; 0.12 0.4],
        initial_mean = [0.3, -0.2], initial_covariance = [1.1 0.25; 0.25 0.8],
        transition_offset = [0.1, -0.05], observation_offset = [0.2, 0.4])
    y = [0.2 0.6; -0.3 0.4; 0.7 -0.2; 0.8 0.1]
    expected_means, expected_covariance = dense_linear_state_oracle(y; model...)
    result = CausalDynamics.infer_linear_state_space(y; model...)
    @test result.smoothing_means ≈ expected_means atol = 1e-9
    @test CausalDynamics.trajectory_covariance(result) ≈ expected_covariance atol = 1e-9
    @test !isnothing(result.raw)
    @test result.backend == :rxinfer
    for t in axes(y, 1)
        filtered_mean, filtered_cov = dense_linear_state_oracle(y[1:t, :]; model...)
        @test result.filtering_means[t, :] ≈ filtered_mean[end, :] atol = 1e-9
        @test result.filtering_covariances[t] ≈ filtered_cov[(2t-1):(2t), (2t-1):(2t)] atol = 1e-9
        @test result.smoothing_covariances[t] ≈ expected_covariance[(2t-1):(2t), (2t-1):(2t)] atol = 1e-9
        for s in axes(y, 1)
            @test CausalDynamics.state_crosscovariance(result, t, s) ≈ expected_covariance[(2t-1):(2t), (2s-1):(2s)] atol = 1e-9
        end
    end
    @test result.posterior.mean ≈ result.filtering_means[end, :]
    @test result.posterior.covariance ≈ result.filtering_covariances[end]
    @test_throws BoundsError CausalDynamics.state_crosscovariance(result, 0, 1)

    @testset "Rectangular measurements and singular dynamics" begin
        tall_model = merge(model, (observation = [1.0 0.3; -0.2 0.9; 0.6 -0.4],
            observation_covariance = [0.5 0.12 0.0; 0.12 0.4 0.08; 0.0 0.08 0.3],
            observation_offset = [0.2, 0.4, -0.1]))
        tall_y = hcat(y, [0.1, 0.5, -0.3, 0.2])
        for (observations, parameters) in ((tall_y, tall_model),
            (y, merge(model, (transition = [0.8 0.0; 0.0 0.0],))))
            means, covariance = dense_linear_state_oracle(observations; parameters...)
            inference = CausalDynamics.infer_linear_state_space(observations; parameters...)
            @test inference.smoothing_means ≈ means atol = 1e-9
            @test CausalDynamics.trajectory_covariance(inference) ≈ covariance atol = 1e-9
        end
    end

    @testset "Missing components and incremental updates" begin
        incomplete = Matrix{Union{Missing,Float64}}(y)
        incomplete[2, 1] = missing
        incomplete[3, :] .= missing
        incomplete[4, 2] = missing
        means, covariance = dense_linear_state_oracle(incomplete; model...)
        batch = CausalDynamics.infer_linear_state_space(incomplete; model...)
        @test batch.backend == :analytic_rts
        @test isnothing(batch.raw)
        @test batch.smoothing_means ≈ means atol = 1e-9
        @test CausalDynamics.trajectory_covariance(batch) ≈ covariance atol = 1e-9
        previous = CausalDynamics.infer_linear_state_space(incomplete[1:2, :]; model...)
        updated = CausalDynamics.update_state_posterior(previous, incomplete[3:4, :])
        @test updated.filtering_means ≈ batch.filtering_means[3:4, :] atol = 1e-9
        @test updated.smoothing_means ≈ batch.smoothing_means[3:4, :] atol = 1e-9
        @test updated.posterior.mean ≈ batch.posterior.mean atol = 1e-9
        @test updated.posterior.covariance ≈ batch.posterior.covariance atol = 1e-9
        @test CausalDynamics.trajectory_covariance(updated) ≈ covariance[5:8, 5:8] atol = 1e-9
        absent = fill(missing, 3, 2)
        absent_means, absent_cov = dense_linear_state_oracle(absent; model...)
        absent_result = CausalDynamics.infer_linear_state_space(absent; model...)
        @test absent_result.smoothing_means ≈ absent_means atol = 1e-9
        @test CausalDynamics.trajectory_covariance(absent_result) ≈ absent_cov atol = 1e-9
        @test absent_result.backend == :analytic_rts
        one_missing = CausalDynamics.infer_linear_state_space(absent[1:1, :]; model...)
        @test one_missing.smoothing_means[1, :] ≈ model.initial_mean
        @test one_missing.smoothing_covariances[1] ≈ model.initial_covariance
        # A complete scalar measurement of a two-dimensional state has a
        # rank-deficient information contribution even without missing values.
        rectangular_model = merge(model, (observation = reshape([1.0, 0.3], 1, 2),
            observation_covariance = reshape([0.5], 1, 1), observation_offset = [0.2]))
        rectangular_y = y[:, 1:1]
        rectangular_means, rectangular_cov = dense_linear_state_oracle(rectangular_y; rectangular_model...)
        rectangular = CausalDynamics.infer_linear_state_space(rectangular_y; rectangular_model...)
        @test rectangular.backend == :analytic_rts
        @test rectangular.smoothing_means ≈ rectangular_means atol = 1e-9
        @test CausalDynamics.trajectory_covariance(rectangular) ≈ rectangular_cov atol = 1e-9
    end

    @testset "Scalar observations and validation" begin
        scalar_model = (transition = 0.8, observation = 1.0, process_covariance = 0.2,
            observation_covariance = 0.3, initial_mean = 0.1, initial_covariance = 1.0)
        scalar = CausalDynamics.infer_linear_state_space([0.1, missing, 0.4]; scalar_model...)
        @test size(scalar.smoothing_means) == (3, 1)
        @test scalar.filtering_means[2, 1] ≈ 0.8 * scalar.filtering_means[1, 1]
        one = CausalDynamics.infer_linear_state_space([0.2]; scalar_model...)
        @test one.backend == :rxinfer
        @test one.smoothing_means ≈ one.filtering_means
        @test CausalDynamics.trajectory_covariance(one) ≈ one.filtering_covariances[1]
        for bad in (NaN, Inf)
            @test_throws ArgumentError CausalDynamics.infer_linear_state_space([bad]; scalar_model...)
        end
        @test_throws ArgumentError CausalDynamics.infer_linear_state_space(Float64[]; scalar_model...)
        @test_throws ArgumentError CausalDynamics.infer_linear_state_space(y; model..., process_covariance = [1.0 2.0; 2.0 1.0])
        @test_throws ArgumentError CausalDynamics.infer_linear_state_space(y; model..., observation_covariance = zeros(2, 2))
        @test_throws ArgumentError CausalDynamics.infer_linear_state_space(y; model..., initial_covariance = [1.0 0.5; 0.0 1.0])
        @test_throws DimensionMismatch CausalDynamics.infer_linear_state_space(y; model..., observation = ones(3, 2))
        @test_throws DimensionMismatch CausalDynamics.infer_linear_state_space(y; model..., transition_offset = [0.1])
    end
end
