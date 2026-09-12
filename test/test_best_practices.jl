using CausalDynamics
using Graphs
using Test
using DataFrames

# Keep only checks that are not already covered by identification / integration tests.
@testset "Best Practices Compliance" begin
    g = DiGraph(3)
    add_edge!(g, 1, 2)
    add_edge!(g, 1, 3)
    add_edge!(g, 2, 3)

    @testset "Error Messages" begin
        data = DataFrame(Z = randn(10), X = rand([0, 1], 10), Y = randn(10))
        node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
        try
            estimate_effect(g, data, 2, 3; node_names = node_names)
        catch e
            error_msg = sprint(showerror, e)
            @test occursin("TMLE", error_msg) || occursin("tmle", lowercase(error_msg))
        end

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
        try
            counterfactual_graph(scm, intervention)
        catch e
            error_msg = sprint(showerror, e)
            @test occursin("not yet implemented", lowercase(error_msg)) ||
                  occursin("counterfactual", lowercase(error_msg))
        end
    end
end
