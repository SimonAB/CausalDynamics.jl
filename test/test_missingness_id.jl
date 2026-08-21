"""Phase 3: Structural missingness certificates (MAR/MNAR claims)."""

using CausalDynamics
using Graphs
using Test

@testset "MissingnessSpec and certify_missingness" begin
    @testset "MCAR identified" begin
        spec = MissingnessSpec(:Y; regime = :mcar)
        cert = certify_missingness(spec)
        @test cert.regime === :mcar
        @test cert.identifiable === true
        @test cert.status === :identified
        @test isempty(cert.mar_set)
        @test cert.response == [:Y]
        @test cert.time_indexed === false
    end

    @testset "MAR with conditioning set" begin
        spec = MissingnessSpec(:Y; regime = :mar, conditioning_set = [:W])
        cert = certify_missingness(spec)
        @test cert.identifiable === true
        @test cert.status === :identified
        @test cert.mar_set == [:W]
        @test :mar in cert.assumptions
    end

    @testset "MAR without conditioning set is unidentified" begin
        spec = MissingnessSpec(:Y; regime = :mar, conditioning_set = Symbol[])
        cert = certify_missingness(spec)
        @test cert.identifiable === false
        @test cert.status === :unidentified
        @test occursin("conditioning", lowercase(cert.note))
    end

    @testset "MNAR without extra assumptions is unidentified" begin
        spec = MissingnessSpec(:Y; regime = :mnar, conditioning_set = [:W])
        cert = certify_missingness(spec)
        @test cert.identifiable === false
        @test cert.status === :unidentified
        @test :mnar in cert.assumptions
        @test occursin("mnar", lowercase(cert.note))
    end

    @testset "time-indexed response" begin
        spec = MissingnessSpec([:Y1, :Y2]; regime = :mar, conditioning_set = [:W], time_indexed = true)
        cert = certify_missingness(spec)
        @test cert.time_indexed === true
        @test cert.response == [:Y1, :Y2]
        @test cert.identifiable === true
    end

    @testset "unknown regime throws" begin
        @test_throws ArgumentError MissingnessSpec(:Y; regime = :foo)
    end
end

@testset "identify with missingness= attaches certificate" begin
    g = DiGraph(3)
    add_edge!(g, 1, 2)  # W → A
    add_edge!(g, 1, 3)  # W → Y
    add_edge!(g, 2, 3)  # A → Y
    names = Dict(1 => :W, 2 => :A, 3 => :Y)
    q = TotalEffectQuery(:A, :Y)

    @testset "default missingness is nothing" begin
        id = identify(g, q; node_names = names)
        @test id.missingness === nothing
        @test id.identifiable === true
    end

    @testset "MAR claim populates certificate" begin
        miss = MissingnessSpec(:Y; regime = :mar, conditioning_set = [:W])
        id = identify(g, q; node_names = names, missingness = miss)
        @test id.missingness isa MissingnessCertificate
        @test id.missingness.identifiable === true
        @test id.missingness.mar_set == [:W]
        @test id.identifiable === true
        d = certificate_dict(id)
        @test haskey(d, :missingness)
        @test d[:missingness].regime === :mar
    end

    @testset "MNAR marks missingness unidentified" begin
        miss = MissingnessSpec(:Y; regime = :mnar)
        id = identify(g, q; node_names = names, missingness = miss)
        @test id.missingness.identifiable === false
        @test id.missingness.status === :unidentified
        # Causal backdoor ID is separate from missingness ID
        @test id.identifiable === true
    end
end
