@testset "Frontdoor via CausalInference" begin
    # CausalInference gensearch fixtures (g1, g2)
    g1 = SimpleDiGraph(Edge.([(1, 2), (2, 3), (3, 4), (5, 1), (6, 5), (6, 4), (1, 7)]))
    g2 = SimpleDiGraph(Edge.([(1, 3), (3, 6), (2, 5), (5, 8), (6, 7), (7, 8), (1, 4), (2, 4), (4, 6), (4, 8)]))

    @test find_frontdoor_adjustment_set(g1, 1, 4) == Set([2, 3, 7])
    @test find_min_frontdoor_adjustment_set(g1, 1, 4) == Set([3])
    @test Set(list_frontdoor_adjustment_sets(g1, 1, 4)) == Set([
        Set([3]),
        Set([7, 2]),
        Set([7, 2, 3]),
        Set([7, 3]),
        Set([2]),
        Set([2, 3]),
    ])

    @test find_frontdoor_adjustment_set(g2, 6, 8) == Set([7])
    @test find_min_frontdoor_adjustment_set(g2, 6, 8) == Set([7])
    @test Set(list_frontdoor_adjustment_sets(g2, 6, 8)) == Set([Set([7])])

    # Canonical textbook frontdoor
    g_canon = DiGraph(4)
    add_edge!(g_canon, 1, 2)
    add_edge!(g_canon, 1, 4)
    add_edge!(g_canon, 2, 3)
    add_edge!(g_canon, 3, 4)
    @test frontdoor_adjustment_set(g_canon, 2, 4, [3])
    @test find_frontdoor_mediators(g_canon, 2, 4) == [Set([3])]
    @test Set(find_frontdoor_mediators(g1, 1, 4)) == Set([Set([2]), Set([3])])

    # Prior reachability shortcut rejected this; CI accepts {3,4}
    g_joint = SimpleDiGraph(Edge.([(1, 3), (1, 4), (3, 2), (4, 2), (4, 3)]))
    @test frontdoor_adjustment_set(g_joint, 1, 2, [3, 4])
    @test find_frontdoor_adjustment_set(g_joint, 1, 2) == Set([3, 4])

    # Prior reachability shortcut accepted {4} with no X→Y path; CI rejects {4}
    g_vacuous = SimpleDiGraph(Edge.([(1, 3), (2, 3), (4, 2)]))
    @test !frontdoor_adjustment_set(g_vacuous, 3, 2, [4])
    @test find_frontdoor_adjustment_set(g_vacuous, 3, 2) == Set{Int}()

    # U → M breaks single-node frontdoor
    g_invalid = DiGraph(5)
    add_edge!(g_invalid, 1, 2)
    add_edge!(g_invalid, 1, 4)
    add_edge!(g_invalid, 2, 3)
    add_edge!(g_invalid, 3, 4)
    add_edge!(g_invalid, 1, 3)
    @test !frontdoor_adjustment_set(g_invalid, 2, 4, [3])
end
