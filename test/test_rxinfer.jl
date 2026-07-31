using CausalDynamics
using DataFrames
using Graphs
using Random
using Test

@testset "RxInfer extension" begin
    @test !CausalDynamics.has_rxinfer()

    @test_throws ErrorException CausalDynamics.infer_backdoor_effect(
        DiGraph(2),
        DataFrame(X=[1.0], Y=[1.0]),
        1,
        2,
    )

    # Test target extras install RxInfer; loading activates CausalDynamicsRxInfer
    using RxInfer

    if !CausalDynamics.has_rxinfer()
        @warn "CausalDynamicsRxInfer extension not loaded; skipping RxInfer tests"
    else
        @test CausalDynamics.has_rxinfer()

        Random.seed!(42)
        n = 80
        z = randn(n)
        x = z .+ 0.3 .* randn(n)
        y = 1.5 .* x .+ 0.8 .* z .+ 0.2 .* randn(n)
        data = DataFrame(Z=z, X=x, Y=y)

        g = DiGraph(3)
        add_edge!(g, 1, 2)
        add_edge!(g, 1, 3)
        add_edge!(g, 2, 3)
        names = Dict(1 => :Z, 2 => :X, 3 => :Y)

        result = CausalDynamics.infer_backdoor_effect(g, data, 2, 3; node_names=names, iterations=15)
        @test result.identifiable
        @test result.confounders == [:Z]
        @test result.n == n
        @test result.τ_posterior !== nothing
        @test 0.5 < result.τ_mean < 2.5
        @test result.τ_mean ≈ CausalDynamics.posterior_mean_τ(result.τ_posterior)

        # Empty adjustment set: demeaning still identifies the slope (no-intercept head)
        g0 = DiGraph(2)
        add_edge!(g0, 1, 2)
        Random.seed!(3)
        n0 = 120
        x0 = randn(n0)
        y0 = 2.0 .* x0 .+ 0.25 .* randn(n0)
        r0 = CausalDynamics.infer_backdoor_effect(
            g0, DataFrame(X = x0, Y = y0), 1, 2;
            node_names = Dict(1 => :X, 2 => :Y), iterations = 20,
        )
        @test isempty(r0.confounders)
        @test 1.5 < r0.τ_mean < 2.5

        spec = CausalDynamics.prepare_for_rxinfer(g, 2, 3; node_names=names, data=data)
        ppl_data = CausalDynamics.ppl_data_from_spec(spec)
        @test length(ppl_data.y) == n
        @test ppl_data.n_conf == 1
        @test length(ppl_data.y) == n
    end
end
