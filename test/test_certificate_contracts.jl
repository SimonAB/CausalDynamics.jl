@testset "versioned certificate and intervention contracts" begin
    d₁ = InterventionDescriptor(:A; replacement = :constant, replacement_id = "1")
    d₂ = InterventionDescriptor(:B; replacement = :constant, replacement_id = "2")
    bundle = compose_intervention_bundle(d₁, d₂)
    @test bundle.mode === :simultaneous
    @test bundle.descriptors == [d₁, d₂]
    @test_throws ArgumentError compose_intervention_bundle(d₁, d₁)
    @test_throws ArgumentError compose_intervention_bundle(d₁; mode = :invalid)

    provenance = CDMProvenance(
        graph = "g-1", mechanisms = "f-1", observation = "h-1", policy = "π-1",
        exogenous = "u-1", intervention = bundle,
    )
    certificate = certificate_envelope(provenance; environment = (julia = VERSION,))
    encoded = certificate_dict(certificate)
    @test encoded["schema_version"] == "cdcs.certificate.v1"
    @test encoded["semantic"]["graph"] == "g-1"
    @test encoded["environment"][:julia] == VERSION
end
