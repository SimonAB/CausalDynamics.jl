# TMLE.jl Integration Example
#
# This example demonstrates how to use CausalDynamics.jl with TMLE.jl
# for complete causal inference workflow: identification → estimation

using CausalDynamics
using Graphs
using DataFrames
using Random

# For this example, we'll simulate data
# In practice, you would load your own data
Random.seed!(123)

# ============================================================================
# Example 1: Basic Integration
# ============================================================================

println("=" ^ 60)
println("Example 1: Basic Integration")
println("=" ^ 60)

# Create causal graph: Z → X → Y, Z → Y (confounding)
# Nodes: 1=Z, 2=X, 3=Y
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Check identifiability
adj_set = backdoor_adjustment_set(g, 2, 3)
println("Backdoor adjustment set: ", adj_set)  # Should be Set([1]) = {Z}

# Prepare for TMLE.jl
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
confounders, identifiable = prepare_for_tmle(g, 2, 3; node_names=node_names)
println("Confounders for TMLE: ", confounders)  # Should be [:Z]
println("Is identifiable: ", identifiable)  # Should be true

# Simulate data (in practice, use your own data)
n = 1000
data = DataFrame(
    Z = randn(n),
    X = rand([0, 1], n),
    Y = randn(n)
)

# Note: To actually run TMLE, you would need:
# using TMLE
# result = estimate_effect(g, data, 2, 3; node_names=node_names)
# or
# result = TMLE.tmle(data, treatment=:X, outcome=:Y, confounders=confounders)

println("\nData prepared for TMLE estimation:")
println("Treatment: :X")
println("Outcome: :Y")
println("Confounders: ", confounders)

# ============================================================================
# Example 2: No Confounding
# ============================================================================

println("\n" * "=" ^ 60)
println("Example 2: No Confounding (X → Y only)")
println("=" ^ 60)

g2 = DiGraph(2)
add_edge!(g2, 1, 2)  # X → Y only

adj_set2 = backdoor_adjustment_set(g2, 1, 2)
println("Backdoor adjustment set: ", adj_set2)  # Should be empty

node_names2 = Dict(1 => :X, 2 => :Y)
confounders2, identifiable2 = prepare_for_tmle(g2, 1, 2; node_names=node_names2)
println("Confounders for TMLE: ", confounders2)  # Should be []
println("Is identifiable: ", identifiable2)  # Should be true (no adjustment needed)

# ============================================================================
# Example 3: Multiple Confounders
# ============================================================================

println("\n" * "=" ^ 60)
println("Example 3: Multiple Confounders")
println("=" ^ 60)

# Graph: Z1 → X → Y, Z2 → X → Y, Z1 → Y, Z2 → Y
g3 = DiGraph(4)
add_edge!(g3, 1, 2)  # Z1 → X
add_edge!(g3, 3, 2)  # Z2 → X
add_edge!(g3, 1, 4)  # Z1 → Y
add_edge!(g3, 3, 4)  # Z2 → Y
add_edge!(g3, 2, 4)  # X → Y

adj_set3 = backdoor_adjustment_set(g3, 2, 4)
println("Backdoor adjustment set: ", adj_set3)  # Should include Z1 and/or Z2

node_names3 = Dict(1 => :Z1, 2 => :X, 3 => :Z2, 4 => :Y)
confounders3, identifiable3 = prepare_for_tmle(g3, 2, 4; node_names=node_names3)
println("Confounders for TMLE: ", confounders3)
println("Is identifiable: ", identifiable3)

# ============================================================================
# Example 4: Using get_tmle_confounders
# ============================================================================

println("\n" * "=" ^ 60)
println("Example 4: Using get_tmle_confounders (convenience function)")
println("=" ^ 60)

confounders4 = get_tmle_confounders(g, 2, 3; node_names=node_names)
println("Confounders: ", confounders4)  # Just the confounders, no identifiability check

println("\n" * "=" ^ 60)
println("Integration examples complete!")
println("=" ^ 60)
println("\nTo use with TMLE.jl, load it and call:")
println("  using TMLE")
println("  result = estimate_effect(g, data, 2, 3; node_names=node_names)")
println("  # or")
println("  result = TMLE.tmle(data, treatment=:X, outcome=:Y, confounders=confounders)")
