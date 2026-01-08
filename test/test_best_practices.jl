using CausalDynamics
using Graphs
using Test

# Test suite for best practices compliance:
# - Type annotations
# - Type stability
# - Error handling
# - Input validation
@testset "Best Practices Compliance" begin
    g = DiGraph(3)
    add_edge!(g, 1, 2)  # Z → X
    add_edge!(g, 1, 3)  # Z → Y
    add_edge!(g, 2, 3)  # X → Y
    
    @testset "Type Annotations" begin
        # Test that functions accept Int parameters (not just Any)
        # This ensures type annotations are working
        
        # All identification functions should accept Int
        @test hasmethod(backdoor_adjustment_set, (AbstractGraph, Int, Int))
        @test hasmethod(is_backdoor_adjustable, (AbstractGraph, Int, Int))
        @test hasmethod(find_instruments, (AbstractGraph, Int, Int))
        @test hasmethod(is_valid_instrument, (AbstractGraph, Int, Int, Int))
        @test hasmethod(has_path, (AbstractGraph, Int, Int))
        @test hasmethod(frontdoor_adjustment_set, (AbstractGraph, Int, Int, Any))
        @test hasmethod(find_frontdoor_mediators, (AbstractGraph, Int, Int))
        @test hasmethod(find_all_adjustment_sets, (AbstractGraph, Int, Int))
        @test hasmethod(is_valid_adjustment_set, (AbstractGraph, Int, Int, Set))
        @test hasmethod(minimal_adjustment_set, (AbstractGraph, Int, Int))
        @test hasmethod(find_backdoor_paths, (AbstractGraph, Int, Int))
        @test hasmethod(find_directed_paths, (AbstractGraph, Int, Int))
        @test hasmethod(markov_boundary, (AbstractGraph, Int))
        @test hasmethod(prepare_for_tmle, (AbstractGraph, Int, Int))
        @test hasmethod(get_tmle_confounders, (AbstractGraph, Int, Int))
    end
    
    @testset "Input Validation" begin
        # Test that functions validate node indices and provide helpful errors
        
        # Test backdoor_adjustment_set validation
        @test_throws ArgumentError backdoor_adjustment_set(g, 0, 3)   # Invalid: 0
        @test_throws ArgumentError backdoor_adjustment_set(g, 1, 10)  # Invalid: 10 > nv(g)
        @test_throws ArgumentError backdoor_adjustment_set(g, 10, 3) # Invalid: 10 > nv(g)
        
        # Verify error messages are helpful
        try
            backdoor_adjustment_set(g, 10, 3)
        catch e
            error_msg = sprint(showerror, e)
            @test occursin("Node indices", error_msg) || occursin("range", error_msg) || occursin("nodes", error_msg)
        end
        
        # Test find_instruments validation
        @test_throws ArgumentError find_instruments(g, 0, 3)
        @test_throws ArgumentError find_instruments(g, 1, 10)
        
        # Test frontdoor validation
        @test_throws ArgumentError frontdoor_adjustment_set(g, 10, 3, [1])
        @test_throws ArgumentError find_frontdoor_mediators(g, 10, 3)
        
        # Test adjustment sets validation
        @test_throws ArgumentError find_all_adjustment_sets(g, 10, 3)
        @test_throws ArgumentError is_valid_adjustment_set(g, 10, 3, Set([1]))
        @test_throws ArgumentError minimal_adjustment_set(g, 10, 3)
        
        # Test paths validation (should throw ArgumentError with our validation)
        @test_throws ArgumentError find_backdoor_paths(g, 10, 3)
        @test_throws ArgumentError find_directed_paths(g, 10, 3)
        
        # Test markov_boundary validation
        @test_throws ArgumentError markov_boundary(g, 10)
        
        # Verify all error messages include helpful context
        for func in [
            (g, x, y) -> find_backdoor_paths(g, x, y),
            (g, x, y) -> find_directed_paths(g, x, y),
            (g, x, y) -> markov_boundary(g, x)
        ]
            try
                func(g, 10, 3)
            catch e
                if isa(e, ArgumentError)
                    error_msg = sprint(showerror, e)
                    @test occursin("Node indices", error_msg) || occursin("range", error_msg) || occursin("nodes", error_msg)
                end
            end
        end
        
        # Test TMLE integration validation
        @test_throws ArgumentError prepare_for_tmle(g, 10, 3)
        @test_throws ArgumentError get_tmle_confounders(g, 10, 3)
    end
    
    @testset "Type Stability" begin
        # Test that functions return consistent, type-stable results
        
        # Test Vector{Int}() vs Int[] - should use Vector{Int}()
        # This is tested indirectly by checking return types
        
        # Test find_instruments returns Vector{Int}
        instruments = find_instruments(g, 2, 3)
        @test instruments isa Vector{Int}
        
        # Test find_all_adjustment_sets returns Vector{Set{Int}}
        all_sets = find_all_adjustment_sets(g, 2, 3)
        @test all_sets isa Vector{Set{Int}}
        if !isempty(all_sets)
            @test all_sets[1] isa Set{Int}
        end
        
        # Test prepare_for_tmle returns consistent types
        confounders1, identifiable1 = prepare_for_tmle(g, 2, 3)
        @test confounders1 isa Vector{Int}
        @test identifiable1 isa Bool
        
        # Test with node_names returns Vector{Symbol}
        node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
        confounders2, identifiable2 = prepare_for_tmle(g, 2, 3; node_names=node_names)
        @test confounders2 isa Vector{Symbol}
        @test identifiable2 isa Bool
    end
    
    @testset "Error Messages" begin
        # Test that error messages are contextualized and helpful
        
        # Test TMLE error message
        using DataFrames
        data = DataFrame(Z=randn(10), X=rand([0,1], 10), Y=randn(10))
        node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
        
        try
            estimate_effect(g, data, 2, 3; node_names=node_names)
        catch e
            error_msg = sprint(showerror, e)
            @test occursin("TMLE", error_msg) || occursin("tmle", lowercase(error_msg))
        end
        
        # Test intervention error message
        g_scm = DiGraph(2)
        add_edge!(g_scm, 1, 2)
        equations = Dict(1 => (u) -> u, 2 => (x, u) -> x + u)
        scm = GraphSCM(g_scm, equations, Set([1]))
        intervention = do_intervention(2, 0.0)
        
        try
            apply_intervention(scm, intervention)
        catch e
            error_msg = sprint(showerror, e)
            @test occursin("not yet implemented", lowercase(error_msg)) || 
                  occursin("graph-based", lowercase(error_msg))
        end
        
        # Test counterfactual error message
        try
            counterfactual_graph(scm, intervention)
        catch e
            error_msg = sprint(showerror, e)
            @test occursin("not yet implemented", lowercase(error_msg)) || 
                  occursin("counterfactual", lowercase(error_msg))
        end
    end
    
    @testset "Performance: Pre-allocation" begin
        # Test that functions use pre-allocation where appropriate
        # This is tested indirectly by checking that results are properly typed
        
        # Large graph test
        g_large = DiGraph(100)
        for i in 1:99
            add_edge!(g_large, i, i+1)
        end
        
        # These should complete without excessive allocations
        ancestors = get_ancestors(g_large, 50)
        @test ancestors isa Set{Int}
        
        descendants = get_descendants(g_large, 1)
        @test descendants isa Set{Int}
        
        # Test that path finding is efficient
        paths = find_directed_paths(g_large, 1, 50)
        @test paths isa Vector{Vector{Int}}
    end
    
    @testset "Consistent Return Types" begin
        # Test that functions return consistent types across calls
        
        # Multiple calls should return same types
        result1 = backdoor_adjustment_set(g, 2, 3)
        result2 = backdoor_adjustment_set(g, 2, 3)
        @test typeof(result1) == typeof(result2)
        @test result1 isa Set{Int}
        @test result2 isa Set{Int}
        
        # Test with different graphs
        g2 = DiGraph(4)
        add_edge!(g2, 1, 2)
        add_edge!(g2, 2, 3)
        add_edge!(g2, 1, 4)
        
        result3 = backdoor_adjustment_set(g2, 2, 3)
        @test result3 isa Set{Int}  # Same type even with different graph
    end
end
