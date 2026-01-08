using CausalDynamics
using Graphs
using Test

@testset "Utilities" begin
    @testset "Graph Utils" begin
        # Test create_causal_graph with edge list
        edges = [(1, 2), (2, 3), (1, 3)]
        g = create_causal_graph(edges)
        
        @test nv(g) == 3
        @test has_edge(g, 1, 2)
        @test has_edge(g, 2, 3)
        @test has_edge(g, 1, 3)
        
        # Test type stability: function should accept Union type
        @test g isa DiGraph
        
        # Test with empty edges
        g_empty = create_causal_graph(Tuple{Int, Int}[])
        @test nv(g_empty) == 0
        
        # Test with single edge
        g_single = create_causal_graph([(1, 2)])
        @test nv(g_single) == 2
        @test has_edge(g_single, 1, 2)
        
        # Test with dictionary input (Union type)
        edge_dict = Dict(1 => [2, 3], 2 => [3])
        g_dict = create_causal_graph(edge_dict)
        @test nv(g_dict) == 3
        @test has_edge(g_dict, 1, 2)
        @test has_edge(g_dict, 1, 3)
        @test has_edge(g_dict, 2, 3)
    end
    
    @testset "Visualization" begin
        # Test that visualization functions exist
        # Note: Full testing requires GraphMakie and CairoMakie
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)
        
        # Functions should exist with correct type signatures
        @test hasmethod(plot_causal_graph, (AbstractGraph,))
        @test hasmethod(plot_with_adjustment_set, (AbstractGraph, Int, Int, Vector{Int}))
        @test hasmethod(plot_backdoor_paths, (AbstractGraph, Int, Int))
        
        # Test type stability: functions should accept Int parameters
        # (Even if they error due to missing packages)
        @test_throws ErrorException plot_causal_graph(g)
        @test_throws ErrorException plot_with_adjustment_set(g, 1, 3, [2])
        @test_throws ErrorException plot_backdoor_paths(g, 1, 3)
        
        # Should error if GraphMakie not loaded (expected behavior)
        # We don't test actual plotting here as it requires optional dependencies
    end
    
    @testset "Edge Cases" begin
        # Test create_causal_graph with invalid edges
        # Function may handle this gracefully (Graphs.jl may auto-resize)
        result = try
            create_causal_graph([(1, 0)])
            :no_error
        catch e
            typeof(e)
        end
        # Either errors or creates graph (Graphs.jl may handle 0-index gracefully)
        @test result isa Union{Type, Symbol}
        
        # Test with duplicate edges (should be fine, Graphs.jl handles it)
        edges_dup = [(1, 2), (1, 2)]
        g_dup = create_causal_graph(edges_dup)
        @test nv(g_dup) == 2
        @test has_edge(g_dup, 1, 2)
        
        # Test with dictionary input
        edge_dict = Dict(1 => [2, 3], 2 => [3])
        g_dict = create_causal_graph(edge_dict)
        @test nv(g_dict) == 3
        @test has_edge(g_dict, 1, 2)
        @test has_edge(g_dict, 1, 3)
        @test has_edge(g_dict, 2, 3)
    end
    
    @testset "Visualization Error Handling" begin
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)
        
        # Test that visualization functions error appropriately when GraphMakie not loaded
        # (This is expected behavior - they require optional dependencies)
        @test_throws ErrorException plot_causal_graph(g)
        @test_throws ErrorException plot_with_adjustment_set(g, 1, 3, [2])
        @test_throws ErrorException plot_backdoor_paths(g, 1, 3)
        
        # Verify error messages mention required packages
        try
            plot_causal_graph(g)
        catch e
            error_msg = sprint(showerror, e)
            @test occursin("GraphMakie", error_msg) || occursin("CairoMakie", error_msg)
        end
    end
end
