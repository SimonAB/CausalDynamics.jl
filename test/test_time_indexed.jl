using CausalDynamics
using Graphs
using Test

@testset "Time-indexed graphs" begin
    @testset "unroll confounded CDM (Ch. 28 pattern)" begin
        # C_{t-1} → C_t, A_{t-1} → C_t, C_t → A_t (confounding),
        # X_{t-1} → X_t, A_{t-1} → X_t, C_{t-1} → X_t, X_t → Y_t
        spec = TemporalDAGSpec(
            nodes = [TemporalNodeSpec(v) for v in [:x, :y, :a, :c]],
            edges = [
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
        @test nv(u.graph) == 4 * (T + 1)
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
        spec = TemporalDAGSpec(
            nodes = [TemporalNodeSpec(v) for v in [:z, :x, :y]],
            edges = [(:z, :x, 0), (:z, :y, 0)],
        )
        u = unroll_temporal_dag(spec, 3)
        @test d_separated_temporal(u, :x, 2, :y, 2, [(:z, 2)])
        @test !d_separated_temporal(u, :x, 2, :y, 2, Tuple{Symbol, Int}[])
        # Different occasions are unconnected in this spec
        @test d_separated_temporal(u, :x, 1, :y, 2, Tuple{Symbol, Int}[])
    end

    @testset "temporal_node_label" begin
        spec = TemporalDAGSpec(nodes = [TemporalNodeSpec(:x)], edges = [LaggedEdge(:x, :x, 1)])
        u = unroll_temporal_dag(spec, 2)
        @test temporal_node_label(u, temporal_node(u, :x, 0)) == "x[0]"
        @test temporal_node_label(u, temporal_node(u, :x, 1)) == "x[1]"
        @test temporal_node_label(u, temporal_node(u, :x, 2)) == "x[2]"
        @test_throws ArgumentError temporal_node(u, :x, 3)
    end

    @testset "enduring attributes and baseline assignment" begin
        spec = TemporalDAGSpec(
            entity = :sheep,
            nodes = [
                TemporalNodeSpec(:diagnosis; value_representation = :state),
                TemporalNodeSpec(
                    :pasture;
                    temporal_support = FromOnsetSupport(1),
                    value_representation = :attribute,
                    causal_role = :assigned,
                    referent_id = :sheep,
                    identity_criterion = :administrative_identifier,
                    ontological_character = :enduring,
                ),
                TemporalNodeSpec(
                    :weight;
                    value_representation = :state,
                    referent_id = :sheep,
                    identity_criterion = :organisational_continuity,
                    ontological_character = :enduring,
                ),
            ],
            edges = [
                (:diagnosis, :pasture, 1),
                (:pasture, :weight, 0),
                (:weight, :weight, 1),
            ],
        )
        u = unroll_temporal_dag(spec, 2)
        @test u.T == 2
        @test nv(u.graph) == 1 + 3 + 3
        @test is_single_node(spec.nodes[2])
        @test !is_single_node(spec.nodes[3])
        @test temporal_node(u, :pasture, 1) == enduring_node(u, :pasture)
        @test temporal_node_label(u, enduring_node(u, :pasture)) == "pasture"
        @test temporal_node_label(u, temporal_node(u, :diagnosis, 0)) == "diagnosis[0]"
        @test has_edge(u.graph, temporal_node(u, :diagnosis, 0), enduring_node(u, :pasture))
        @test has_edge(u.graph, enduring_node(u, :pasture), temporal_node(u, :weight, 1))
        @test !has_edge(u.graph, enduring_node(u, :pasture), temporal_node(u, :weight, 0))
        @test_throws ArgumentError temporal_node(u, :pasture, 0)

        constitution = temporal_edge_records(u)
        constitutive = only(filter(record -> record.role === :constitutive, constitution))
        recurrent = filter(record -> record.role === :recurrent_influence, constitution)
        @test constitutive.parent == (:diagnosis, 0)
        @test constitutive.child == (:pasture, nothing)
        @test length(recurrent) == 2
        @test all(record.parent == (:pasture, nothing) for record in recurrent)
        @test Set(record.child for record in recurrent) == Set([(:weight, 1), (:weight, 2)])

        proj = causal_projection(u)
        @test ne(proj.graph) == ne(u.graph) - 1  # constitutive edge excluded
        @test only(proj.constraints).relation_kind === :constitutive_persistence
    end

    @testset "validation errors" begin
        @test_throws ArgumentError unroll_temporal_dag(
            TemporalDAGSpec(nodes = [TemporalNodeSpec(:x)], edges = [(:y, :x, 0)]),
            2,
        )
        @test_throws ArgumentError unroll_temporal_dag(
            TemporalDAGSpec(nodes = [TemporalNodeSpec(:x)], edges = [(:x, :x, -1)]),
            2,
        )
        @test_throws ArgumentError unroll_temporal_dag(TemporalDAGSpec(nodes = [TemporalNodeSpec(:x)], edges = []), -1)
        @test_throws ArgumentError TemporalNodeSpec(:x; temporal_mode = :unknown)
        @test_throws ArgumentError TemporalNodeSpec(:x; temporal_support = :interval)
        @test_throws ArgumentError unroll_temporal_dag(
            TemporalDAGSpec(nodes = [TemporalNodeSpec(:x; onset_time = 3)], edges = []),
            2,
        )
        @test_throws ArgumentError unroll_temporal_dag(
            TemporalDAGSpec(
                nodes = [
                    TemporalNodeSpec(:x),
                    TemporalNodeSpec(:a; temporal_support = FromOnsetSupport(1)),
                ],
                edges = [(:x, :a, 2)],
            ),
            2,
        )
        @test_throws ArgumentError unroll_temporal_dag(
            TemporalDAGSpec(
                nodes = [TemporalNodeSpec(:x)],
                edges = [],
                graph_kind = ProcessGraph(),
            ),
            1,
        )
    end

    @testset "occasion influence records" begin
        spec = TemporalDAGSpec(
            nodes = [TemporalNodeSpec(:x), TemporalNodeSpec(:y)],
            edges = [(:x, :y, 0)],
        )
        u = unroll_temporal_dag(spec, 1)
        records = temporal_edge_records(u)
        @test length(records) == 2
        @test all(record.role === :occasion_influence for record in records)
    end
end
