using CausalDynamics
using Test
using Random

@testset "SciML extension" begin
    @test !has_sciml()

    spec = ContinuousCDMSpec([:X, :Y])
    @test spec.index[:X] == 1
    @test spec.index[:Y] == 2

    @test_throws ErrorException ode_problem_cdm(
        spec,
        (du, u, p, t) -> (du[1] = 0.0; du[2] = 0.0),
        [1.0, 2.0],
        (0.0, 1.0),
        (),
    )

    using OrdinaryDiffEq

    if !has_sciml()
        @warn "CausalDynamicsSciMLExt not loaded; skipping SciML tests"
    else
        @test has_sciml()

        @testset "Lotka–Volterra CDM" begin
            spec = ContinuousCDMSpec([:prey, :predator])
            function lotka!(du, u, p, t)
                X, Y = u
                du[1] = p.r * X - p.α * X * Y
                du[2] = p.β * X * Y - p.δ * Y
                return nothing
            end
            p = (r = 1.0, α = 0.1, β = 0.02, δ = 0.5)
            u0 = [40.0, 9.0]
            sol = solve_cdm(spec, lotka!, u0, (0.0, 10.0), p)
            term = terminal_state(spec, sol)
            @test term.prey ≈ sol.u[end][1]
            @test term.predator ≈ sol.u[end][2]
            @test term.prey > 0
            series = state_series(spec, sol)
            @test length(series.prey) == length(sol.t)
        end

        @testset "do(·) pins predator" begin
            spec = ContinuousCDMSpec([:prey, :predator])
            function lotka!(du, u, p, t)
                X, Y = u
                du[1] = p.r * X - p.α * X * Y
                du[2] = p.β * X * Y - p.δ * Y
                return nothing
            end
            p = (r = 1.0, α = 0.1, β = 0.02, δ = 0.5)
            do_pred = do_pin(:predator, 5.0)
            @test do_pred isa DoPin
            @test do_pred isa AbstractContinuousIntervention
            @test do_pred isa AbstractCausalIntervention
            sol = solve_cdm(spec, lotka!, [40.0, 9.0], (0.0, 5.0), p; intervention = do_pred)
            term = terminal_state(spec, sol)
            @test term.predator ≈ 5.0 atol = 1e-6
            # Pin must not rely on mutating u inside the RHS alone: series stays flat
            series = state_series(spec, sol)
            @test all(x -> abs(x - 5.0) < 1e-5, series.predator)
        end

        @testset "intervention hierarchy" begin
            @test DoSequence(Dict(:x => 1.0)) isa AbstractIntervention
            @test DoSequence(Dict(:x => 1.0)) isa AbstractCausalIntervention
            @test do_intervention(:x, 1.0) isa AbstractCausalIntervention
            @test !(do_pin(:x, 1.0) isa AbstractIntervention)
        end

        @testset "ContinuousCDMSpec parent sets" begin
            spec = ContinuousCDMSpec(
                [:prey, :predator];
                parents = Dict(
                    :prey => [:prey, :predator],
                    :predator => [:prey, :predator],
                ),
            )
            @test spec.parents[:prey] == [:prey, :predator]
            g = continuous_cdm_graph(spec)
            @test Graphs.nv(g) == 2
            @test Graphs.has_edge(g, 1, 2)  # prey → predator
            @test Graphs.has_edge(g, 2, 1)  # predator → prey
            spec2 = with_parents(spec, Dict(:prey => [:predator], :predator => [:prey]))
            @test spec2.parents[:prey] == [:predator]
        end

        @testset "do_ic changes initial prey" begin
            spec = ContinuousCDMSpec([:prey, :predator])
            function lotka!(du, u, p, t)
                X, Y = u
                du[1] = p.r * X - p.α * X * Y
                du[2] = p.β * X * Y - p.δ * Y
                return nothing
            end
            p = (r = 1.0, α = 0.1, β = 0.02, δ = 0.5)
            sol = solve_cdm(
                spec, lotka!, [40.0, 9.0], (0.0, 0.0), p;
                intervention = do_ic(:prey, 55.0),
            )
            @test sol.u[1][1] ≈ 55.0
        end

        @testset "forward sensitivity extension" begin
            using SciMLSensitivity
            if has_sciml_sensitivity()
                spec = ContinuousCDMSpec([:prey, :predator])
                function lotka!(du, u, p, t)
                    X, Y = u
                    du[1] = p.r * X - p.α * X * Y
                    du[2] = p.β * X * Y - p.δ * Y
                    return nothing
                end
                p = (r = 1.0, α = 0.1, β = 0.02, δ = 0.5)
                sol = forward_sensitivity_cdm(spec, lotka!, [40.0, 9.0], (0.0, 2.0), p)
                @test length(sol.u) ≥ 2
                @test sol.u[end][1] > 0
            else
                @warn "Sensitivity extension not loaded; skipping"
            end
        end

        @testset "do_force pulls toward target" begin
            spec = ContinuousCDMSpec([:x, :y])
            # Idle observational dynamics; soft force should dominate.
            function idle!(du, u, p, t)
                du[1] = 0.0
                du[2] = 0.0
                return nothing
            end
            sol = solve_cdm(
                spec, idle!, [0.0, 0.0], (0.0, 5.0), ();
                intervention = do_force(:x, 1.0; κ = 2.0),
            )
            term = terminal_state(spec, sol)
            @test term.x ≈ 1.0 atol = 1e-2
            @test term.y ≈ 0.0 atol = 1e-8
        end

        @testset "continuous g_computation functionals" begin
            spec = ContinuousCDMSpec([:x, :y])
            function drift!(du, u, p, t)
                du[1] = 0.0
                du[2] = u[1]  # ẏ = x
                return nothing
            end
            u0_sampler = rng -> [1.0, 0.0]
            fun_term = ContinuousEffectFunctional(:y; kind = :terminal)
            g_pin = g_computation(
                spec, drift!, u0_sampler, (0.0, 2.0), ();
                intervention = do_pin(:x, 1.0),
                functional = fun_term,
                n = 20,
                rng = Random.Xoshiro(11),
            )
            @test g_pin isa GComputationResult
            # With x pinned at 1, y(t)=t → terminal ≈ 2
            @test g_pin.mean ≈ 2.0 atol = 1e-2

            sol = solve_cdm(spec, drift!, [1.0, 0.0], (0.0, 2.0), (); intervention = do_pin(:x, 1.0))
            @test evaluate_functional(spec, sol, ContinuousEffectFunctional(:y; kind = :mean)) > 0
            @test evaluate_functional(spec, sol, ContinuousEffectFunctional(:y; kind = :integral)) ≈ 2.0 atol = 0.1

            g_out = g_computation(
                spec, drift!, u0_sampler, (0.0, 1.0), ();
                intervention = do_pin(:x, 0.5),
                outcome = :y,
                n = 10,
                rng = Random.Xoshiro(12),
            )
            @test g_out.mean ≈ 0.5 atol = 5e-2
        end
    end
end
