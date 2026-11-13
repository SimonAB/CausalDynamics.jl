using Test, LinearAlgebra, CausalDynamics, RxInfer, GraphPPL, DataFrames
isdefined(@__MODULE__, :NonlinearStateReference) || include("nonlinear_state_reference.jl")

@testset "Independent nonlinear state accuracy" begin
    reference = NonlinearStateReference
    y = [0.2, -0.1, 0.4, 0.3, -0.2, 0.1]
    constants = (process_variance = 0.15, observation_variance = 0.25,
        initial_mean = 0.0, initial_variance = 0.8)
    affine = reference.grid_reference(y; constants..., transition = (x,t) -> 0.8x,
        bounds = (-6.0, 6.0), points = 201)
    exact = reference.dense_affine_reference(y; constants...,
        slopes = fill(0.8, 5), offsets = zeros(5))
    @test affine.smoothing_means ≈ exact.smoothing_means atol = 1e-6
    @test affine.trajectory_covariance ≈ exact.trajectory_covariance atol = 1e-6

    transition = (x,t) -> 0.8x + 0.05sin(x)
    coarse = reference.grid_reference(y; constants..., transition, bounds = (-6.0, 6.0), points = 201)
    fine = reference.grid_reference(y; constants..., transition, bounds = (-6.0, 6.0), points = 401)
    wider = reference.grid_reference(y; constants..., transition, bounds = (-9.0, 9.0), points = 601)
    for (candidate, truth) in ((coarse, fine), (fine, wider))
        error = reference.moment_disagreement(candidate.smoothing_means, candidate.trajectory_covariance, truth)
        @test error.standardised_mean <= 1e-4
        @test error.relative_covariance <= 1e-4
    end
    fit = infer_nonlinear_state_space(y; constants..., transition,
        transition_derivative = (x,t) -> 0.8 + 0.05cos(x))
    error = reference.moment_disagreement(fit.smoothing_means, trajectory_covariance(fit), wider)
    # Fixed before implementation; reference refinement and approximation
    # accuracy remain separate gates.
    @test error.standardised_mean <= 0.20
    @test error.relative_covariance <= 0.25
end
