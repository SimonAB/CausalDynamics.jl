using Random

"""Typed CDM interventions compile to real DoSequence / Policy surgery."""

function _typed_surgery_cdm()
    return DiscreteTimeCDM(
        [:a, :y];
        initialise = rng -> (a = 0.0, y = 0.0),
        sample_noise = (rng, state, t) -> (u_a = 0.0, u_y = 0.0),
        step = (state, t, noise, intervention) -> begin
            a = intervention_value(intervention, :a, t, 0.5 * state.a + noise.u_a, state)
            y = 2a + noise.u_y
            (a = a, y = y)
        end,
    )
end

@testset "typed CDM DoSequence and Policy surgery" begin
    cdm = _typed_surgery_cdm()

    @testset "SetState is a constant DoSequence" begin
        traj = simulate(cdm, 4; rng = Random.Xoshiro(1), intervention = SetState(:a, 1.0))
        @test all(traj.series[:a] .== 1.0)
        @test all(traj.series[:y][2:4] .== 2.0)
    end

    @testset "SetState respects a time interval" begin
        traj = simulate(cdm, 4; rng = Random.Xoshiro(1),
            intervention = SetState(:a, 1.0; interval = 2:3))
        @test traj.series[:a][1] == 0.0
        @test traj.series[:a][2] == 1.0
        @test traj.series[:a][3] == 1.0
        @test traj.series[:a][4] == 0.5
    end

    @testset "Sequential SetStates are time-windowed DoSequences" begin
        intervention = Sequential(
            SetState(:a, 1.0; interval = 1:2),
            SetState(:a, 0.0; interval = 3:4),
        )
        traj = simulate(cdm, 4; rng = Random.Xoshiro(1), intervention = intervention)
        @test traj.series[:a] == [1.0, 1.0, 0.0, 0.0]
    end

    @testset "ReplacePolicy executes a named Policy rule" begin
        π = ReplacePolicy(:a, "threshold-v1"; rule = (state, t) -> state.a <= 0 ? 1.0 : -1.0)
        traj = simulate(cdm, 4; rng = Random.Xoshiro(1), intervention = π)
        @test traj.series[:a][1] == 1.0
        @test traj.series[:a][2] == -1.0
        @test traj.series[:a][3] == 1.0
    end

    @testset "apply_intervention bakes the typed node into the CDM" begin
        cdm_do = apply_intervention(cdm, SetState(:a, 1.0))
        traj = simulate(cdm_do, 3; rng = Random.Xoshiro(1))
        @test all(traj.series[:a] .== 1.0)
        @test_throws ArgumentError apply_intervention(cdm, ReplacePolicy(:a, "π-v1"))
        initial = apply_intervention(cdm, SetInitialCondition(:a, 2.0))
        @test simulate(initial, 2; rng = Random.Xoshiro(1)).series[:a][1] == 2.0
        @test_throws ArgumentError apply_intervention(cdm, ReplaceParameter(:β, "β-v1"))
    end

    @testset "DoSequence participates in the typed algebra" begin
        intervention = Sequential(do_sequence(:a, 1.0), SetState(:a, 0.0; interval = 4:4))
        traj = simulate(cdm, 4; rng = Random.Xoshiro(1), intervention = intervention)
        @test traj.series[:a][1:3] == [1.0, 1.0, 1.0]
        @test traj.series[:a][4] == 0.0
    end

    @testset "Policy participates in the typed algebra" begin
        intervention = Sequential(
            policy(:a, (state, t) -> 1.0),
            SetState(:a, 0.0; interval = 4:4),
        )
        traj = simulate(cdm, 4; rng = Random.Xoshiro(1), intervention = intervention)
        @test traj.series[:a][1:3] == [1.0, 1.0, 1.0]
        @test traj.series[:a][4] == 0.0
    end
end
