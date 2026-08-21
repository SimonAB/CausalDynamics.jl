"""Phase 5: generative MAR masking and encode completeness guards."""

using CausalDynamics
using Random
using StableRNGs
using Test

@testset "apply_missingness_mechanism" begin
    n = 40
    W = randn(StableRNG(1), n)
    Y = 0.5 .* W .+ randn(StableRNG(2), n)
    data = Dict(:W => W, :Y => Y)
    spec = MissingnessSpec(:Y; regime = :mar, conditioning_set = [:W])
    out, mask = apply_missingness_mechanism(
        data, spec; intercept = -0.5, coefficients = Dict(:W => 1.0), rng = StableRNG(3),
    )
    @test mask.time_indexed === false
    @test 0 < miss_rates(mask)[:Y] < 1
    @test any(ismissing, out[:Y])
    @test !any(ismissing, out[:W])
    # observed Y preserved
    for i in 1:n
        if !ismissing(out[:Y][i])
            @test out[:Y][i] == Y[i]
        end
    end
end

@testset "MNAR mechanism refused" begin
    data = Dict(:Y => [1.0, 2.0], :W => [0.0, 1.0])
    @test_throws ArgumentError apply_missingness_mechanism(
        data, MissingnessSpec(:Y; regime = :mnar); rng = StableRNG(1),
    )
end

@testset "simulate_incomplete_panel" begin
    cdm = DiscreteTimeCDM(
        [:a, :y];
        initialise = (rng) -> (a = 0.0, y = 0.0),
        sample_noise = (rng, state, t) -> (u_a = randn(rng), u_y = randn(rng)),
        step = (state, t, noise, intervention) -> begin
            a = 0.5 * state.a + noise.u_a
            y = 2a + noise.u_y
            (a = a, y = y)
        end,
    )
    incomplete, mask, panel = simulate_incomplete_panel(
        cdm, 25, 2;
        missingness = MissingnessSpec(:y; regime = :mcar),
        intercept = 0.0,
        baseline = Symbol[],
        timed = [:a],
        terminal = [:y],
        rng = StableRNG(9),
        rng_missing = StableRNG(10),
    )
    @test panel isa CDMPanel
    @test haskey(incomplete, :y)
    @test miss_rates(mask)[:y] > 0.15
    @test count(ismissing, incomplete[:y]) > 0
end

@testset "encode_to_panel rejects Missing" begin
    X = Matrix{Union{Float64, Missing}}(randn(StableRNG(8), 10, 4))
    X[1, 1] = missing
    spec = RepresentationSpec(:S, [:z1], S -> S[:, 1:1])
    @test_throws ArgumentError encode_to_panel(X, spec)
end
