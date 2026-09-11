using Test
using LinearAlgebra

@testset "Boosted control function" begin
    n = 80
    z = collect(range(-2.0, 2.0; length=n))
    v₁ = sin.(range(0.0, 4π; length=n))
    v₂ = cos.(range(0.0, 4π; length=n))
    X = hcat(z .+ v₁, v₂)
    Y = 1.5 .* X[:, 1] .+ 0.7 .* v₁ .+ 0.2 .* v₂
    Z = reshape(z, :, 1)

    fit = boosted_control_function(X, Y, Z)

    @test fit isa BoostedControlFunctionFit
    @test size(fit.M) == (2, 1)
    @test size(fit.V) == size(X)
    @test size(fit.R, 1) == 2
    @test length(CausalDynamics.predict(fit, X)) == n
    @test all(isfinite, CausalDynamics.predict(fit, X))
end

@testset "Boosted control function validation" begin
    @test_throws DimensionMismatch boosted_control_function(randn(4, 2), randn(3), randn(4, 1))
    @test_throws ArgumentError boosted_control_function(randn(4, 2), randn(4), zeros(4, 1))
end
