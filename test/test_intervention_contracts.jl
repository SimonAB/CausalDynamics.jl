"""Behavioural tests for typed intervention and abstraction contracts."""

@testset "typed intervention contract" begin
    descriptor = InterventionDescriptor(
        :action;
        replacement = :constant,
        interval = 2:4,
        scope = :unit,
        stochasticity = :deterministic,
        cointerventions = [:measurement],
    )

    @test descriptor.target == :action
    @test descriptor.interval == 2:4
    @test descriptor.cointerventions == [:measurement]
    @test intervention_descriptor(do_sequence(:action, [0.0, 1.0]))[1].target == :action
    continuous = continuous_interventions(do_pin(:state, 1.0), do_rhs(:state, (u, p, t) -> 0.0))
    @test length(intervention_descriptor(continuous; replacement_ids = Dict(:state => "rhs-v1"))) == 2

    integer_descriptor = intervention_descriptor(do_intervention(2, 1.0))
    changed_value = intervention_descriptor(do_intervention(2, 2.0))
    @test integer_descriptor.target == 2
    @test canonical_intervention_descriptor(integer_descriptor) !=
          canonical_intervention_descriptor(changed_value)
    @test_throws ArgumentError compose_intervention_descriptors(
        InterventionDescriptor(:action), InterventionDescriptor(:action))
    @test_throws ArgumentError InterventionDescriptor(:rule; replacement = :policy)
    @test_throws ArgumentError InterventionDescriptor(:graph; replacement = :topology)
    @test InterventionDescriptor(:graph; replacement = :topology,
        replacement_id = "G-v2").replacement == :topology
    @test canonical_intervention_descriptor(intervention_descriptor(do_pin(:x, 1.0))) !=
          canonical_intervention_descriptor(intervention_descriptor(do_pin(:x, 2.0)))
    @test canonical_intervention_descriptor(intervention_descriptor(do_ic(:x, 1.0))) !=
          canonical_intervention_descriptor(intervention_descriptor(do_ic(:x, 2.0)))
    @test canonical_intervention_descriptor(intervention_descriptor(do_force(:x, 1.0; κ = 0.1))) !=
          canonical_intervention_descriptor(intervention_descriptor(do_force(:x, 1.0; κ = 0.2)))
    @test_throws ArgumentError intervention_descriptor(policy(:a, (state, t) -> 0.0))
    @test_throws ArgumentError intervention_descriptor(do_rhs(:x, (u, p, t) -> 0.0))
    @test canonical_intervention_descriptor(InterventionDescriptor(
        :x; cointerventions = [:a_b, :c])) != canonical_intervention_descriptor(
        InterventionDescriptor(:x; cointerventions = [:a, :b_c]))
end

@testset "causal abstraction contract" begin
    τ = x -> sum(x)
    ω = i -> i
    spec = CausalAbstractionSpec(τ, ω; interventions = [:control], tolerance = 0.0)
    exact = validate_abstraction(spec, Dict(:control => [1.0, 2.0]), Dict(:control => 3.0))
    failed = validate_abstraction(spec, Dict(:control => [1.0, 2.0]), Dict(:control => 2.0))

    @test exact.exact
    @test exact.accepted
    @test exact.discrepancy == 0.0
    @test !failed.exact
    @test !failed.accepted
    @test failed.discrepancy == 1.0
    within_tolerance = validate_abstraction(
        CausalAbstractionSpec(τ, ω; interventions = [:control], tolerance = 1.0),
        Dict(:control => [1.0, 2.0]), Dict(:control => 2.0),
    )
    @test !within_tolerance.exact
    @test within_tolerance.accepted
    @test_throws ArgumentError CausalAbstractionSpec(τ, ω; interventions = Symbol[])
    @test_throws ArgumentError validate_abstraction(
        CausalAbstractionSpec(τ, ω; interventions = [:control], distance = (x, y) -> NaN),
        Dict(:control => [1.0]), Dict(:control => 1.0),
    )
    @test_throws ArgumentError validate_abstraction(
        CausalAbstractionSpec(τ, ω; interventions = [:a, :b], distance = (x, y) -> x),
        Dict(:a => -1.0, :b => 1.0), Dict(:a => 0.0, :b => 0.0),
    )
end

@testset "provenance fingerprints are semantic" begin
    base = CDMProvenance(
        graph = "G1", mechanisms = "F1", observation = "h1",
        policy = "π1", exogenous = "U1", intervention = "i1",
    )
    changed = CDMProvenance(
        graph = "G2", mechanisms = "F1", observation = "h1",
        policy = "π1", exogenous = "U1", intervention = "i1",
    )

    @test provenance_fingerprint(base) != provenance_fingerprint(changed)
    @test provenance_dict(base)["observation"] == "h1"
    for component in (:mechanisms, :observation, :policy, :exogenous, :intervention,
                      :scale_map, :numerical, :coupling)
        kwargs = Dict{Symbol, Any}(
            :graph => "G1", :mechanisms => "F1", :observation => "h1",
            :policy => "π1", :exogenous => "U1", :intervention => "i1",
            :scale_map => "s1", :numerical => "n1", :coupling => "c1",
        )
        kwargs[component] = "changed"
        @test provenance_fingerprint(base) != provenance_fingerprint(CDMProvenance(; kwargs...))
    end
    for component in (:estimand, :identification, :estimator, :positivity, :sensitivity)
        kwargs = Dict{Symbol, Any}(
            :graph => "G1", :mechanisms => "F1", :observation => "h1",
            :policy => "π1", :exogenous => "U1", :intervention => "i1",
        )
        kwargs[component] = "changed"
        @test provenance_fingerprint(base) != provenance_fingerprint(CDMProvenance(; kwargs...))
    end
    descriptor_provenance = CDMProvenance(
        graph = "G1", mechanisms = "F1", observation = "h1", policy = "π1",
        exogenous = "U1", intervention = intervention_descriptor(do_intervention(1, 1.0)),
    )
    changed_descriptor_provenance = CDMProvenance(
        graph = "G1", mechanisms = "F1", observation = "h1", policy = "π1",
        exogenous = "U1", intervention = intervention_descriptor(do_intervention(1, 2.0)),
    )
    @test provenance_fingerprint(descriptor_provenance) !=
          provenance_fingerprint(changed_descriptor_provenance)
end

@testset "g-computation carries declared provenance" begin
    cdm = DiscreteTimeCDM(
        [:a, :y];
        initialise = rng -> (a = 0.0, y = 0.0),
        sample_noise = (rng, state, t) -> (u = 0.0,),
        step = (state, t, noise, intervention) -> begin
            a = intervention_value(intervention, :a, t, 0.0, state)
            (a = a, y = a)
        end,
    )
    provenance = CDMProvenance(
        graph = "g", mechanisms = "f", observation = "h", policy = "π",
        exogenous = "u", intervention = "do-a",
    )
    result = g_computation(cdm, 3, :y; intervention = do_sequence(:a, 1.0), n = 4,
        provenance = provenance)

    @test result.provenance === provenance
end
