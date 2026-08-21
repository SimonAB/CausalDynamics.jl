using CausalDynamics
using Test
using Graphs
using Random
using OrdinaryDiffEq
using Lux
using ComponentArrays
using Optimization
using OptimizationOptimisers

@testset "Lux mechanisms" begin
    @test lux_mechanisms_available()

    @testset "ODE residual + do_pin + thin train" begin
        rng = Random.Xoshiro(7)
        # True dynamics: ż = -0.1 z; ẋ = -0.2 x + 0.5 z; ẏ = -0.1 y + 0.4 x
        # Learn the Z→X residual with a tiny net (known self-dynamics only)
        spec = ContinuousCDMSpec(
            [:z, :x, :y];
            parents = Dict(:z => Symbol[], :x => [:z, :x], :y => [:x, :y]),
        )
        lib = mechanism_library_from_cdm(spec)
        attach_lux_mechanism!(
            lib, :x;
            parents = [:z],
            hidden = 4,
            kind = :ode_residual,
            rng = rng,
        )
        @test lib.mechanisms[:x].model !== nothing
        cert = mechanism_certificate(lib)
        @test cert.attached[:x]

        function known_rhs!(du, u, p, t)
            z, x, y = u
            du[1] = -0.1 * z
            du[2] = -0.2 * x          # missing +0.5 z (learned)
            du[3] = -0.1 * y + 0.4 * x
            return nothing
        end

        rhs! = build_ode_rhs(known_rhs!, spec, lib)
        u0 = [2.0, 0.5, 0.0]
        tspan = (0.0, 5.0)
        # Synthetic truth with full residual
        function true_rhs!(du, u, p, t)
            z, x, y = u
            du[1] = -0.1 * z
            du[2] = -0.2 * x + 0.5 * z
            du[3] = -0.1 * y + 0.4 * x
            return nothing
        end
        t_obs = 0.0:0.25:5.0
        sol_true = solve(ODEProblem(true_rhs!, u0, tspan), Tsit5(); saveat = t_obs)
        data = Array(sol_true)

        function loss(_ps)
            prob = ODEProblem(rhs!, u0, tspan, nothing)
            pred = solve(prob, Tsit5(); saveat = t_obs, abstol = 1e-6, reltol = 1e-6)
            try
                return sum(abs2, Array(pred) .- data)
            catch
                return 1e6
            end
        end

        before = loss(nothing)
        train_mechanisms!(lib; loss = loss, maxiters = 150, lr = 0.05)
        after = loss(nothing)
        @test after < before
        @test after < 0.5 * before || after < 2.0  # recovery progress

        # do_pin on z should still run
        sol_do = solve_cdm(
            spec, rhs!, u0, tspan, nothing;
            intervention = do_pin(:z, 1.0),
        )
        @test sol_do.u[end][spec.index[:z]] ≈ 1.0 atol = 1e-8
    end

    @testset "parent masking: wrong parent rejected at register" begin
        spec = ContinuousCDMSpec(
            [:z, :x];
            parents = Dict(:z => Symbol[], :x => [:z]),
        )
        lib = mechanism_library_from_cdm(spec)
        @test_throws ArgumentError attach_lux_mechanism!(
            lib, :x; parents = [:z, :x], hidden = 2, rng = Random.Xoshiro(1),
        )
        # :x is allowed as self-parent only if in allowed_parents — here only :z
    end

    @testset "static GraphSCM mechanism" begin
        rng = Random.Xoshiro(3)
        g = DiGraph(3)
        add_edge!(g, 1, 2)  # Z → X
        add_edge!(g, 2, 3)  # X → Y
        names = Dict(1 => :z, 2 => :x, 3 => :y)
        lib = MechanismLibrary(;
            allowed_parents = Dict(:z => Symbol[], :x => [:z], :y => [:x]),
        )
        attach_lux_mechanism!(
            lib, :y;
            parents = [:x],
            hidden = 4,
            kind = :static,
            rng = rng,
        )
        equations = Dict{Int, Function}(
            1 => (u,) -> u,
            2 => (z, u) -> z + u,
            3 => (x, u) -> 0.0,  # replaced by Lux
        )
        scm = graphscm_with_mechanisms(
            g, equations, Set{Int}(), lib; node_names = names,
        )
        U = Dict(1 => 1.0, 2 => 0.1, 3 => 0.0)
        vals = simulate_scm(scm, U)
        @test vals[3] isa Real
        @test isfinite(vals[3])
    end
end
