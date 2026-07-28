using CausalDynamics
using Graphs
using Test

@testset "Discovery bridge (core)" begin
    @testset "cpdag_to_dag" begin
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 1)
        add_edge!(g, 1, 3)
        h = cpdag_to_dag(g)
        @test is_dag(h)
        @test has_edge(h, 1, 2)
        @test !has_edge(h, 2, 1)
        @test has_edge(h, 1, 3)
    end

    @testset "prepare_from_discovery with complete" begin
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 1)
        add_edge!(g, 1, 3)
        add_edge!(g, 2, 3)
        confounders, ok = prepare_from_discovery(g, 2, 3; complete=true)
        @test ok
        @test 1 in confounders
    end

    @testset "digraph_with_names and prepare_from_discovery" begin
        g = DiGraph(3)
        add_edge!(g, 1, 2)  # Z → X
        add_edge!(g, 1, 3)  # Z → Y
        add_edge!(g, 2, 3)  # X → Y
        names = [:z, :x, :y]
        cg = digraph_with_names(g, names)
        @test cg isa CausalGraph
        @test get_node_prop(cg, 1, :name) == :z

        confounders, ok = prepare_from_discovery(g, 2, 3)
        @test ok
        @test confounders == [1]

        confounders2, ok2 = prepare_from_discovery(g, :x, :y; node_names=Dict(1 => :z, 2 => :x, 3 => :y))
        @test ok2
        @test confounders2 == [:z]

        confounders3, ok3 = prepare_from_discovery(cg, :x, :y)
        @test ok3
        @test confounders3 == [:z]
    end

    @testset "oce_parents_to_temporal_spec" begin
        # Hand-crafted OCE-style parent list: x₁(-1) → x₂(0)
        parents = [
            (i = 1, parents_js = Int[], parents_τs = Int[]),
            (i = 2, parents_js = [1], parents_τs = [-1]),
        ]
        spec = oce_parents_to_temporal_spec(parents, [:x1, :x2])
        @test spec isa TemporalDAGSpec
        @test spec.edges == [LaggedEdge(:x1, :x2, 1)]

        u = unroll_temporal_dag(spec, 4)
        @test is_dag(u.graph)
        @test temporal_node(u, :x1, 1) == 1
        @test has_edge(u.graph, temporal_node(u, :x1, 1), temporal_node(u, :x2, 2))
    end

    @testset "validation errors" begin
        g = DiGraph(2)
        @test_throws ArgumentError digraph_with_names(g, [:a])
        @test_throws ArgumentError oce_parents_to_temporal_spec(
            [(i = 1, parents_js = Int[], parents_τs = Int[])],
            [:x1, :x2],
        )
        @test_throws ArgumentError prepare_from_discovery(g, :a, :b)
    end

    @testset "has_associations" begin
        @test has_associations() == !isnothing(
            Base.get_extension(CausalDynamics, :CausalDynamicsAssociationsExt),
        )
    end
end
