using CausalDynamics
using Test
using Random
using Graphs

"""
Simulate multi-environment linear ODE dynamics:
  Ẏ = α Y + β X₁  (true parents include X₁; X₂ is spurious)
with environment-dependent levels.
"""
function _ode_parent_synthetic(; L = 40, n_env = 4, reps_per_env = 2, seed = 1)
    rng = Random.Xoshiro(seed)
    times = collect(range(0.0, 4.0; length = L))
    trajectories = Matrix{Float64}[]
    env = Int[]
    α, β = -0.5, 1.2
    for e in 1:n_env
        for _ in 1:reps_per_env
            X1 = 0.5 + 0.3 * e .+ 0.1 .* sin.(times .+ 0.2 * e) .+ 0.02 .* randn(rng, L)
            X2 = randn(rng, L)
            Y = zeros(L)
            Y[1] = 0.2 + 0.1 * e
            dt = times[2] - times[1]
            for ℓ in 1:(L - 1)
                dY = α * Y[ℓ] + β * X1[ℓ] + 0.02 * randn(rng)
                Y[ℓ + 1] = Y[ℓ] + dt * dY
            end
            push!(trajectories, vcat(Y', X1', X2'))
            push!(env, e)
        end
    end
    return times, trajectories, env
end

@testset "ODE parent discovery" begin
    times, trajectories, env = _ode_parent_synthetic()

    @testset "candidate_parent_sets" begin
        ms = candidate_parent_sets(3; max_size = 2)
        @test [1] in ms
        @test [1, 2] in ms
        @test length(ms) == 3 + 3
    end

    @testset "finite-difference ranking recovers X1 over X2" begin
        result = infer_ode_parents(times, trajectories, env, 1; max_size = 2, K = 3)
        @test result isa ODEParentRanking
        @test length(result.model_scores) == length(result.models)
        @test result.variable_scores[2] ≥ result.variable_scores[3] - 1e-8
        spec = ode_parent_ranking_to_continuous_spec(result, [:Y, :X1, :X2]; max_parents = 1)
        @test first(spec.parents[:Y]) in (:X1, :Y)
    end

    @testset "DataInterpolations spline derivatives" begin
        using DataInterpolations
        @test has_data_interpolations()
        result = infer_ode_parents(times, trajectories, env, 1; max_size = 2, K = 3)
        @test result.variable_scores[2] ≥ result.variable_scores[3] - 1e-8
        dy = finite_difference_derivative(times, vec(trajectories[1][1, :]))
        ext = Base.get_extension(CausalDynamics, :CausalDynamicsDataInterpolationsExt)
        dy_s = ext.spline_derivative(times, vec(trajectories[1][1, :]))
        @test length(dy_s) == length(dy)
        @test maximum(abs, dy_s .- dy) < 5.0
    end

    @testset "with_parents / ranked_variables_to_parents" begin
        spec0 = ContinuousCDMSpec([:Y, :X1, :X2])
        pa = ranked_variables_to_parents([3, 1, 2], [:Y, :X1, :X2]; target = :Y, max_parents = 1)
        spec = with_parents(spec0, pa)
        @test spec.parents[:Y] == [:X1]
        @test ne(continuous_cdm_graph(spec)) == 1
    end
end
