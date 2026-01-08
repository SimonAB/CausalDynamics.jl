"""
Basic identification examples using CausalDynamics.jl

This example demonstrates:
- d-separation testing
- Backdoor adjustment
- Frontdoor adjustment
- Instrumental variables
"""

using CausalDynamics
using Graphs

println("=== CausalDynamics.jl Basic Examples ===\n")

# Example 1: Confounding (Backdoor adjustment)
println("Example 1: Confounding")
g1 = DiGraph(3)
add_edge!(g1, 1, 2)  # Z → X
add_edge!(g1, 1, 3)  # Z → Y
add_edge!(g1, 2, 3)  # X → Y

println("Graph: Z → X → Y, Z → Y")
println("d-separated(X, Y | Z): ", d_separated(g1, 2, 3, [1]))
adj_set = backdoor_adjustment_set(g1, 2, 3)
println("Backdoor adjustment set: ", adj_set)
println()

# Example 2: Mediation (Frontdoor)
println("Example 2: Mediation with Confounding")
g2 = DiGraph(4)
add_edge!(g2, 1, 2)  # U → X
add_edge!(g2, 1, 4)  # U → Y
add_edge!(g2, 2, 3)  # X → M
add_edge!(g2, 3, 4)  # M → Y

println("Graph: U → X → M → Y, U → Y")
is_frontdoor = frontdoor_adjustment_set(g2, 2, 4, [3])
println("M is valid frontdoor adjustment: ", is_frontdoor)
println()

# Example 3: Instrumental Variable
println("Example 3: Instrumental Variable")
g3 = DiGraph(4)
add_edge!(g3, 1, 2)  # Z → X
add_edge!(g3, 2, 3)  # X → Y
add_edge!(g3, 4, 2)  # U → X
add_edge!(g3, 4, 3)  # U → Y

println("Graph: Z → X → Y, U → X, U → Y")
instruments = find_instruments(g3, 2, 3)
println("Valid instruments: ", instruments)
println()

println("=== Examples Complete ===")
