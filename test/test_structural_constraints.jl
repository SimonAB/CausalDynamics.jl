@testset "structural constraint declarations" begin
    constraint = StructuralConstraintSpec(
        :regenerative_morphology,
        [:bioelectric_state, :morphology];
        kind = :viability,
        claim = "Perturbed tissue can return to a viable morphological region.",
        predictions = [:return_after_damage],
        test_ids = [:damage_recovery],
        embodiments = [:planarian, :anthrobot],
    )

    @test constraint.id === :regenerative_morphology
    @test constraint.targets == [:bioelectric_state, :morphology]
    @test constraint.kind === :viability
    @test constraint.predictions == [:return_after_damage]

    certificate = constraint_certificate(constraint)
    @test certificate.id === constraint.id
    @test certificate.kind === constraint.kind
    @test certificate.targets == constraint.targets
    @test certificate.claim == constraint.claim
    @test certificate.predictions == constraint.predictions
    @test certificate.test_ids == constraint.test_ids
    @test certificate.embodiments == constraint.embodiments
    @test certificate.fingerprint isa UInt64
    @test certificate == constraint_certificate(constraint)

    equivalent = StructuralConstraintSpec(
        :regenerative_morphology,
        [:bioelectric_state, :morphology];
        kind = :viability,
        claim = "Perturbed tissue can return to a viable morphological region.",
        predictions = [:return_after_damage],
        test_ids = [:damage_recovery],
        embodiments = [:planarian, :anthrobot],
    )
    @test constraint_certificate(equivalent).fingerprint == certificate.fingerprint

    @test_throws ArgumentError StructuralConstraintSpec(
        :invalid_kind, [:x]; kind = :attractor, claim = "A claim.")
    @test_throws ArgumentError StructuralConstraintSpec(
        :missing_targets, Symbol[]; claim = "A claim.")
    @test_throws ArgumentError StructuralConstraintSpec(
        :blank_claim, [:x]; claim = "   ")
    @test_throws ArgumentError StructuralConstraintSpec(
        Symbol(""), [:x]; claim = "A claim.")
    @test_throws ArgumentError StructuralConstraintSpec(
        :duplicate_predictions, [:x]; claim = "A claim.", predictions = [:p, :p])
end
