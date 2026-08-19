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

    @testset "integer-coded factor recode Policy" begin
        function _draw_level(u::Real, scores)
            e = exp.(scores .- maximum(scores))
            p = e ./ sum(e)
            c = 0.0
            @inbounds for k in 0:2
                c += p[k + 1]
                u <= c && return Float64(k)
            end
            return 2.0
        end
        recode_level(a) = a == 2.0 ? 1.0 : a
        structural_y(a1, a2, w) =
            1.0 * (a1 == 1.0) + (-0.5) * (a1 == 2.0) +
            0.8 * (a2 == 1.0) + (-0.4) * (a2 == 2.0) + 0.6 * w

        cdm = DiscreteTimeCDM(
            [:w, :a, :l, :y];
            initialise = (rng) -> begin
                w = randn(rng)
                a = _draw_level(rand(rng), (0.2 * w, 0.1 + 0.4 * w, -0.2 - 0.3 * w))
                l = 0.5 * (a == 2.0) + 0.4 * w + 0.3 * randn(rng)
                (w = w, a = a, l = l, y = 0.0)
            end,
            sample_noise = (rng, state, t) -> (u_a = rand(rng), u_y = 0.4 * randn(rng)),
            step = (state, t, noise, intervention) -> begin
                scores = (0.1 * state.w + 0.35 * state.l, 0.15 + 0.25 * state.w, -0.15 - 0.3 * state.l)
                a_nat = _draw_level(noise.u_a, scores)
                a = intervention_value(intervention, :a, t, a_nat, merge(state, (a = a_nat,)))
                y = structural_y(state.a, a, state.w) + noise.u_y
                (w = state.w, a = a, l = state.l, y = y)
            end,
        )
        π = policy(:a, (s, t) -> recode_level(s.a))
        rng = Random.Xoshiro(11)
        n = 40
        y_cf = Float64[]
        y_struct = Float64[]
        for _ in 1:n
            factual = simulate(cdm, 2; rng = rng)
            init = (
                w = factual.series[:w][1],
                a = factual.series[:a][1],
                l = factual.series[:l][1],
                y = factual.series[:y][1],
            )
            cf = counterfactual(cdm, factual.noise; intervention = π, initial = init)
            a1d = recode_level(factual.series[:a][1])
            a2d = recode_level(factual.series[:a][2])
            μ = structural_y(a1d, a2d, factual.series[:w][1]) + factual.noise[:u_y][2]
            @test cf.series[:a][1] == a1d
            @test cf.series[:a][2] == a2d
            @test cf.series[:y][2] ≈ μ atol = 1e-10
            push!(y_cf, cf.series[:y][2])
            push!(y_struct, μ)
        end
        @test mean(y_cf) ≈ mean(y_struct) atol = 1e-10
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
