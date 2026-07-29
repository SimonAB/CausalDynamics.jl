using CausalDynamics
using Test
using Random

"""
Build a minimal two-variable CDM used across several tests.

``A_t = 0.5 A_{t-1} + U^a_t``, ``Y_t = 2 A_t + U^y_t`` (with `intervention_value` on `:a`).
"""
function _ar_cdm()
    return DiscreteTimeCDM(
        [:a, :y];
        initialise = (rng) -> (a = 0.0, y = 0.0),
        sample_noise = (rng, state, t) -> (u_a = randn(rng), u_y = randn(rng)),
        step = (state, t, noise, intervention) -> begin
            a = intervention_value(intervention, :a, t, 0.5 * state.a + noise.u_a)
            y = 2a + noise.u_y
            (a = a, y = y)
        end,
    )
end

@testset "Discrete-time CDMs" begin
    @testset "type hierarchy" begin
        cdm = _ar_cdm()
        @test cdm isa AbstractCDM
        @test cdm isa DiscreteTimeCDM
        @test cdm.variables == [:a, :y]
    end

    @testset "DoSequence construction" begin
        seq = do_sequence(:a, [1.0, 2.0, 3.0])
        @test seq isa DoSequence
        @test seq.values[:a] isa SeriesAssignment
        @test seq.values[:a].values == [1.0, 2.0, 3.0]

        seq2 = do_sequence(:a => [0.0, 1.0], :b => 5.0)
        @test seq2.values[:a] isa SeriesAssignment
        @test seq2.values[:a].values == [0.0, 1.0]
        @test seq2.values[:b] isa ConstantAssignment
        @test seq2.values[:b].value == 5.0

        seq_scalar = do_sequence(:a, 1.0)
        @test seq_scalar.values[:a] isa ConstantAssignment
        @test seq_scalar.values[:a].value == 1.0

        seq_fn = do_sequence(:a, t -> Float64(t))
        @test seq_fn.values[:a] isa TimedAssignment
        @test seq_fn.values[:a].f isa Function
    end

    @testset "intervention_value" begin
        @test intervention_value(nothing, :a, 1, 7.0) == 7.0

        seq = do_sequence(:a => [10.0, 20.0], :b => 5.0, :c => (t -> 100.0 + t))
        @test intervention_value(seq, :a, 1, 0.0) == 10.0
        @test intervention_value(seq, :a, 2, 0.0) == 20.0
        @test intervention_value(seq, :b, 3, 0.0) == 5.0
        @test intervention_value(seq, :c, 4, 0.0) == 104.0
        @test intervention_value(seq, :z, 1, 99.0) == 99.0  # missing key

        @test_throws ArgumentError intervention_value(do_sequence(:a, [1.0]), :a, 2, 0.0)
    end

    @testset "simulate DiscreteTimeCDM (linear AR)" begin
        cdm = DiscreteTimeCDM(
            [:x, :y];
            initialise = (rng) -> (x = 1.0, y = 1.0),
            sample_noise = (rng, state, t) -> (
                u_x = randn(rng),
                u_y = 0.1 * randn(rng),
            ),
            step = (state, t, noise, intervention) -> begin
                x = 0.5 * state.x + noise.u_x
                y = x + noise.u_y
                (x = x, y = y)
            end,
        )

        traj = simulate(cdm, 5; rng = Random.Xoshiro(1))
        @test traj isa CDMTrajectory
        @test traj.T == 5
        @test length(traj.series[:x]) == 5
        @test length(traj.series[:y]) == 5
        @test length(traj.noise[:u_x]) == 5
        @test length(traj.noise[:u_y]) == 5
        @test traj.series[:x][1] == 1.0

        # Deterministic recurrence for t ≥ 2
        for t in 2:5
            @test traj.series[:x][t] ≈ 0.5 * traj.series[:x][t - 1] + traj.noise[:u_x][t]
            @test traj.series[:y][t] ≈ traj.series[:x][t] + traj.noise[:u_y][t]
        end
    end

    @testset "simulate reproducibility and T=1" begin
        cdm = _ar_cdm()
        a = simulate(cdm, 8; rng = Random.Xoshiro(11))
        b = simulate(cdm, 8; rng = Random.Xoshiro(11))
        @test a.series[:a] == b.series[:a]
        @test a.series[:y] == b.series[:y]
        @test a.noise[:u_a] == b.noise[:u_a]

        traj1 = simulate(cdm, 1; rng = Random.Xoshiro(12))
        @test traj1.T == 1
        @test length(traj1.series[:a]) == 1
        @test length(traj1.noise[:u_a]) == 1
    end

    @testset "simulate rejects invalid T" begin
        cdm = _ar_cdm()
        @test_throws ArgumentError simulate(cdm, 0)
        @test_throws ArgumentError simulate(cdm, -1)
    end

    @testset "DoSequence fixes intervened series (vector)" begin
        T = 4
        a_do = [10.0, 20.0, 30.0, 40.0]
        cdm = DiscreteTimeCDM(
            [:a, :x];
            initialise = (rng) -> (a = 0.0, x = 0.0),
            sample_noise = (rng, state, t) -> (u_a = randn(rng), u_x = randn(rng)),
            step = (state, t, noise, intervention) -> begin
                a = intervention_value(intervention, :a, t, state.a + noise.u_a)
                x = state.x + a + noise.u_x
                (a = a, x = x)
            end,
        )

        traj = simulate(cdm, T; rng = Random.Xoshiro(2), intervention = do_sequence(:a, a_do))
        @test traj.series[:a] == a_do
    end

    @testset "DoSequence scalar and function forms" begin
        cdm = _ar_cdm()
        T = 5

        traj_scalar = simulate(cdm, T; rng = Random.Xoshiro(21), intervention = do_sequence(:a, 1.5))
        @test all(traj_scalar.series[:a] .== 1.5)

        traj_fn = simulate(cdm, T; rng = Random.Xoshiro(22), intervention = do_sequence(:a, t -> Float64(t)))
        @test traj_fn.series[:a] == Float64.(1:T)
    end

    @testset "multi-variable DoSequence" begin
        cdm = DiscreteTimeCDM(
            [:a, :b, :y];
            initialise = (rng) -> (a = 0.0, b = 0.0, y = 0.0),
            sample_noise = (rng, state, t) -> (u = randn(rng),),
            step = (state, t, noise, intervention) -> begin
                a = intervention_value(intervention, :a, t, state.a + noise.u)
                b = intervention_value(intervention, :b, t, state.b + noise.u)
                y = a + b
                (a = a, b = b, y = y)
            end,
        )
        T = 3
        traj = simulate(
            cdm,
            T;
            rng = Random.Xoshiro(30),
            intervention = do_sequence(:a => ones(T), :b => fill(2.0, T)),
        )
        @test all(traj.series[:a] .== 1.0)
        @test all(traj.series[:b] .== 2.0)
        # t=1: `do` overwrites a,b on the initial state but does not re-run children
        @test traj.series[:y][1] == 0.0
        @test all(traj.series[:y][2:T] .== 3.0)
    end

    @testset "shared-U counterfactual trajectories" begin
        cdm = _ar_cdm()
        T = 6
        factual = simulate(cdm, T; rng = Random.Xoshiro(3))
        cf = counterfactual(cdm, factual.noise; intervention = do_sequence(:a, fill(1.0, T)))
        @test cf.T == T
        @test cf.noise[:u_a] == factual.noise[:u_a]
        @test cf.noise[:u_y] == factual.noise[:u_y]
        @test all(cf.series[:a] .== 1.0)
        @test cf.series[:y] != factual.series[:y]
    end

    @testset "counterfactual with factual initial" begin
        cdm = _ar_cdm()
        T = 5
        factual = simulate(cdm, T; rng = Random.Xoshiro(4))
        initial = (
            a = factual.series[:a][1],
            y = factual.series[:y][1],
        )
        cf = counterfactual(
            cdm,
            factual.noise;
            intervention = do_sequence(:a, fill(1.0, T)),
            initial = initial,
        )
        @test cf.series[:a][1] == 1.0  # do applied at t=1
        # Shared U^y ⇒ Y_t = 2·1 + U^y_t for t ≥ 2
        for t in 2:T
            @test cf.series[:y][t] ≈ 2.0 + factual.noise[:u_y][t]
        end
    end

    @testset "counterfactual noise is copied (isolation)" begin
        cdm = _ar_cdm()
        T = 4
        factual = simulate(cdm, T; rng = Random.Xoshiro(5))
        noise_copy_before = copy(factual.noise[:u_a])
        cf = counterfactual(cdm, factual.noise; intervention = do_sequence(:a, ones(T)))
        cf.noise[:u_a][1] = 999.0
        @test factual.noise[:u_a] == noise_copy_before
        @test factual.noise[:u_a][1] != 999.0
    end

    @testset "counterfactual error handling" begin
        cdm = _ar_cdm()
        @test_throws ArgumentError counterfactual(
            cdm,
            Dict{Symbol, Vector}();
            intervention = do_sequence(:a, 1.0),
        )

        bad = Dict{Symbol, Vector}(:u_a => [1.0, 2.0], :u_y => [1.0])
        @test_throws ArgumentError counterfactual(
            cdm,
            bad;
            intervention = do_sequence(:a, 1.0),
        )
    end

    @testset "short DoSequence vector errors during simulate" begin
        cdm = _ar_cdm()
        # Length-1 vector: t=1 OK via _apply_do_to_state; t=2 fails in step
        @test_throws ArgumentError simulate(
            cdm,
            3;
            rng = Random.Xoshiro(6),
            intervention = do_sequence(:a, [1.0]),
        )
    end
end
