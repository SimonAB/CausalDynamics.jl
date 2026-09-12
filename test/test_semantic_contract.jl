using CausalDynamics
using Test
using Graphs
using Random

@testset "orthogonal semantic contract" begin
    @testset "interval-summary scalar do refused" begin
        nodes = [
            TemporalNodeSpec(
                :cum_exp;
                temporal_support = IntervalSupport(1, 7),
                value_representation = :interval_summary,
            ),
            TemporalNodeSpec(:y; value_representation = :state),
        ]
        ι = do_sequence(:cum_exp => 1.0)
        @test_throws ArgumentError assert_interval_summary_do!(nodes, ι)
        assert_interval_summary_do!(nodes, ι; justified = true)
        validate_intervention_semantics(nodes, ι; macro_intervention_justified = true)
    end

    @testset "feasibility constraint blocks intervention" begin
        c = StructuralConstraintSpec(
            :viable_dose,
            [:a];
            kind = :feasibility,
            claim = "Dose must remain in the physically admissible range.",
        )
        ι = do_sequence(:a => 99.0)
        @test_throws ArgumentError assert_feasibility!([c], ι)
        assert_feasibility!([c], ι; justified = true)
        @test constraint_certificate(c).claim_kind === :declared_assumption
    end

    @testset "ObservationBridge availability clocks" begin
        bridge = ObservationBridge(
            Dict(:y => :y_obs);
            availability = Dict(:y_obs => 2),
        )
        @test !available_at(bridge, :y_obs, 1)
        @test available_at(bridge, :y_obs, 2)
        @test :y_obs in information_set_at(bridge, 2)
        @test !(:y_obs in information_set_at(bridge, 1))
    end

    @testset "two times / one referent" begin
        spec = TemporalDAGSpec(
            nodes = [
                TemporalNodeSpec(
                    :weight;
                    value_representation = :state,
                    referent_id = :sheep_17,
                    identity_criterion = :organisational_continuity,
                    ontological_character = :enduring,
                ),
            ],
            edges = [(:weight, :weight, 1)],
        )
        u = unroll_temporal_dag(spec, 2)
        @test nv(u.graph) == 3
        @test all(n.referent_id === :sheep_17 for n in spec.nodes)
        @test !is_single_node(spec.nodes[1])
    end

    @testset "process graph identify unsupported" begin
        spec = TemporalDAGSpec(
            nodes = [TemporalNodeSpec(:x), TemporalNodeSpec(:y)],
            edges = [(:x, :y, 0)],
            graph_kind = ProcessGraph(),
        )
        @test_throws ArgumentError unroll_temporal_dag(spec, 1)
    end

    @testset "participation vs influence projection" begin
        spec = TemporalDAGSpec(
            nodes = [
                TemporalNodeSpec(:part),
                TemporalNodeSpec(:whole; temporal_support = FromOnsetSupport(0)),
                TemporalNodeSpec(:y),
            ],
            edges = [
                LaggedEdge(:part, :whole, 0; relation_kind = :constitutive_dependence),
                LaggedEdge(:whole, :y, 0),
            ],
        )
        u = unroll_temporal_dag(spec, 1)
        proj = causal_projection(u)
        @test length(proj.constraints) == 1
        @test only(proj.constraints).relation_kind === :constitutive_dependence
        @test ne(proj.graph) == ne(u.graph) - 1
    end

    @testset "Policy information set" begin
        π = policy(:a => (state, t) -> state.w; information_set = [:w])
        @test π.information_set == Set([:w])
        state = (w = 1.0, y_future = 9.0)
        @test intervention_value(π, :a, 1, 0.0, state) == 1.0
    end

    @testset "fingerprint distinguishes outcome support" begin
        n1 = TemporalNodeSpec(:y; temporal_support = PointSupport(1), value_representation = :state)
        n2 = TemporalNodeSpec(
            :y;
            temporal_support = IntervalSupport(1, 3),
            value_representation = :interval_summary,
        )
        @test semantic_fingerprint(n1.name, n1.temporal_support, n1.value_representation) !=
              semantic_fingerprint(n2.name, n2.temporal_support, n2.value_representation)
    end
end
