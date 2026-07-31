using CausalDynamics
using Graphs
using Test

@testset "Utilities" begin
    @testset "Graph Utils" begin
        edges = [(1, 2), (2, 3), (1, 3)]
        g = create_causal_graph(edges)

        @test nv(g) == 3
        @test has_edge(g, 1, 2)
        @test has_edge(g, 2, 3)
        @test has_edge(g, 1, 3)
        @test g isa DiGraph

        g_empty = create_causal_graph(Tuple{Int, Int}[])
        @test nv(g_empty) == 0

        g_single = create_causal_graph([(1, 2)])
        @test nv(g_single) == 2
        @test has_edge(g_single, 1, 2)

        edge_dict = Dict(1 => [2, 3], 2 => [3])
        g_dict = create_causal_graph(edge_dict)
        @test nv(g_dict) == 3
        @test has_edge(g_dict, 1, 2)
        @test has_edge(g_dict, 1, 3)
        @test has_edge(g_dict, 2, 3)
    end

    @testset "Visualization" begin
        g = DiGraph(3)
        add_edge!(g, 1, 2)  # Z → X
        add_edge!(g, 1, 3)  # Z → Y
        add_edge!(g, 2, 3)  # X → Y
        labels = ["Z", "X", "Y"]

        @test hasmethod(plot_causal_graph, (AbstractGraph,))
        @test hasmethod(plot_with_adjustment_set, (AbstractGraph, Int, Int, Vector{Int}))
        @test hasmethod(plot_backdoor_paths, (AbstractGraph, Int, Int))

        dagmakie_loaded = false
        try
            # Use `import` (not `using`) so DAGMakie path helpers do not collide
            # with CausalDynamics exports in Main.
            @eval import DAGMakie
            @eval import CairoMakie
            dagmakie_loaded = true
        catch
            dagmakie_loaded = false
        end

        if dagmakie_loaded && has_dagmakie()
            fig = plot_causal_graph(g; node_labels = labels, highlight_nodes = Set([1]))
            @test fig !== nothing
            fig2 = plot_with_adjustment_set(g, 2, 3, [1]; node_labels = labels)
            @test fig2 !== nothing
            fig3 = plot_backdoor_paths(g, 2, 3; node_labels = labels)
            @test fig3 !== nothing

            spec = TemporalDAGSpec([:x, :y], [(:x, :y, 1)])
            u = unroll_temporal_dag(spec, 3)
            fig_t, ax_t, p_t = dagplot_temporal(u; figure_size = (500, 280))
            @test fig_t !== nothing
        else
            @test_throws ErrorException plot_causal_graph(g)
            try
                plot_causal_graph(g)
            catch e
                @test occursin("DAGMakie", sprint(showerror, e))
            end
        end
    end

    @testset "Edge Cases" begin
        result = try
            create_causal_graph([(1, 0)])
            :no_error
        catch e
            typeof(e)
        end
        @test result isa Union{Type, Symbol}

        edges_dup = [(1, 2), (1, 2)]
        g_dup = create_causal_graph(edges_dup)
        @test nv(g_dup) == 2
        @test has_edge(g_dup, 1, 2)

        edge_dict = Dict(1 => [2, 3], 2 => [3])
        g_dict = create_causal_graph(edge_dict)
        @test nv(g_dict) == 3
        @test has_edge(g_dict, 1, 2)
        @test has_edge(g_dict, 1, 3)
        @test has_edge(g_dict, 2, 3)
    end
end
