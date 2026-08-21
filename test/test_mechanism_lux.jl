using CausalDynamics
using Test
using Graphs
using Random
using OrdinaryDiffEq
using Lux
using ComponentArrays
using Optimization
using OptimizationOptimisers
using LinearAlgebra

@testset "Lux mechanisms" begin
    @test lux_mechanisms_available()

    @testset "attach_lux_mechanism! units" begin
        rng = Random.Xoshiro(1)
        lib = MechanismLibrary(;
            allowed_parents = Dict(:z => Symbol[], :x => [:z], :y => [:x, :z]),
        )

        @testset "happy path and certificate attached" begin
            attach_lux_mechanism!(lib, :x; parents = [:z], hidden = 3, rng = rng)
            m = lib.mechanisms[:x]
            @test m.model !== nothing
            @test m.parameters !== nothing
            @test m.states !== nothing
            @test m.output_dim == 1
            @test mechanism_certificate(lib).attached[:x]
        end

        @testset "empty parents rejected" begin
            @test_throws ArgumentError attach_lux_mechanism!(
                lib, :z; parents = Symbol[], hidden = 2, rng = rng,
            )
        end

        @testset "wrong parent rejected" begin
            @test_throws ArgumentError attach_lux_mechanism!(
                lib, :x; parents = [:z, :x], hidden = 2, rng = Random.Xoshiro(2),
            )
        end

        @testset "output_dim > 1" begin
            attach_lux_mechanism!(
                lib, :y;
                parents = [:x],
                hidden = 4,
                kind = :generative,
                output_dim = 3,
                rng = Random.Xoshiro(3),
            )
            @test lib.mechanisms[:y].output_dim == 3
            @test size(lib.mechanisms[:y].parameters.layer_2.weight, 1) == 3
        end

        @testset "deterministic seed" begin
            lib_a = MechanismLibrary(; allowed_parents = Dict(:x => [:z], :z => Symbol[]))
            lib_b = MechanismLibrary(; allowed_parents = Dict(:x => [:z], :z => Symbol[]))
            attach_lux_mechanism!(lib_a, :x; parents = [:z], hidden = 2, rng = Random.Xoshiro(99))
            attach_lux_mechanism!(lib_b, :x; parents = [:z], hidden = 2, rng = Random.Xoshiro(99))
            @test Array(lib_a.mechanisms[:x].parameters) == Array(lib_b.mechanisms[:x].parameters)
        end
    end

    @testset "ODE residual + do_pin + thin train" begin
        rng = Random.Xoshiro(7)
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

        function known_rhs!(du, u, p, t)
            z, x, y = u
            du[1] = -0.1 * z
            du[2] = -0.2 * x
            du[3] = -0.1 * y + 0.4 * x
            return nothing
        end
        rhs! = build_ode_rhs(known_rhs!, spec, lib)
        u0 = [2.0, 0.5, 0.0]
        tspan = (0.0, 5.0)

        function true_rhs!(du, u, p, t)
            z, x, y = u
            du[1] = -0.1 * z
            du[2] = -0.2 * x + 0.5 * z
            du[3] = -0.1 * y + 0.4 * x
            return nothing
        end
        t_obs = 0.0:0.25:5.0
        data = Array(solve(ODEProblem(true_rhs!, u0, tspan), Tsit5(); saveat = t_obs))

        function loss(_ps)
            pred = solve(
                ODEProblem(rhs!, u0, tspan, nothing), Tsit5();
                saveat = t_obs, abstol = 1e-6, reltol = 1e-6,
            )
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
        @test after < 0.5 * before || after < 2.0

        sol_do = solve_cdm(
            spec, rhs!, u0, tspan, nothing;
            intervention = do_pin(:z, 1.0),
        )
        @test sol_do.u[end][spec.index[:z]] ≈ 1.0 atol = 1e-8

        # residual RHS is finite on a grid of states
        du = zeros(3)
        for z in (-1.0, 0.0, 2.0), x in (-0.5, 1.0)
            rhs!(du, [z, x, 0.0], nothing, 0.0)
            @test all(isfinite, du)
        end
    end

    @testset "build_ode_rhs edge cases" begin
        spec = ContinuousCDMSpec(
            [:z, :x];
            parents = Dict(:z => Symbol[], :x => [:z]),
        )
        lib = mechanism_library_from_cdm(spec)
        attach_lux_mechanism!(
            lib, :x; parents = [:z], kind = :ode_residual, rng = Random.Xoshiro(4),
        )
        known! = (du, u, p, t) -> (du .= 0.0; nothing)
        rhs! = build_ode_rhs(known!, spec, lib)
        du = zeros(2)
        rhs!(du, [1.0, 0.0], nothing, 0.0)
        @test isfinite(du[2])

        # static / generative mechanisms are ignored by build_ode_rhs
        lib2 = mechanism_library_from_cdm(spec)
        attach_lux_mechanism!(
            lib2, :x; parents = [:z], kind = :static, rng = Random.Xoshiro(5),
        )
        rhs_static! = build_ode_rhs(known!, spec, lib2)
        fill!(du, NaN)
        rhs_static!(du, [1.0, 2.0], nothing, 0.0)
        @test du == [0.0, 0.0]

        # node missing from ContinuousCDMSpec
        lib3 = MechanismLibrary(;
            allowed_parents = Dict(:w => [:z], :z => Symbol[], :x => [:z]),
        )
        attach_lux_mechanism!(
            lib3, :w; parents = [:z], kind = :ode_residual, rng = Random.Xoshiro(6),
        )
        @test_throws ArgumentError build_ode_rhs(known!, spec, lib3)
    end

    @testset "train_mechanisms! edges" begin
        lib = MechanismLibrary()
        @test_throws ArgumentError train_mechanisms!(lib; loss = _ -> 0.0)

        lib2 = MechanismLibrary(; allowed_parents = Dict(:x => [:z], :z => Symbol[]))
        register_mechanism!(lib2, MechanismSpec(:x, [:z]; kind = :static))
        @test_throws ArgumentError train_mechanisms!(lib2; loss = _ -> 0.0)
    end

    @testset "static GraphSCM mechanism" begin
        rng = Random.Xoshiro(3)
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)
        names = Dict(1 => :z, 2 => :x, 3 => :y)
        lib = MechanismLibrary(;
            allowed_parents = Dict(:z => Symbol[], :x => [:z], :y => [:x]),
        )
        attach_lux_mechanism!(
            lib, :y; parents = [:x], hidden = 4, kind = :static, rng = rng,
        )
        equations = Dict{Int, Function}(
            1 => (u,) -> u,
            2 => (z, u) -> z + u,
            3 => (x, u) -> 0.0,
        )
        scm = graphscm_with_mechanisms(
            g, equations, Set{Int}(), lib; node_names = names,
        )
        vals = simulate_scm(scm, Dict(1 => 1.0, 2 => 0.1, 3 => 0.0))
        @test vals[3] isa Real && isfinite(vals[3])

        # Symbol => Int node_names
        scm2 = graphscm_with_mechanisms(
            g, equations, Set{Int}(), lib;
            node_names = Dict(:z => 1, :x => 2, :y => 3),
        )
        @test isfinite(simulate_scm(scm2, Dict(1 => 0.5, 2 => 0.0, 3 => 0.0))[3])

        # parent set mismatch
        lib_bad = MechanismLibrary(;
            allowed_parents = Dict(:z => Symbol[], :x => [:z], :y => [:x, :z]),
        )
        # Force a mechanism whose parents ≠ graph parents of Y (only X)
        attach_lux_mechanism!(
            lib_bad, :y; parents = [:x, :z], kind = :static, rng = rng,
        )
        @test_throws ArgumentError graphscm_with_mechanisms(
            g, equations, Set{Int}(), lib_bad; node_names = names,
        )
    end

    @testset "generative L3 abduction (scalar)" begin
        rng = Random.Xoshiro(9)
        lib = MechanismLibrary(;
            allowed_parents = Dict(:x => Symbol[], :y => [:x]),
        )
        attach_lux_mechanism!(
            lib, :y; parents = [:x], hidden = 8, kind = :generative, rng = rng,
        )
        spec = lib.mechanisms[:y]
        xs = range(-1.5, 1.5; length = 40)

        loss = function (_ps)
            s = 0.0
            for x in xs
                s += abs2(generate_from_noise(spec, 0.0, [x]) - 2x)
            end
            return s / length(xs)
        end
        train_mechanisms!(lib; loss = loss, maxiters = 250, lr = 0.05)
        spec = lib.mechanisms[:y]

        x_f, u_true = 1.0, -0.3
        y_f = 2x_f + u_true
        z = abduce_noise(spec, y_f, [x_f])
        @test z ≈ u_true atol = 0.15
        y_cf = mechanism_counterfactual(spec, y_f, [x_f], [0.0])
        @test y_cf ≈ u_true atol = 0.2

        # round-trip: generate then abduce
        for x in (-1.0, 0.0, 1.2), u in (-0.5, 0.0, 0.4)
            y = generate_from_noise(spec, u, [x])
            @test abduce_noise(spec, y, [x]) ≈ u atol = 1e-10
        end

        g = DiGraph(2)
        add_edge!(g, 1, 2)
        names = Dict(1 => :x, 2 => :y)
        equations = Dict{Int, Function}(1 => (u,) -> u, 2 => (x, u) -> 0.0)
        scm = graphscm_with_mechanisms(
            g, equations, Set{Int}(), lib; node_names = names,
        )
        U = Dict(1 => 1.0, 2 => z)
        fact = simulate_scm(scm, U)
        cf = simulate_scm(counterfactual_graph(scm, do_intervention(1, 0.0)), U)
        @test fact[2] ≈ y_f atol = 0.25
        @test cf[2] ≈ y_cf atol = 0.25
    end

    @testset "generative multi-dim codes (output_dim=3)" begin
        rng = Random.Xoshiro(12)
        lib = MechanismLibrary(;
            allowed_parents = Dict(:x => Symbol[], :y => [:x]),
        )
        attach_lux_mechanism!(
            lib, :y;
            parents = [:x],
            hidden = 6,
            kind = :generative,
            output_dim = 3,
            rng = rng,
        )
        spec = lib.mechanisms[:y]
        # Supervise f(x) ≈ [x, 2x, -x]
        xs = range(-1.0, 1.0; length = 30)
        loss = function (_ps)
            s = 0.0
            for x in xs
                ŷ = generate_from_noise(spec, zeros(3), [x])
                s += sum(abs2, ŷ .- [x, 2x, -x])
            end
            return s / length(xs)
        end
        before = loss(nothing)
        train_mechanisms!(lib; loss = loss, maxiters = 300, lr = 0.05)
        @test loss(nothing) < before

        x_f = 0.8
        u = [0.1, -0.2, 0.05]
        y_f = generate_from_noise(spec, u, [x_f])
        @test abduce_noise(spec, y_f, [x_f]) ≈ u atol = 1e-10
        y_cf = mechanism_counterfactual(spec, y_f, [x_f], [0.0])
        @test length(y_cf) == 3
        @test y_cf ≈ generate_from_noise(spec, u, [0.0]) atol = 1e-10

        @test_throws ArgumentError abduce_noise(spec, [1.0, 2.0], [x_f])  # wrong x dim
        @test_throws ArgumentError generate_from_noise(spec, [1.0], [x_f])
        @test_throws ArgumentError abduce_noise(spec, y_f, [1.0, 2.0])  # wrong pa dim
    end

    @testset "abduce / generate kind guards" begin
        lib = MechanismLibrary(;
            allowed_parents = Dict(:x => [:z], :z => Symbol[]),
        )
        attach_lux_mechanism!(
            lib, :x; parents = [:z], kind = :static, rng = Random.Xoshiro(8),
        )
        m = lib.mechanisms[:x]
        @test_throws ArgumentError abduce_noise(m, 1.0, [0.0])
        @test_throws ArgumentError generate_from_noise(m, 0.0, [0.0])
        @test_throws ArgumentError mechanism_counterfactual(m, 1.0, [0.0], [1.0])
    end

    @testset "multi-node library train" begin
        rng = Random.Xoshiro(15)
        lib = MechanismLibrary(;
            allowed_parents = Dict(
                :z => Symbol[],
                :x => [:z],
                :y => [:x],
            ),
        )
        attach_lux_mechanism!(lib, :x; parents = [:z], kind = :generative, rng = rng)
        attach_lux_mechanism!(
            lib, :y; parents = [:x], kind = :generative, rng = Random.Xoshiro(16),
        )
        # Fit f_x(z)=z, f_y(x)=2x
        zs = range(-1.0, 1.0; length = 25)
        loss = function (_ps)
            s = 0.0
            for z in zs
                x̂ = generate_from_noise(lib.mechanisms[:x], 0.0, [z])
                s += abs2(x̂ - z)
                ŷ = generate_from_noise(lib.mechanisms[:y], 0.0, [x̂])
                s += abs2(ŷ - 2z)
            end
            return s / length(zs)
        end
        before = loss(nothing)
        train_mechanisms!(lib; loss = loss, maxiters = 200, lr = 0.05)
        @test loss(nothing) < before
        @test mechanism_certificate(lib).n_mechanisms == 2
        @test all(values(mechanism_certificate(lib).attached))
    end

    @testset "stress: many generative round-trips" begin
        rng = Random.Xoshiro(21)
        lib = MechanismLibrary(;
            allowed_parents = Dict(:x => Symbol[], :y => [:x]),
        )
        attach_lux_mechanism!(
            lib, :y;
            parents = [:x],
            hidden = 4,
            kind = :generative,
            output_dim = 2,
            rng = rng,
        )
        spec = lib.mechanisms[:y]
        n = 200
        max_err = 0.0
        for _ in 1:n
            x = randn(rng)
            u = randn(rng, 2)
            y = generate_from_noise(spec, u, [x])
            max_err = max(max_err, norm(abduce_noise(spec, y, [x]) .- u))
            y2 = mechanism_counterfactual(spec, y, [x], [x + 0.5])
            @test y2 ≈ generate_from_noise(spec, u, [x + 0.5]) atol = 1e-10
        end
        @test max_err < 1e-9
    end

    @testset "Phase 1 codes → generative L3 hand-off" begin
        rng = Random.Xoshiro(33)
        n, p, d = 40, 6, 2
        X = randn(rng, n, p)
        B = randn(rng, p, d)
        spec_rep = RepresentationSpec(:S, [:z1, :z2], S -> S * B)
        panel = encode_to_panel(X, spec_rep)
        # Structural: Y = 1.5 z1 - 0.5 z2 + U (use z1 as treatment-like parent of y)
        lib = MechanismLibrary(;
            allowed_parents = Dict(:z1 => Symbol[], :y => [:z1]),
        )
        attach_lux_mechanism!(
            lib, :y; parents = [:z1], kind = :generative, hidden = 6, rng = rng,
        )
        m = lib.mechanisms[:y]
        loss = function (_ps)
            s = 0.0
            for i in 1:n
                s += abs2(
                    generate_from_noise(m, 0.0, [panel[:z1][i]]) -
                    (1.5 * panel[:z1][i]),
                )
            end
            return s / n
        end
        train_mechanisms!(lib; loss = loss, maxiters = 200, lr = 0.05)
        i = 1
        u = -0.25
        y_f = 1.5 * panel[:z1][i] + u
        y_cf = mechanism_counterfactual(m, y_f, [panel[:z1][i]], [0.0])
        @test y_cf ≈ u atol = 0.35
    end
end
