using CausalDynamics
using Test

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
            do_pred = do_intervention(:predator, 5.0)
            sol = solve_cdm(spec, lotka!, [40.0, 9.0], (0.0, 5.0), p; intervention = do_pred)
            term = terminal_state(spec, sol)
            @test term.predator ≈ 5.0 atol = 1e-6
        end
    end
end
