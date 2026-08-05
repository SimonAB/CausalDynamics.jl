using CausalDynamics
using Graphs
using Test

@testset "Identification API" begin
    g = SimpleDiGraph(3)
    add_edge!(g, 1, 2)
    add_edge!(g, 1, 3)
    add_edge!(g, 2, 3)
    names = Dict(1 => :Z, 2 => :X, 3 => :Y)

    q = TotalEffectQuery(:X, :Y)
    res = identify(g, q; node_names = names)
    @test res.identifiable
    @test res.strategy == :backdoor
    @test res.adjustment == [:Z]
    @test res.graph_hash == graph_fingerprint(g)

    conf, ok = prepare_for_tmle(g, 2, 3; node_names = names)
    @test ok
    @test conf == [:Z]

    # Interventional mediation certificate (mediators optional on this tiny graph)
    res_m = identify(
        g, MediationQuery(:X, :Y, Symbol[]; effect_kind = :interventional); node_names = names,
    )
    @test res_m.strategy == :mediation_interventional
    @test isempty(res_m.mediators)

    # Natural with no recanting witness
    g2 = SimpleDiGraph(4)
    add_edge!(g2, 1, 2); add_edge!(g2, 2, 3); add_edge!(g2, 4, 1); add_edge!(g2, 4, 3)
    names2 = Dict(1 => :A, 2 => :M, 3 => :Y, 4 => :W)
    res_n = identify(g2, MediationQuery(:A, :Y, [:M]; effect_kind = :natural); node_names = names2)
    @test res_n.strategy == :mediation_natural

    spec = TemporalDAGSpec([:a, :x], [(:a, :x, 1)])
    u = unroll_temporal_dag(spec, 3)
    tq = TemporalEffectQuery(:a, :x, 1, 2)
    res_t = identify(u, tq)
    @test res_t.strategy == :temporal_backdoor
    @test res_t.identifiable

    report = identification_report(g, 2, 3; node_names = names)
    @test !isempty(report)
    @test any(r -> r.minimal, report)

    resolved = resolve_identification_columns(
        res, IdentityColumnResolver(), [:Z, :X, :Y, :W],
    )
    @test :Z in resolved.adjustment
end
