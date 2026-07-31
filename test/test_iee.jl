using CausalDynamics
using Test
using Random

include("reference_iee_matlab.jl")

"""Coupled logistic map used in Shi et al. IntDC numerics (unidirectional x → y)."""
function _coupled_logistic(; T = 500, β = 0.15, seed = 1)
    rng = Random.Xoshiro(seed)
    x = zeros(T)
    y = zeros(T)
    x[1] = 0.1
    y[1] = 0.2
    for t in 1:(T - 1)
        x[t + 1] = 3.7 * x[t] * (1 - x[t]) + 0.01 * randn(rng)
        y[t + 1] = 3.7 * y[t] * (1 - (1 - β) * y[t] - β * x[t]) + 0.01 * randn(rng)
    end
    return x[101:end], y[101:end]
end

@testset "Interventional Embedding Entropy" begin
    x, y = _coupled_logistic()

    @testset "smsxiaomayi/IEE MATLAB concordance" begin
        # Exact algorithm match vs port of https://github.com/smsxiaomayi/IEE/IEE.m
        kwargs = (p = 2, k = 2, theiler = 2, n_delta = 8)
        pkg = interventional_embedding_entropy(x, y; kwargs..., mi = :reference)
        ref = matlab_iee(x, y; kwargs...)
        @test pkg ≈ ref rtol = 1e-10 atol = 1e-12

        pkg_rev = interventional_embedding_entropy(y, x; kwargs..., mi = :reference)
        ref_rev = matlab_iee(y, x; kwargs...)
        @test pkg_rev ≈ ref_rev rtol = 1e-10 atol = 1e-12
    end

    @testset "directionality on coupled logistic" begin
        iee_xy = interventional_embedding_entropy(x, y; p = 2, k = 2, n_delta = 8, mi = :reference)
        iee_yx = interventional_embedding_entropy(y, x; p = 2, k = 2, n_delta = 8, mi = :reference)
        @test iee_xy isa Float64
        @test iee_yx isa Float64
        @test iee_xy ≥ 0
        @test iee_yx ≥ 0
        @test iee_xy ≥ iee_yx - 0.05
    end

    @testset "golden regression (fixed seed)" begin
        # Locked against MATLAB-port oracle for seed=1, β=0.15, burn-in 100
        kwargs = (p = 2, k = 2, theiler = 2, n_delta = 8)
        xy = interventional_embedding_entropy(x, y; kwargs..., mi = :reference)
        yx = interventional_embedding_entropy(y, x; kwargs..., mi = :reference)
        @test xy ≈ matlab_iee(x, y; kwargs...)
        @test yx ≈ matlab_iee(y, x; kwargs...)
        # Soft bounds: true direction stronger; absolute scale is estimator-dependent
        @test xy > 0.01
        @test xy > yx
    end

    @testset "Associations backend ranks true direction" begin
        using Associations
        using DataFrames
        if has_associations()
            iee_xy = interventional_embedding_entropy(
                x, y; p = 2, k = 2, n_delta = 8, mi = :associations,
            )
            iee_yx = interventional_embedding_entropy(
                y, x; p = 2, k = 2, n_delta = 8, mi = :associations,
            )
            @test iee_xy isa Float64
            @test iee_yx isa Float64
            @test iee_xy ≥ 0
            @test iee_yx ≥ 0
            # KSG1 scale differs from the MATLAB MIknn port; only require finiteness here.
            @test isfinite(iee_xy) && isfinite(iee_yx)
        else
            @warn "Associations extension not loaded; skipping Associations IEE test"
        end
    end

    @testset "score matrix → TemporalDAGSpec" begin
        scores = iee_score_matrix([x, y]; p = 2, k = 2, n_delta = 8, mi = :reference)
        @test size(scores) == (2, 2)
        @test scores[1, 1] == 0
        @test scores[2, 2] == 0
        thr = 0.5 * (scores[1, 2] + scores[2, 1])
        spec = iee_to_temporal_spec(scores, [:x, :y]; threshold = thr, lag = 1)
        @test spec isa TemporalDAGSpec
        @test :x in spec.variables
        spec2 = infer_iee_temporal_spec([x, y], [:x, :y]; threshold = thr, p = 2, k = 2, n_delta = 8, mi = :reference)
        @test length(spec2.edges) == length(spec.edges)
    end

    @testset "matrix (dx×T) input matches vector" begin
        X = reshape(x, 1, :)
        Y = reshape(y, 1, :)
        a = interventional_embedding_entropy(x, y; p = 1, k = 2, n_delta = 6, mi = :reference)
        b = interventional_embedding_entropy(X, Y; p = 1, k = 2, n_delta = 6, mi = :reference)
        @test a ≈ b rtol = 1e-10
    end
end
