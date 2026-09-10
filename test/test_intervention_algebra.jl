@testset "typed intervention algebra" begin
    state = SetState(:A, 1.0; interval = 1:3)
    parameter = ReplaceParameter(:β, "β-v1")
    simultaneous = Simultaneous(state, parameter)
    @test intervention_kind(state) === :state
    @test intervention_kind(parameter) === :parameter
    @test length(simultaneous.interventions) == 2
    @test canonical_intervention(simultaneous) == canonical_intervention(Simultaneous(parameter, state))
    @test_throws InterventionConflict Simultaneous(state, SetState(:A, 2.0))
    sequential = Sequential(SetState(:A, 1.0), SetState(:A, 2.0))
    @test length(sequential.interventions) == 2
    @test_throws InterventionConflict Simultaneous(ReplacePolicy(:A, "π"), state)

    graph = DiGraph(2)
    Graphs.add_edge!(graph, 1, 2)
    scm = GraphSCM(graph, Dict(1 => (u,) -> u, 2 => (x, u) -> x + u), Set([1]))
    transformed = apply_intervention(scm, SetState(2, 3.0))
    @test isempty(Graphs.inneighbors(transformed.graph, 2))
    @test simulate_scm(transformed, Dict(1 => 1, 2 => 2))[2] == 3.0
    @test_throws ArgumentError apply_intervention(scm, ReplaceParameter(:β, "β-v1"))
end
