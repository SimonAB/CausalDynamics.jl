using CausalDynamics
using Graphs
using Test

@testset "Time-indexed graphs" begin
    @testset "unroll confounded CDM (Ch. 28 pattern)" begin
        # C_{t-1} → C_t, A_{t-1} → C_t, C_t → A_t (confounding),
        # X_{t-1} → X_t, A_{t-1} → X_t, C_{t-1} → X_t, X_t → Y_t
        spec = TemporalDAGSpec(
            [:x, :y, :a, :c],
            [
                (:c, :c, 1),
                (:a, :c, 1),
                (:c, :a, 0),
                (:x, :x, 1),
                (:a, :x, 1),
                (:c, :x, 1),
                (:x, :y, 0),
            ],
        )
        T = 4
        u = unroll_temporal_dag(spec, T)
        @test u isa TemporalUnrolling
        @test nv(u.graph) == 4 * T
        @test is_dag(u.graph)

        # Effect of A_{t-1} on X_t (treatment at t=1, outcome at t=2):
        # backdoor a[1] ← c[1] → x[2], so adjust for C_{t-1}
        adj = temporal_backdoor_adjustment_set(u, :a, 1, :x, 2)
        @test adj !== nothing
        @test temporal_node(u, :c, 1) in adj

        adj_nodes = temporal_backdoor_adjustment_nodes(u, :a, 1, :x, 2)
        @test (:c, 1) in adj_nodes

        # Contemporaneous A_t has no directed path to X_t; the confounder is C_t
        adj_same = temporal_backdoor_adjustment_nodes(u, :a, 2, :x, 2)
        @test (:c, 2) in adj_same
    end

    @testset "d_separated_temporal" begin
        # Fork only: Z_t → X_t, Z_t → Y_t (no direct X → Y edge)
        spec = TemporalDAGSpec([:z, :x, :y], [(:z, :x, 0), (:z, :y, 0)])
        u = unroll_temporal_dag(spec, 3)
        @test d_separated_temporal(u, :x, 2, :y, 2, [(:z, 2)])
        @test !d_separated_temporal(u, :x, 2, :y, 2, Tuple{Symbol, Int}[])
        # Different occasions are unconnected in this spec
        @test d_separated_temporal(u, :x, 1, :y, 2, Tuple{Symbol, Int}[])
    end

    @testset "temporal_node_label" begin
        spec = TemporalDAGSpec([:x], [LaggedEdge(:x, :x, 1)])
        u = unroll_temporal_dag(spec, 2)
        @test temporal_node_label(u, 1) == "x[1]"
        @test temporal_node_label(u, 2) == "x[2]"
        @test temporal_node(u, :x, 2) == 2
        @test_throws ArgumentError temporal_node(u, :x, 3)
    end

    @testset "spec accepts tuples, LaggedEdge, and empty edges" begin
        @test length(TemporalDAGSpec([:x], [(:x, :x, 1)]).edges) == 1
        @test length(TemporalDAGSpec([:x], [LaggedEdge(:x, :x, 1)]).edges) == 1
        @test isempty(TemporalDAGSpec([:x], []).edges)
        @test_throws ArgumentError TemporalDAGSpec([:x], ["not an edge"])
    end

    @testset "validation errors" begin
        @test_throws ArgumentError unroll_temporal_dag(
            TemporalDAGSpec([:x], [(:y, :x, 0)]),
            2,
        )
        @test_throws ArgumentError unroll_temporal_dag(
            TemporalDAGSpec([:x], [(:x, :x, -1)]),
            2,
        )
        @test_throws ArgumentError unroll_temporal_dag(TemporalDAGSpec([:x], []), 0)
    end
end
