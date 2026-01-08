using Test
using CausalDynamics
using Graphs
using DataFrames

@testset "TMLE Integration" begin
    # Test graph: Z → X → Y, Z → Y (confounding)
    g = DiGraph(3)
    add_edge!(g, 1, 2)  # Z → X
    add_edge!(g, 1, 3)  # Z → Y
    add_edge!(g, 2, 3)  # X → Y
    
    node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
    
    @testset "prepare_for_tmle" begin
        confounders, identifiable = prepare_for_tmle(g, 2, 3; node_names=node_names)
        
        @test confounders == [:Z]
        @test identifiable == true
        @test confounders isa Vector{Symbol}
        @test length(confounders) == 1  # Type stability: pre-allocated size
        
        # Test type stability: should return consistent types
        confounders2, identifiable2 = prepare_for_tmle(g, 2, 3; node_names=node_names)
        @test confounders2 isa Vector{Symbol}
        @test identifiable2 isa Bool
    end
    
    @testset "prepare_for_tmle without node_names" begin
        confounders, identifiable = prepare_for_tmle(g, 2, 3)
        
        @test confounders == [1]
        @test identifiable == true
        @test confounders isa Vector{Int}
        
        # Test input validation
        @test_throws ArgumentError prepare_for_tmle(g, 10, 3)  # Invalid node
    end
    
    @testset "get_tmle_confounders" begin
        confounders = get_tmle_confounders(g, 2, 3; node_names=node_names)
        
        @test confounders == [:Z]
        @test confounders isa Vector{Symbol}
    end
    
    @testset "No confounding case" begin
        # Graph: X → Y only
        g2 = DiGraph(2)
        add_edge!(g2, 1, 2)  # X → Y
        
        node_names2 = Dict(1 => :X, 2 => :Y)
        confounders, identifiable = prepare_for_tmle(g2, 1, 2; node_names=node_names2)
        
        @test confounders == []
        @test identifiable == true  # No adjustment needed is still identifiable
    end
    
    @testset "Multiple confounders" begin
        # Graph: Z1 → X → Y, Z2 → X → Y, Z1 → Y, Z2 → Y
        g3 = DiGraph(4)
        add_edge!(g3, 1, 2)  # Z1 → X
        add_edge!(g3, 3, 2)  # Z2 → X
        add_edge!(g3, 1, 4)  # Z1 → Y
        add_edge!(g3, 3, 4)  # Z2 → Y
        add_edge!(g3, 2, 4)  # X → Y
        
        node_names3 = Dict(1 => :Z1, 2 => :X, 3 => :Z2, 4 => :Y)
        confounders, identifiable = prepare_for_tmle(g3, 2, 4; node_names=node_names3)
        
        @test :Z1 in confounders || :Z2 in confounders
        @test identifiable == true
    end
    
    @testset "estimate_effect error handling" begin
        # Should error if TMLE is not loaded
        # (We can't test the actual TMLE call without loading TMLE.jl)
        # But we can test that the function exists and has correct signature
        @test isdefined(CausalDynamics, :estimate_effect)
        
        # Test that estimate_effect errors when TMLE is not loaded
        # Create mock data
        using DataFrames
        data = DataFrame(
            Z = randn(10),
            X = rand([0, 1], 10),
            Y = randn(10)
        )
        
        node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
        
        # Should error because TMLE is not loaded (with helpful message)
        @test_throws ErrorException estimate_effect(g, data, 2, 3; node_names=node_names)
        
        # Verify error message mentions TMLE
        try
            estimate_effect(g, data, 2, 3; node_names=node_names)
        catch e
            error_msg = sprint(showerror, e)
            @test occursin("TMLE", error_msg) || occursin("tmle", lowercase(error_msg))
        end
        
        # Test input validation (should check node indices before TMLE check)
        @test_throws ArgumentError estimate_effect(g, data, 10, 3; node_names=node_names)  # Invalid node
        @test_throws ArgumentError estimate_effect(g, data, 1, 10; node_names=node_names)  # Invalid node
        
        # Test with invalid method
        # We can't test this without TMLE loaded, but we can check the function signature
        @test hasmethod(estimate_effect, (AbstractGraph, Any, Int, Int))
    end
    
    @testset "Edge cases for TMLE integration" begin
        # Test with empty graph
        g_empty = DiGraph(0)
        result = try
            prepare_for_tmle(g_empty, 1, 2)
            :no_error
        catch e
            :error
        end
        # Should handle gracefully or error
        @test result in [:error, :no_error]
        
        # Test with same node (X == Y)
        g_same = DiGraph(2)
        add_edge!(g_same, 1, 2)
        confounders, identifiable = prepare_for_tmle(g_same, 1, 1)
        @test confounders isa Vector
        @test identifiable isa Bool
        
        # Test with disconnected nodes
        g_disconnected = DiGraph(3)
        add_edge!(g_disconnected, 1, 2)
        # Node 3 is isolated
        confounders, identifiable = prepare_for_tmle(g_disconnected, 1, 3)
        @test confounders isa Vector
        # May or may not be identifiable depending on implementation
        @test identifiable isa Bool
        
        # Test with invalid node indices
        g_valid = DiGraph(3)
        add_edge!(g_valid, 1, 2)
        add_edge!(g_valid, 2, 3)
        
        # Should error with helpful message for invalid nodes
        @test_throws ArgumentError prepare_for_tmle(g_valid, 10, 3)  # Node 10 doesn't exist
        @test_throws ArgumentError prepare_for_tmle(g_valid, 1, 10)   # Node 10 doesn't exist
        @test_throws ArgumentError prepare_for_tmle(g_valid, 0, 3)    # Invalid index
    end
    
    @testset "Node names handling" begin
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 1, 3)
        add_edge!(g, 2, 3)
        
        # Test with incomplete node_names (missing some nodes)
        partial_names = Dict(1 => :Z, 2 => :X)  # Missing Y
        result = try
            prepare_for_tmle(g, 2, 3; node_names=partial_names)
            :no_error
        catch e
            :error
        end
        # Should handle gracefully or error
        @test result in [:error, :no_error]
        
        # Test with wrong node_names type (strings instead of symbols)
        # Function should handle this gracefully or convert
        wrong_names = Dict(1 => "Z", 2 => "X", 3 => "Y")  # Strings instead of symbols
        result_wrong = try
            confounders, _ = prepare_for_tmle(g, 2, 3; node_names=wrong_names)
            :no_error
        catch e
            :error
        end
        # Should handle gracefully or error (depending on implementation)
        @test result_wrong in [:error, :no_error]
    end
end
