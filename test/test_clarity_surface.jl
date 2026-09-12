using CausalDynamics
using Test

@testset "clarity surface (exports and removed APIs)" begin
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

    @testset "unit_level override and unrolling-free panel API are gone" begin
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
        # Unrolling-free query_panel_columns(query; …) was removed
        @test length(methods(query_panel_columns)) == 1
        @test_throws MethodError query_panel_columns(query)
    end

    @testset "GlobalSupport is single-node, not unspecified time-invariance" begin
        @test parse_temporal_support(:global) isa GlobalSupport
        @test parse_temporal_support(:from_onset; onset = 2) == FromOnsetSupport(2)
        @test_throws ArgumentError parse_temporal_support(:from_onset)
        @test_throws ArgumentError parse_temporal_support(:interval)

        spec = TemporalDAGSpec(
            nodes = [
                TemporalNodeSpec(:site; temporal_support = GlobalSupport()),
                TemporalNodeSpec(:y),
            ],
            edges = [(:site, :y, 0)],
        )
        @test is_single_node(spec.nodes[1])
        u = unroll_temporal_dag(spec, 2)
        site_idx = single_node(u, :site)
        @test site_idx isa Integer
        # Only one node exists; timed lookup resolves to that same index
        @test temporal_node(u, :site, 0) == site_idx
        @test temporal_node(u, :site, 1) == site_idx
        qcols = query_panel_columns(u, TemporalEffectQuery(:site, :y, 1, 1))
        @test qcols.treatment === :site
        @test qcols.outcome === :y1
    end
end
