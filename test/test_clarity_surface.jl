using CausalDynamics
using Test

@testset "clarity surface (exports and panel mapping)" begin
    public = names(CausalDynamics)

    @testset "single_node is public; enduring_node is not" begin
        @test :single_node ∈ public
        @test :is_single_node ∈ public
        @test :enduring_node ∉ public
        @test !isdefined(CausalDynamics, :enduring_node)
    end

    @testset "experimental Hypergraph and normalise_* stay unexported" begin
        @test :Hypergraph ∉ public
        @test isdefined(CausalDynamics, :Hypergraph)
        @test :normalise_value_representation ∉ public
        @test isdefined(CausalDynamics, :normalise_value_representation)
    end

    @testset "panel bridge refuses unit_level override" begin
        spec = TemporalDAGSpec(
            nodes = [
                TemporalNodeSpec(:grid_type; temporal_support = FromOnsetSupport(0)),
                TemporalNodeSpec(:fec),
            ],
            edges = [(:grid_type, :fec, 0)],
        )
        u = unroll_temporal_dag(spec, 2)
        query = TemporalEffectQuery(:grid_type, :fec, 1, 1)
        @test_throws MethodError plan_targeted_estimation(
            u, query, [:grid_type, :fec1];
            unit_level = [:grid_type],
        )
        @test_throws MethodError temporal_adjustment_columns(
            identify(u, query), u;
            unit_level = [:grid_type],
        )
        qcols = query_panel_columns(u, query)
        @test qcols.treatment === :grid_type
        @test qcols.outcome === :fec1
    end

    @testset "pointwise treatment needs timed column without FromOnsetSupport" begin
        spec = TemporalDAGSpec([:a, :y], [(:a, :y, 0)])
        u = unroll_temporal_dag(spec, 2)
        query = TemporalEffectQuery(:a, :y, 1, 1)
        qcols = query_panel_columns(u, query)
        @test qcols.treatment === :a1
        @test qcols.outcome === :y1
    end
end
