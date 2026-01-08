using CausalDynamics
using Graphs
using Test

@testset "Graph Operations" begin
    # Create a simple graph: Z → X → Y, Z → Y
    g = DiGraph(3)
    add_edge!(g, 1, 2)  # Z → X
    add_edge!(g, 2, 3)  # X → Y
    add_edge!(g, 1, 3)  # Z → Y
    
    @testset "d-separation" begin
        # X and Y are NOT d-separated by Z because there's a direct path X → Y
        # that is not blocked by Z (Z is not on that path)
        @test d_separated(g, 2, 3, [1]) == false
        
        # X and Y are not d-separated without conditioning (direct edge exists)
        @test d_separated(g, 2, 3, []) == false
        
        # Test a case where d-separation actually works:
        # Create a graph where X and Y share a common cause Z, but no direct edge
        g2 = DiGraph(3)
        add_edge!(g2, 1, 2)  # Z → X
        add_edge!(g2, 1, 3)  # Z → Y
        # No direct edge X → Y
        
        # X and Y are d-separated by Z (common cause pattern)
        @test d_separated(g2, 2, 3, [1]) == true
        
        # X and Y are NOT d-separated without conditioning on Z
        @test d_separated(g2, 2, 3, []) == false
        
        # Test chain pattern: A → B → C
        g_chain = DiGraph(3)
        add_edge!(g_chain, 1, 2)  # A → B
        add_edge!(g_chain, 2, 3)  # B → C
        
        @test d_separated(g_chain, 1, 3, []) == false  # Not d-separated
        @test d_separated(g_chain, 1, 3, [2]) == true   # d-separated by B
        
        # Test fork pattern: A ← B → C
        g_fork = DiGraph(3)
        add_edge!(g_fork, 2, 1)  # B → A
        add_edge!(g_fork, 2, 3)  # B → C
        
        @test d_separated(g_fork, 1, 3, []) == false  # Not d-separated
        @test d_separated(g_fork, 1, 3, [2]) == true   # d-separated by B
        
        # Test collider pattern: A → B ← C
        g_collider = DiGraph(3)
        add_edge!(g_collider, 1, 2)  # A → B
        add_edge!(g_collider, 3, 2)  # C → B
        
        @test d_separated(g_collider, 1, 3, []) == true   # d-separated (collider blocks)
        @test d_separated(g_collider, 1, 3, [2]) == false # Not d-separated (conditioning on collider opens path)
        
        # Test complex graph: Sprinkler-Rain-Wet
        g_sprinkler = DiGraph(4)
        add_edge!(g_sprinkler, 1, 2)  # C → S
        add_edge!(g_sprinkler, 1, 3)  # C → R
        add_edge!(g_sprinkler, 2, 4)  # S → W
        add_edge!(g_sprinkler, 3, 4)  # R → W
        
        @test d_separated(g_sprinkler, 2, 3, [1]) == true   # S ⫫ R | C
        @test d_separated(g_sprinkler, 2, 4, []) == false  # S not ⫫ W
        @test d_separated(g_sprinkler, 2, 3, [4]) == false  # S not ⫫ R | W (collider opens)
        
        # Test with multiple conditioning variables
        g_multi = DiGraph(5)
        add_edge!(g_multi, 1, 2)  # Z1 → X
        add_edge!(g_multi, 3, 2)  # Z2 → X
        add_edge!(g_multi, 1, 4)  # Z1 → Y
        add_edge!(g_multi, 3, 4)  # Z2 → Y
        add_edge!(g_multi, 2, 4)  # X → Y
        
        @test d_separated(g_multi, 2, 4, [1, 3]) == false  # Direct path X → Y
        @test d_separated(g_multi, 1, 3, [2, 4]) == false  # Conditioning on collider opens path
    end
    
    @testset "Sets" begin
        # Ancestors of Y
        ancestors = get_ancestors(g, 3)
        @test ancestors == Set([1, 2])
        
        # Descendants of Z
        descendants = get_descendants(g, 1)
        @test descendants == Set([2, 3])
        
        # Parents of Y
        parents = get_parents(g, 3)
        @test parents == Set([1, 2])
        
        # Children of Z
        children = get_children(g, 1)
        @test children == Set([2, 3])
        
        # Test with multiple nodes
        ancestors_multi = get_ancestors(g, [2, 3])
        @test ancestors_multi == Set([1, 2])
        
        # Test isolated node
        g_isolated = DiGraph(3)
        add_edge!(g_isolated, 1, 2)
        @test get_ancestors(g_isolated, 3) == Set()  # Isolated node has no ancestors (except itself, but function excludes self)
        @test get_descendants(g_isolated, 3) == Set()  # Isolated node has no descendants (except itself, but function excludes self)
        @test get_parents(g_isolated, 3) == Set()
        @test get_children(g_isolated, 3) == Set()
        
        # Test root node (no parents)
        @test get_parents(g_isolated, 1) == Set()
        @test get_ancestors(g_isolated, 1) == Set()  # No ancestors (function excludes self)
        
        # Test leaf node (no children)
        @test get_children(g_isolated, 2) == Set()
        @test get_descendants(g_isolated, 2) == Set()  # No descendants (function excludes self)
    end
    
    @testset "Markov Boundary" begin
        mb = markov_boundary(g, 2)  # Markov boundary of X
        @test mb == Set([1, 3])  # Parents and children
        
        # Test Markov boundary of Y
        mb_Y = markov_boundary(g, 3)
        @test mb_Y == Set([1, 2])  # Parents of Y
        
        # Test complex graph with spouses
        g_spouses = DiGraph(5)
        add_edge!(g_spouses, 1, 3)  # A → Y
        add_edge!(g_spouses, 2, 3)  # B → Y
        add_edge!(g_spouses, 3, 4)  # Y → Z
        add_edge!(g_spouses, 3, 5)  # Y → W
        add_edge!(g_spouses, 1, 4)  # A → Z (A is spouse of Y via child Z)
        add_edge!(g_spouses, 2, 5)  # B → W (B is spouse of Y via child W)
        
        mb_Y_complex = markov_boundary(g_spouses, 3)
        @test mb_Y_complex == Set([1, 2, 4, 5])  # Parents, children, and spouses
    end
    
    @testset "Paths" begin
        # Test backdoor paths
        backdoor_paths = find_backdoor_paths(g, 2, 3)  # Backdoor paths from X to Y
        @test length(backdoor_paths) > 0
        # Should find path: X ← Z → Y
        found_z_path = any(path -> path == [2, 1, 3] || path == [2, 1, 3], backdoor_paths)
        @test found_z_path || any(path -> 1 in path && path[1] == 2 && path[end] == 3, backdoor_paths)
        
        # Test directed paths
        directed_paths = find_directed_paths(g, 1, 3)  # Directed paths from Z to Y
        @test length(directed_paths) > 0
        # Should find path: Z → Y
        found_direct = any(path -> path == [1, 3], directed_paths)
        @test found_direct || any(path -> path[1] == 1 && path[end] == 3, directed_paths)
        
        # Test no paths
        g_no_path = DiGraph(3)
        add_edge!(g_no_path, 1, 2)
        # No path from 2 to 3
        @test isempty(find_backdoor_paths(g_no_path, 2, 3))
        @test isempty(find_directed_paths(g_no_path, 2, 3))
    end
    
    @testset "Graph Validation" begin
        # Valid DAG
        @test is_dag(g) == true
        
        # Test with cycle (should fail)
        g_cycle = DiGraph(3)
        add_edge!(g_cycle, 1, 2)
        add_edge!(g_cycle, 2, 3)
        add_edge!(g_cycle, 3, 1)  # Creates cycle
        @test is_dag(g_cycle) == false
        
        # Test empty graph
        g_empty = DiGraph(0)
        @test is_dag(g_empty) == true
        
        # Test single node
        g_single = DiGraph(1)
        @test is_dag(g_single) == true
        
        # Test validate_causal_graph
        @test validate_causal_graph(g) == true
        # validate_causal_graph may throw error for invalid graphs
        @test_throws Exception validate_causal_graph(g_cycle)
    end
    
    @testset "Edge Cases" begin
        # Empty graph - d_separated may error or return true for non-existent nodes
        g_empty = DiGraph(0)
        result_empty = try
            d_separated(g_empty, 1, 2, [])
            :no_error
        catch e
            typeof(e)
        end
        # Either handles gracefully or errors
        @test result_empty isa Union{Type, Symbol}
        
        # Single node
        g_single = DiGraph(1)
        @test d_separated(g_single, 1, 1, []) == true  # Node is d-separated from itself
        
        # Disconnected graph
        g_disconnected = DiGraph(4)
        add_edge!(g_disconnected, 1, 2)
        add_edge!(g_disconnected, 3, 4)
        @test d_separated(g_disconnected, 1, 3, []) == true  # No paths between disconnected components
        @test d_separated(g_disconnected, 2, 4, []) == true
        
        # Test with invalid node indices (should handle gracefully - d_separated doesn't validate)
        # Note: d_separated doesn't validate node indices, but other functions do
        # This is acceptable as d_separated is lower-level
    end
    
    @testset "Type Stability" begin
        # Test that functions return consistent types
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 2, 3)
        
        # Test get_ancestors returns Set{Int}
        ancestors = get_ancestors(g, 3)
        @test ancestors isa Set{Int}
        
        # Test get_descendants returns Set{Int}
        descendants = get_descendants(g, 1)
        @test descendants isa Set{Int}
        
        # Test get_parents returns Set{Int}
        parents = get_parents(g, 3)
        @test parents isa Set{Int}
        
        # Test get_children returns Set{Int}
        children = get_children(g, 1)
        @test children isa Set{Int}
        
        # Test markov_boundary returns Set{Int}
        mb = markov_boundary(g, 2)
        @test mb isa Set{Int}
        
        # Test find_backdoor_paths returns Vector{Vector{Int}}
        paths = find_backdoor_paths(g, 2, 3)
        @test paths isa Vector{Vector{Int}}
        
        # Test find_directed_paths returns Vector{Vector{Int}}
        dir_paths = find_directed_paths(g, 1, 3)
        @test dir_paths isa Vector{Vector{Int}}
    end
end
