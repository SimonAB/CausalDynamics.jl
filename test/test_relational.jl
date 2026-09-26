@testset "Relational schema grounding" begin
    schema = RelationalSchema(
        [:signal, :car, :pedestrian],
        Dict(:controls => (:signal, :car), :path => (:pedestrian, :car)),
        Dict(
            :signal => [:walk],
            :car => [:brake],
            :pedestrian => [:cross],
        ),
    )
    skeleton = RelationalSkeleton(
        schema,
        Dict(
            :signal => [:s1],
            :car => [:c1, :c2],
            :pedestrian => [:p1],
        ),
        Dict(
            :controls => [(:s1, :c1)],
            :path => [(:p1, :c1)],
        ),
    )

    @test relational_entities(skeleton, :car) == [:c1, :c2]
    @test relational_attributes(schema, :car) == [:brake]

    grounded = ground_relational_graph(skeleton, [
        RelationalParent(:signal, :walk, :car, :brake, :controls),
        RelationalParent(:pedestrian, :cross, :car, :brake, :path),
    ])

    @test length(grounded.node_labels) == 4
    @test grounded.node_labels[1] == (:signal, :s1, :walk)
    @test has_edge(grounded.graph, 1, 2)
    @test has_edge(grounded.graph, 4, 2)
    @test !has_edge(grounded.graph, 1, 3)

    @test_throws ArgumentError RelationalSkeleton(
        schema,
        Dict(:signal => [:s1], :car => [:c1, :c2], :pedestrian => [:p1]),
        Dict(:controls => [(:s2, :c1)]),
    )
    @test_throws ArgumentError RelationalSkeleton(
        schema,
        Dict(:signal => [:s1], :car => [:c1, :c2], :pedestrian => [:p1], :dog => [:d1]),
        Dict{Symbol, Vector{Tuple}}(),
    )
end
