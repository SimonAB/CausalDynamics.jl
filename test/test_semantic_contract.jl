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
        # A bare Boolean records nothing and is refused.
        @test_throws ArgumentError assert_interval_summary_do!(nodes, ι; justified = true)
        @test_throws ArgumentError validate_intervention_semantics(
            nodes, ι; macro_intervention_justified = true,
        )
        # A recorded justification of a macro-intervention kind naming the target passes.
        j = InterventionJustification(
            :trajectory_generator, [:cum_exp],
            "do(cum_exp) stands for the constant-dose trajectory generator in protocol §2",
        )
        @test assert_interval_summary_do!(nodes, ι; justification = j) === nothing
        @test validate_intervention_semantics(
            nodes, ι; macro_intervention_justification = j,
        ) === nothing
        # Wrong kind or wrong target does not license the intervention.
        wrong_kind = InterventionJustification(:physical_justification, [:cum_exp], "dose is deliverable")
        @test_throws ArgumentError assert_interval_summary_do!(nodes, ι; justification = wrong_kind)
        other_target = InterventionJustification(:certificate_note, [:y], "note about y")
        @test_throws ArgumentError assert_interval_summary_do!(nodes, ι; justification = other_target)
        # Justifications must state a reason and a kind from the known list.
        @test_throws ArgumentError InterventionJustification(:certificate_note, [:cum_exp], "  ")
        @test_throws ArgumentError InterventionJustification(:because, [:cum_exp], "reason")
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
        @test_throws ArgumentError assert_feasibility!([c], ι; justified = true)
        physical = InterventionJustification(
            :physical_justification, [:a],
            "99 units is within the pump's rated delivery range (manufacturer sheet).",
        )
        @test assert_feasibility!([c], ι; justification = physical) === nothing
        # A macro-intervention justification does not license feasibility.
        macro_j = InterventionJustification(:certificate_note, [:a], "see certificate")
        @test_throws ArgumentError assert_feasibility!([c], ι; justification = macro_j)
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
        sheep = ReferentSpec(
            :sheep_17;
            identity_criterion = :organisational_continuity,
            ontological_character = :enduring,
        )
        spec = TemporalDAGSpec(
            nodes = [
                TemporalNodeSpec(
                    :weight;
                    value_representation = :state,
                    referent = sheep,
                ),
            ],
            edges = [(:weight, :weight, 1)],
        )
        u = unroll_temporal_dag(spec, 2)
        @test nv(u.graph) == 3
        @test only(spec.nodes).referent_id === :sheep_17
        @test only(spec.nodes).ontological_character === :enduring
        @test only(spec.nodes).identity_criterion === :organisational_continuity
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
        @test policy_information_set(π, 3) == Set([:w])
        # A rule reading outside ℋ fails loudly rather than peeking.
        peeking = policy(:a => (state, t) -> state.y_future; information_set = [:w])
        @test_throws ErrorException intervention_value(peeking, :a, 1, 0.0, state)
    end

    @testset "Policy information set derived from ObservationBridge" begin
        bridge = ObservationBridge(
            Dict(:w => :w_obs, :y => :y_obs);
            availability = Dict(:y_obs => 2),
        )
        # Time-varying ℋ_t: y enters the decision set only from t = 2; the
        # unmapped :z is never observable and so never available.
        π = policy(
            :a => (state, t) -> haskey(state, :y) ? state.y : state.w;
            information_set = bridge,
        )
        @test π.information_set === bridge
        @test policy_information_set(π, 1) == Set([:w])
        @test policy_information_set(π, 2) == Set([:w, :y])
        state = (w = 1.0, y = 5.0, z = 7.0)
        @test intervention_value(π, :a, 1, 0.0, state) == 1.0
        @test intervention_value(π, :a, 2, 0.0, state) == 5.0
        greedy = policy(:a => (state, t) -> state.z; information_set = bridge)
        @test_throws ErrorException intervention_value(greedy, :a, 2, 0.0, state)
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
