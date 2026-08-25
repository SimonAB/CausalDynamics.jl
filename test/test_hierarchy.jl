using CausalDynamics
using Test
using Random
using Statistics
using Graphs
using CausalDynamics: TotalEffectQuery, identify

@testset "hierarchical nested exogenous" begin
    @testset "RandomEffectSpec validation" begin
        spec = RandomEffectSpec(; n_clusters = 5, σ_cluster = 1.2, outcome_vars = [:y])
        @test spec.n_clusters == 5
        @test spec.cluster_col === :cluster
        @test HIERARCHY_ASSUMPTIONS == (:nested_exogenous, :no_interference_across_clusters)
        @test_throws ArgumentError RandomEffectSpec(; n_clusters = 0)
        @test_throws ArgumentError RandomEffectSpec(; n_clusters = 2, σ_cluster = -1.0)
        @test_throws ArgumentError RandomEffectSpec(; n_clusters = 2, outcome_vars = Symbol[])
    end

    @testset "assign_cluster_ids" begin
        rng = Random.Xoshiro(1)
        ids = assign_cluster_ids(20, 5; rng = rng)
        @test length(ids) == 20
        @test sort(unique(ids)) == Float64.(1:5)
        @test_throws ArgumentError assign_cluster_ids(3, 5)
    end

    @testset "draw_nested_effects shared within cluster" begin
        rng = Random.Xoshiro(2)
        cluster = Float64[1, 1, 2, 2, 3, 3]
        spec = RandomEffectSpec(; n_clusters = 3, σ_cluster = 2.0, σ_unit = 0.0)
        eff = draw_nested_effects(cluster, spec; rng = rng)
        @test eff.u_cluster[1] == eff.u_cluster[2]
        @test eff.u_cluster[3] == eff.u_cluster[4]
        @test eff.u_cluster[1] != eff.u_cluster[3] || eff.u_cluster[3] != eff.u_cluster[5]
        @test all(iszero, eff.u_unit)
    end

    @testset "simulate_hierarchical_intercept_ate" begin
        cols, truth = simulate_hierarchical_intercept_ate(
            400; n_clusters = 20, σ_cluster = 1.5, β_a = 0.7, σ_y = 0.3,
            rng = Random.Xoshiro(3),
        )
        @test truth.ate == 0.7
        @test truth.n_clusters == 20
        @test Set(truth.assumptions) == Set(collect(HIERARCHY_ASSUMPTIONS))
        @test length(unique(cols[:cluster])) == 20
        @test length(cols[:Y]) == 400

        # Within-cluster residual correlation after residualising A and W
        Y_res = cols[:Y] .- truth.ate .* cols[:A] .- truth.β_w .* cols[:W]
        # Pairwise same-cluster product mean should be positive and larger than
        # a zero-cluster baseline (σ_cluster = 0).
        function mean_within_product(y, c)
            s = 0.0
            n_pairs = 0
            for i in 1:length(y), j in (i + 1):length(y)
                if c[i] == c[j]
                    s += y[i] * y[j]
                    n_pairs += 1
                end
            end
            return n_pairs == 0 ? 0.0 : s / n_pairs
        end
        ρ_hi = mean_within_product(Y_res, cols[:cluster])
        cols0, _ = simulate_hierarchical_intercept_ate(
            400; n_clusters = 20, σ_cluster = 0.0, β_a = 0.7, σ_y = 0.3,
            rng = Random.Xoshiro(3),
        )
        Y0 = cols0[:Y] .- 0.7 .* cols0[:A] .- 1.0 .* cols0[:W]
        ρ_lo = mean_within_product(Y0, cols0[:cluster])
        @test ρ_hi > ρ_lo + 0.5
    end

    @testset "simulate_hierarchical_panel" begin
        cdm = DiscreteTimeCDM(
            [:a, :y];
            initialise = (rng) -> (a = 0.0, y = 0.0),
            sample_noise = (rng, state, t) -> (u_a = 0.1 * randn(rng), u_y = 0.1 * randn(rng)),
            step = (state, t, noise, intervention) -> begin
                a = intervention_value(intervention, :a, t, 0.5 * state.a + noise.u_a)
                y = 2a + noise.u_y
                (a = a, y = y)
            end,
        )
        hier = RandomEffectSpec(;
            n_clusters = 8,
            σ_cluster = 1.0,
            σ_unit = 0.1,
            outcome_vars = [:y],
        )
        panel = simulate_hierarchical_panel(
            cdm, 40, 3;
            hierarchy = hier,
            baseline = [:a],
            terminal = [:y],
            rng = Random.Xoshiro(4),
        )
        @test panel.n == 40
        @test haskey(panel.data, :cluster)
        @test :cluster in panel.column_order
        @test length(unique(panel.data[:cluster])) == 8
        # Cluster effect moved the terminal outcome away from near-zero noise only
        @test std(panel.data[:y]) > 0.5
    end

    @testset "unroll_hierarchical_dag" begin
        spec = HierarchicalNestingSpec(
            [:W, :A, :Y],
            [(:W, :A), (:W, :Y), (:A, :Y)];
            cluster_variable = :U,
            affects = [:Y],
        )
        un = unroll_hierarchical_dag(spec, 4; n_clusters = 2)
        @test un.n_units == 4
        @test un.n_clusters == 2
        @test Graphs.nv(un.graph) == 2 + 4 * 3  # clusters + unit copies
        # Cluster 1 → Y of units assigned to cluster 1
        u1 = hierarchical_node(un, (:unit, 1, :Y))
        c_of_1 = un.cluster_of_unit[1]
        cnode = hierarchical_node(un, (:cluster, c_of_1))
        @test Graphs.has_edge(un.graph, cnode, u1)
        @test Graphs.has_edge(
            un.graph,
            hierarchical_node(un, (:unit, 1, :A)),
            hierarchical_node(un, (:unit, 1, :Y)),
        )
        @test !Graphs.has_edge(
            un.graph,
            hierarchical_node(un, (:unit, 1, :A)),
            hierarchical_node(un, (:unit, 2, :Y)),
        )
        names = hierarchical_node_names(un)
        @test names[hierarchical_node(un, (:cluster, 1))] === :U_c1

        # identify A_u1 → Y_u1 with W_u1 in adjustment; attach hierarchy assumptions
        g = un.graph
        A = hierarchical_node(un, (:unit, 1, :A))
        Y = hierarchical_node(un, (:unit, 1, :Y))
        W = hierarchical_node(un, (:unit, 1, :W))
        id = identify(g, TotalEffectQuery(A, Y))
        id_h = attach_hierarchy_assumptions(id)
        @test :nested_exogenous in id_h.assumptions
        @test :no_interference_across_clusters in id_h.assumptions
        id_h2 = attach_hierarchy_assumptions(id_h)
        @test count(==(:nested_exogenous), id_h2.assumptions) == 1
    end
end
