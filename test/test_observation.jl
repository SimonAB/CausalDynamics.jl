using CausalDynamics
using Test
using Random

@testset "Observation bridge and latent panels" begin
    cdm = DiscreteTimeCDM(
        [:x, :y];
        initialise = (rng) -> (x = 1.0, y = 1.0),
        sample_noise = (rng, state, t) -> (u_x = 0.1 * randn(rng), u_y = 0.1 * randn(rng)),
        step = (state, t, noise, intervention) -> begin
            x = 0.8 * state.x + noise.u_x
            y = x + noise.u_y
            (x = x, y = y)
        end,
    )

    @testset "identity observation" begin
        traj = simulate(cdm, 4; rng = Random.Xoshiro(1))
        bridge = identity_observation([:x, :y])
        obs = observe_trajectory(traj, bridge)
        @test obs[:x] == Float64.(traj.series[:x])
        @test obs[:y] == Float64.(traj.series[:y])
    end

    @testset "measurement map hides latent" begin
        traj = simulate(cdm, 5; rng = Random.Xoshiro(2))
        bridge = ObservationBridge(
            Dict(:y_obs => :y_obs);
            measure = (state, t) -> (y_obs = state.y + 0.0,),
        )
        obs = observe_trajectory(traj, bridge)
        @test collect(keys(obs)) == [:y_obs]
        @test obs[:y_obs] ≈ Float64.(traj.series[:y])
    end

    @testset "panel_from_trajectories with bridge" begin
        trajs = [simulate(cdm, 3; rng = Random.Xoshiro(10 + i)) for i in 1:5]
        bridge = ObservationBridge(
            Dict(:y => :y);
            measure = (state, t) -> (y = state.y,),
        )
        panel = panel_from_trajectories(
            trajs;
            timed = [:y],
            bridge = bridge,
        )
        @test panel.n == 5
        @test panel.T == 3
        @test :y1 in panel.column_order
        @test :y3 in panel.column_order
    end

    @testset "panel_from_latent_series" begin
        units = [
            Dict(:w => [0.0, 0.0], :a => [1.0, 2.0], :y => [0.5, 1.5]),
            Dict(:w => [1.0, 1.0], :a => [0.0, 1.0], :y => [0.2, 0.8]),
        ]
        panel = panel_from_latent_series(
            units;
            baseline = [:w],
            timed = [:a],
            terminal = [:y],
        )
        @test panel.n == 2
        @test panel.column_order == [:w, :a1, :a2, :y]
        @test panel.data[:a2] ≈ [2.0, 1.0]
    end

    @testset "simulate_observed_panel" begin
        bridge = ObservationBridge(Dict(:x => :a, :y => :y))
        panel = simulate_observed_panel(
            cdm, 8, 2;
            bridge = bridge,
            rng = Random.Xoshiro(3),
            timed = [:a],
            terminal = [:y],
        )
        @test panel.n == 8
        @test :a1 in panel.column_order
        @test :y in panel.column_order
    end
end
