using CausalDynamics
using Graphs
using Test

@testset "CausalGraph" begin
    @testset "construction and delegation" begin
        g = CausalGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 1, 3)
        add_edge!(g, 2, 3)
        @test nv(g) == 3
        @test ne(g) == 3
        @test has_edge(g, 1, 2)
        @test is_dag(g)
    end

    @testset "node and graph properties" begin
        g = CausalGraph(2)
        add_edge!(g, 1, 2)
        set_node_prop!(g, 1, :name, :Z)
        set_node_prop!(g, 2, :name, :X)
        set_prop!(g, :study, "demo")
        @test get_node_prop(g, 1, :name) == :Z
        @test get_prop(g, :study) == "demo"
        @test has_node_prop(g, 1, :name)
        delete_prop!(g, :study)
        @test !has_prop(g, :study)
    end

    @testset "edge properties" begin
        g = CausalGraph(2)
        add_edge!(g, 1, 2)
        set_edge_prop!(g, 1, 2, :weight, 0.5)
        @test get_edge_prop(g, 1, 2, :weight) == 0.5
        delete_edge_prop!(g, 1, 2, :weight)
        @test !has_edge_prop(g, 1, 2, :weight)
    end

    @testset "node names and attach_data" begin
        g = CausalGraph(2)
        add_edge!(g, 1, 2)
        names = Dict(1 => :Z, 2 => :X)
        data = (Z = [1.0, 2.0], X = [0.0, 1.0])
        attach_data!(g, data; node_names = names)
        @test get_node_name(g, 1) == :Z
        @test get_node_names(g) == names
        @test has_data(g)
        @test get_data(g) == data
    end

    @testset "identification on CausalGraph" begin
        g = CausalGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 1, 3)
        add_edge!(g, 2, 3)
        adj = backdoor_adjustment_set(g, 2, 3)
        @test adj == Set([1])
    end

    @testset "convert to DiGraph" begin
        g = CausalGraph(2)
        add_edge!(g, 1, 2)
        dg = convert(DiGraph, g)
        @test has_edge(dg, 1, 2)
    end
end
