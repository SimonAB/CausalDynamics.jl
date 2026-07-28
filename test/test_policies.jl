using CausalDynamics
using Test
using Random
using Statistics

"""
Treatment-response CDM: `A_t` is intervenable, `Y_t = 2·A_t + U^y_t`.
"""
function _policy_cdm()
    return DiscreteTimeCDM(
        [:a, :y];
        initialise = (rng) -> (a = 0.0, y = 0.0),
        sample_noise = (rng, state, t) -> (u_a = randn(rng), u_y = randn(rng)),
        step = (state, t, noise, intervention) -> begin
            a = intervention_value(intervention, :a, t, 0.5 * state.a + noise.u_a, state)
            y = 2a + noise.u_y
            (a = a, y = y)
        end,
    )
end

@testset "Policies and g-computation" begin
    @testset "Policy is an AbstractIntervention" begin
        π = policy(:a, (state, t) -> state.a > 0 ? 1.0 : 0.0)
        @test π isa Policy
        @test π isa AbstractIntervention
        @test do_sequence(:a, 1.0) isa AbstractIntervention
    end

    @testset "state-dependent policy drives assignment" begin
        cdm = _policy_cdm()
        T = 10
        # Threshold policy: treat whenever previous A was non-positive
        π = policy(:a, (state, t) -> state.a <= 0 ? 1.0 : -1.0)
        traj = simulate(cdm, T; rng = Random.Xoshiro(1), intervention = π)
        for t in 2:T
            expected = traj.series[:a][t - 1] <= 0 ? 1.0 : -1.0
            @test traj.series[:a][t] == expected
        end
    end

    @testset "policy leaves unnamed variables observational" begin
        cdm = _policy_cdm()
        π = policy(:a, (state, t) -> 1.0)
        traj = simulate(cdm, 5; rng = Random.Xoshiro(2), intervention = π)
        # Y is not intervened: it follows the structural map given A and U^y
        for t in 2:5
            @test traj.series[:y][t] ≈ 2 * traj.series[:a][t] + traj.noise[:u_y][t]
        end
    end

    @testset "policy works in counterfactual with shared U" begin
        cdm = _policy_cdm()
        T = 8
        factual = simulate(cdm, T; rng = Random.Xoshiro(3))
        π = policy(:a, (state, t) -> 1.0)
        cf = counterfactual(cdm, factual.noise; intervention = π)
        @test cf.noise[:u_y] == factual.noise[:u_y]
        @test all(cf.series[:a][2:T] .== 1.0)
    end

    @testset "g_computation compares interventions" begin
        cdm = _policy_cdm()
        T = 6
        treated = g_computation(
            cdm, T, :y;
            intervention = do_sequence(:a, 1.0),
            n = 200,
            rng = Random.Xoshiro(4),
        )
        control = g_computation(
            cdm, T, :y;
            intervention = do_sequence(:a, 0.0),
            n = 200,
            rng = Random.Xoshiro(4),
        )
        # E[Y | do(A=1)] − E[Y | do(A=0)] ≈ 2 (structural coefficient)
        @test isapprox(treated.mean - control.mean, 2.0; atol = 0.3)
        @test treated.n == 200
        @test length(treated.samples) == 200
    end

    @testset "g_computation errors on unknown outcome" begin
        cdm = _policy_cdm()
        @test_throws ArgumentError g_computation(
            cdm, 5, :nope;
            intervention = do_sequence(:a, 1.0),
            n = 5,
        )
    end
end
