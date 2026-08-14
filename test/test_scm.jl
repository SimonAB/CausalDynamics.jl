using CausalDynamics
using Graphs
using Random
using Test

@testset "SCM Framework" begin
    @testset "SCM Types" begin
        # Test GraphSCM creation
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)

        equations = Dict{Int, Function}(
            1 => (u) -> u,
            2 => (x1, u) -> x1 + u,
            3 => (x2, u) -> x2 + u
        )
        exogenous = Set([1])

        scm = GraphSCM(g, equations, exogenous)
        @test scm.graph == g
        @test scm.equations == equations
        @test scm.exogenous == exogenous

        # Test SymbolicSCM (basic structure check)
        # Note: Full symbolic SCM testing requires ModelingToolkit setup
        @test SymbolicSCM isa Type
    end

    @testset "Interventions" begin
        # Test DoIntervention creation
        intervention = do_intervention(:x, 1.0)
        @test intervention.variable == :x
        @test intervention.value == 1.0

        # Test with integer variable
        intervention_int = do_intervention(2, 5)
        @test intervention_int.variable == 2
        @test intervention_int.value == 5

        # Test DoIntervention struct
        intervention_struct = DoIntervention(:y, 2.5)
        @test intervention_struct.variable == :y
        @test intervention_struct.value == 2.5
    end

    @testset "Counterfactuals" begin
        # Create a simple SCM: Z(1) → X(2) → Y(3)
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)

        equations = Dict{Int, Function}(
            1 => (u) -> u,
            2 => (z, u) -> z + u,
            3 => (x, u) -> 2x + u
        )
        exogenous = Set{Int}()
        scm = GraphSCM(g, equations, exogenous)

        intervention = do_intervention(2, 10.0)

        # Function should exist
        @test hasmethod(counterfactual_graph, (GraphSCM, DoIntervention))

        # counterfactual_graph should return a valid GraphSCM
        scm_cf = counterfactual_graph(scm, intervention)
        @test scm_cf isa GraphSCM

        # Edge from 1 → 2 should be removed in counterfactual
        @test !Graphs.has_edge(scm_cf.graph, 1, 2)
        # Edge from 2 → 3 should remain
        @test Graphs.has_edge(scm_cf.graph, 2, 3)

        # Full counterfactual computation
        U = Dict(1 => 1.0, 2 => 0.5, 3 => -0.3)
        result = compute_counterfactual(scm, intervention, U)

        # Factual: Z=1.0, X=1.0+0.5=1.5, Y=2*1.5+(-0.3)=2.7
        @test result.factual[1] ≈ 1.0
        @test result.factual[2] ≈ 1.5
        @test result.factual[3] ≈ 2.7

        # Counterfactual: Z=1.0, X=10.0 (intervened), Y=2*10.0+(-0.3)=19.7
        @test result.counterfactual[1] ≈ 1.0
        @test result.counterfactual[2] ≈ 10.0
        @test result.counterfactual[3] ≈ 19.7
    end

    @testset "Edge Cases" begin
        # Test empty SCM
        g_empty = DiGraph(0)
        equations_empty = Dict{Int, Function}()
        exogenous_empty = Set{Int}()
        scm_empty = GraphSCM(g_empty, equations_empty, exogenous_empty)
        @test scm_empty.graph == g_empty

        # Test SCM with single node
        g_single = DiGraph(1)
        equations_single = Dict(1 => (u) -> u)
        exogenous_single = Set([1])
        scm_single = GraphSCM(g_single, equations_single, exogenous_single)
        @test scm_single.graph == g_single
    end

    @testset "apply_intervention" begin
        # Test apply_intervention function exists
        @test isdefined(CausalDynamics, :apply_intervention)

        # Create a simple SCM: Z(1) → X(2) → Y(3)
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)

        equations = Dict{Int, Function}(
            1 => (u) -> u,
            2 => (z, u) -> z + u,
            3 => (x, u) -> x + u
        )
        exogenous = Set{Int}()
        scm = GraphSCM(g, equations, exogenous)

        # Apply intervention do(X = 5.0)
        intervention = do_intervention(2, 5.0)
        scm_do = apply_intervention(scm, intervention)

        # Check the mutilated graph
        @test scm_do isa GraphSCM
        @test !Graphs.has_edge(scm_do.graph, 1, 2)  # Z → X removed
        @test Graphs.has_edge(scm_do.graph, 2, 3)    # X → Y still present

        # Simulate the intervened SCM
        U = Dict(1 => 2.0, 2 => 0.5, 3 => -1.0)
        vals = simulate_scm(scm_do, U)
        @test vals[1] ≈ 2.0       # Z = U_Z = 2.0
        @test vals[2] ≈ 5.0       # X = 5.0 (intervened, ignoring parent Z and noise)
        @test vals[3] ≈ 4.0       # Y = X + U_Y = 5.0 + (-1.0) = 4.0

        # Original SCM should be unmodified
        @test Graphs.has_edge(scm.graph, 1, 2)

        # Test multiple interventions
        intv_vec = [do_intervention(1, 0.0), do_intervention(2, 3.0)]
        scm_multi = apply_intervention(scm, intv_vec)
        @test !Graphs.has_edge(scm_multi.graph, 1, 2)
        vals_multi = simulate_scm(scm_multi, U)
        @test vals_multi[1] ≈ 0.0
        @test vals_multi[2] ≈ 3.0
        @test vals_multi[3] ≈ 2.0  # 3.0 + (-1.0)

        # Test invalid node index
        @test_throws ArgumentError apply_intervention(scm, do_intervention(99, 1.0))

        # Symbol variables are not yet resolved on GraphSCM
        @test_throws ArgumentError apply_intervention(scm, do_intervention(:x, 1.0))
    end

    @testset "Confounding triangle parent order" begin
        # Z(1) → X(2), Z(1) → Y(3), X(2) → Y(3); structural slope on X→Y is 2
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 1, 3)
        add_edge!(g, 2, 3)
        equations = Dict{Int, Function}(
            1 => (u,) -> u,
            2 => (z, u) -> z + u,
            3 => (z, x, u) -> 2x + z + u,
        )
        scm = GraphSCM(g, equations, Set{Int}())

        rng = Random.MersenneTwister(71)
        n = 400
        Z = Float64[]
        X = Float64[]
        Y = Float64[]
        for _ in 1:n
            U = Dict(1 => randn(rng), 2 => 0.4 * randn(rng), 3 => 0.3 * randn(rng))
            v = simulate_scm(scm, U)
            push!(Z, v[1])
            push!(X, v[2])
            push!(Y, v[3])
        end
        # OLS Y ~ X + Z should recover slope on X ≈ 2
        Xmat = hcat(ones(n), X, Z)
        β = Xmat \ Y
        @test β[2] ≈ 2.0 atol = 0.15

        U0 = Dict(1 => 0.2, 2 => 0.1, 3 => -0.05)
        v_fact = simulate_scm(scm, U0)
        x_fact = v_fact[2]
        y_fact = v_fact[3]
        y_do = simulate_scm(apply_intervention(scm, do_intervention(2, 1.5)), U0)[3]
        @test y_do - y_fact ≈ 2.0 * (1.5 - x_fact) atol = 1e-10
    end

    @testset "create_symbolic_scm (unexported placeholder)" begin
        @test isdefined(CausalDynamics, :create_symbolic_scm)
        @test !(:create_symbolic_scm in names(CausalDynamics))
        @test hasmethod(CausalDynamics.create_symbolic_scm, (DiGraph, Dict))

        g = DiGraph(2)
        add_edge!(g, 1, 2)
        equations = Dict(1 => :x, 2 => :y)

        @test_throws ErrorException CausalDynamics.create_symbolic_scm(g, equations)
    end
end
