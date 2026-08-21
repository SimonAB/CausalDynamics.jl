"""Edge cases for Structural / Dynamical missingness APIs."""

using CausalDynamics
using Graphs
using Random
using StableRNGs
using Test

@testset "missingness edge cases (Dynamics)" begin
    @testset "ObservationMask length mismatch" begin
        @test_throws ArgumentError observation_mask(
            Dict(:y => [1.0, missing], :w => [0.0]);
            columns = [:y, :w],
        )
    end

    @testset "ObservationMask empty columns" begin
        @test_throws ArgumentError observation_mask(
            Dict{Symbol, Vector}();
            columns = Symbol[],
        )
    end

    @testset "require_complete_matrix" begin
        X = ones(3, 2)
        @test require_complete_matrix(X) === X
        Xm = Matrix{Union{Float64, Missing}}(X)
        Xm[2, 1] = missing
        @test_throws ArgumentError require_complete_matrix(Xm; context = "assay")
    end

    @testset "apply_observation_mask length" begin
        @test_throws ArgumentError apply_observation_mask([1.0, 2.0], BitVector([true]))
    end

    @testset "MCAR almost none / almost all" begin
        n = 80
        Y = randn(StableRNG(1), n)
        data = Dict(:Y => Y)
        out0, mask0 = apply_missingness_mechanism(
            data, MissingnessSpec(:Y; regime = :mcar);
            intercept = -8.0, rng = StableRNG(2),
        )
        @test miss_rates(mask0)[:Y] < 0.05
        out1, mask1 = apply_missingness_mechanism(
            data, MissingnessSpec(:Y; regime = :mcar);
            intercept = 8.0, rng = StableRNG(3),
        )
        @test miss_rates(mask1)[:Y] > 0.95
        @test count(!ismissing, out1[:Y]) < count(ismissing, out1[:Y])
    end

    @testset "mechanism refuses already-missing / bad keys" begin
        data = Dict(:Y => [1.0, missing], :W => [0.0, 1.0])
        @test_throws ArgumentError apply_missingness_mechanism(
            data, MissingnessSpec(:Y; regime = :mcar); rng = StableRNG(1),
        )
        complete = Dict(:Y => [1.0, 2.0], :W => [0.0, 1.0])
        @test_throws ArgumentError apply_missingness_mechanism(
            complete, MissingnessSpec(:Z; regime = :mcar); rng = StableRNG(1),
        )
        @test_throws ArgumentError apply_missingness_mechanism(
            complete,
            MissingnessSpec(:Y; regime = :mar, conditioning_set = [:Q]);
            rng = StableRNG(1),
        )
    end

    @testset "multi-response joint mask" begin
        n = 30
        data = Dict(
            :Y1 => randn(StableRNG(4), n),
            :Y2 => randn(StableRNG(5), n),
            :W => randn(StableRNG(6), n),
        )
        out, mask = apply_missingness_mechanism(
            data,
            MissingnessSpec([:Y1, :Y2]; regime = :mar, conditioning_set = [:W], time_indexed = true);
            intercept = -0.2, coefficients = Dict(:W => 1.2), rng = StableRNG(7),
        )
        @test mask.time_indexed === true
        @test mask.columns == [:Y1, :Y2]
        for i in 1:n
            # Joint mechanism: both responses missing together
            @test ismissing(out[:Y1][i]) == ismissing(out[:Y2][i])
        end
    end

    @testset "MNAR certificate note and identify separation" begin
        cert = certify_missingness(MissingnessSpec([:Y]; regime = :mnar))
        @test cert.identifiable === false
        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 1, 3)
        add_edge!(g, 2, 3)
        id = identify(
            g, TotalEffectQuery(:A, :Y);
            node_names = Dict(1 => :W, 2 => :A, 3 => :Y),
            missingness = MissingnessSpec(:Y; regime = :mnar),
        )
        @test id.identifiable === true
        @test id.missingness.identifiable === false
    end

    @testset "MAR certificate empty conditioning unidentified" begin
        # Explicit empty set vs default: both unidentified for :mar
        spec = MissingnessSpec([:Y1, :Y2]; regime = :mar, conditioning_set = Symbol[])
        @test certify_missingness(spec).status === :unidentified
    end
end
