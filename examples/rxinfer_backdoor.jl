#!/usr/bin/env julia
# Backdoor identification (CausalDynamics) + GraphPPL/RxInfer variational inference.
using Pkg
Pkg.activate(dirname(@__DIR__))

using CausalDynamics
using DataFrames
using Graphs
using Random
if !CausalDynamics.has_rxinfer()
    @info "Loading RxInfer to activate CausalDynamicsRxInfer extension..."
    using RxInfer
end

@assert CausalDynamics.has_rxinfer() "Run: using RxInfer after CausalDynamics"

Random.seed!(42)
n = 200
z = randn(n)
x = z .+ 0.4 .* randn(n)
y = 2.0 .* x .+ z .+ 0.3 .* randn(n)
data = DataFrame(Z=z, X=x, Y=y)

g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y
names = Dict(1 => :Z, 2 => :X, 3 => :Y)

println("=== CausalDynamics → GraphPPL → RxInfer ===")
spec = CausalDynamics.prepare_for_rxinfer(g, 2, 3; node_names=names, data=data)
println("Treatment: ", spec.treatment, "  Outcome: ", spec.outcome)
println("Confounders: ", spec.confounders, "  Identifiable: ", spec.is_identifiable)

result = CausalDynamics.infer_backdoor_effect(g, data, 2, 3; node_names=names, iterations=30)
println("n = ", result.n)
println("τ posterior mean ≈ ", round(result.τ_mean, digits=3), " (simulated τ ≈ 2.0)")
