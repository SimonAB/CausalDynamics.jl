@testset "exact finite-law causal abstraction" begin
    law = FiniteLaw([:a, :b, :a], [0.2, 0.3, 0.5])
    @test support(law) == [:a, :b]
    @test probabilities(law) ≈ [0.7, 0.3]

    pushed = pushforward(x -> x == :a ? :left : :right, law)
    @test support(pushed) == [:left, :right]
    @test probabilities(pushed) ≈ [0.7, 0.3]

    spec = CausalAbstractionSpec(x -> x == 0 ? :low : :high, identity;
        interventions = [:do0], law_mode = :exact)
    result = validate_abstraction(spec,
        Dict(:do0 => FiniteLaw([0, 1], [0.25, 0.75])),
        Dict(:do0 => FiniteLaw([:low, :high], [0.25, 0.75])))
    @test result.exact
    @test result.accepted
    @test result.failed_interventions == Symbol[]

    @test_throws ArgumentError FiniteLaw([:a], [-1.0])
    @test_throws ArgumentError CausalAbstractionSpec(identity, identity;
        interventions = [:x], law_mode = :invalid)
end
