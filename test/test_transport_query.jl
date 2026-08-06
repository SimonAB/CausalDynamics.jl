using CausalDynamics
using Test
using Graphs

@testset "TransportQuery identification" begin
    g = DiGraph(4)
    add_edge!(g, 1, 2)  # C → A
    add_edge!(g, 1, 3)  # C → Y
    add_edge!(g, 2, 3)  # A → Y
    add_edge!(g, 4, 2)  # D → A (domain)
    add_edge!(g, 4, 3)  # D → Y
    names = Dict(1 => :C, 2 => :A, 3 => :Y, 4 => :D)

    id = identify(
        g,
        TransportQuery(:A, :Y, [:D]; source = :source, target = :target);
        node_names = names,
    )
    @test id.strategy === :transport_backdoor
    @test id.identifiable
    @test :D in id.adjustment
    @test :C in id.adjustment || :D in id.adjustment
    @test :transportability in id.assumptions
    @test id.query isa TransportQuery
    @test id.query.source === :source
    @test id.query.target === :target
end
