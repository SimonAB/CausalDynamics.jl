"""
Comprehensive examples using CausalDynamics.jl

This file demonstrates various causal graph operations and identification
algorithms, suitable for use in book chapters.
"""

using CausalDynamics
using Graphs

println("=== CausalDynamics.jl Comprehensive Examples ===\n")

# ============================================================================
# Example 1: d-Separation Patterns
# ============================================================================

println("Example 1: d-Separation Patterns\n")

# Chain pattern: A → B → C
println("Chain Pattern: A → B → C")
g_chain = DiGraph(3)
add_edge!(g_chain, 1, 2)  # A → B
add_edge!(g_chain, 2, 3)  # B → C

println("  A and C d-separated by B: ", d_separated(g_chain, 1, 3, [2]))  # true
println("  A and C d-separated (no conditioning): ", d_separated(g_chain, 1, 3, []))  # false
println()

# Fork pattern: A ← B → C
println("Fork Pattern: A ← B → C")
g_fork = DiGraph(3)
add_edge!(g_fork, 2, 1)  # B → A
add_edge!(g_fork, 2, 3)  # B → C

println("  A and C d-separated by B: ", d_separated(g_fork, 1, 3, [2]))  # true
println("  A and C d-separated (no conditioning): ", d_separated(g_fork, 1, 3, []))  # false
println()

# Collider pattern: A → B ← C
println("Collider Pattern: A → B ← C")
g_collider = DiGraph(3)
add_edge!(g_collider, 1, 2)  # A → B
add_edge!(g_collider, 3, 2)  # C → B

println("  A and C d-separated (no conditioning): ", d_separated(g_collider, 1, 3, []))  # true
println("  A and C d-separated by B: ", d_separated(g_collider, 1, 3, [2]))  # false (collider opens path)
println()

# ============================================================================
# Example 2: Complex d-Separation (Sprinkler-Rain-Wet)
# ============================================================================

println("Example 2: Sprinkler-Rain-Wet Graph\n")

g_sprinkler = DiGraph(4)
add_edge!(g_sprinkler, 1, 2)  # C → S
add_edge!(g_sprinkler, 1, 3)  # C → R
add_edge!(g_sprinkler, 2, 4)  # S → W
add_edge!(g_sprinkler, 3, 4)  # R → W

println("Graph: Climate → Sprinkler → Wet, Climate → Rain → Wet")
println("  S and R d-separated by C: ", d_separated(g_sprinkler, 2, 3, [1]))  # true
println("  S and W d-separated: ", d_separated(g_sprinkler, 2, 4, []))  # false
println("  S and R d-separated by W: ", d_separated(g_sprinkler, 2, 3, [4]))  # false (collider)
println()

# ============================================================================
# Example 3: Backdoor Adjustment
# ============================================================================

println("Example 3: Backdoor Adjustment\n")

# Confounding: Z → X → Y, Z → Y
g_confound = DiGraph(3)
add_edge!(g_confound, 1, 2)  # Z → X
add_edge!(g_confound, 1, 3)  # Z → Y
add_edge!(g_confound, 2, 3)  # X → Y

println("Graph: Z → X → Y, Z → Y")
adj_set = backdoor_adjustment_set(g_confound, 2, 3)
println("  Backdoor adjustment set for X → Y: ", adj_set)  # Set([1]) = {Z}
println("  Is backdoor adjustable: ", is_backdoor_adjustable(g_confound, 2, 3))  # true
println()

# ============================================================================
# Example 4: Frontdoor Adjustment
# ============================================================================

println("Example 4: Frontdoor Adjustment\n")

# Frontdoor: U → X → M → Y, U → Y
g_frontdoor = DiGraph(4)
add_edge!(g_frontdoor, 1, 2)  # U → X
add_edge!(g_frontdoor, 1, 4)  # U → Y
add_edge!(g_frontdoor, 2, 3)  # X → M
add_edge!(g_frontdoor, 3, 4)  # M → Y

println("Graph: U → X → M → Y, U → Y")
is_valid = frontdoor_adjustment_set(g_frontdoor, 2, 4, [3])
println("  M is valid frontdoor adjustment: ", is_valid)  # true
mediators = find_frontdoor_mediators(g_frontdoor, 2, 4)
println("  Frontdoor mediators: ", mediators)  # [Set([3])]
println()

# ============================================================================
# Example 5: Instrumental Variables
# ============================================================================

println("Example 5: Instrumental Variables\n")

# IV: Z → X → Y, U → X, U → Y
g_iv = DiGraph(4)
add_edge!(g_iv, 1, 2)  # Z → X
add_edge!(g_iv, 2, 3)  # X → Y
add_edge!(g_iv, 4, 2)  # U → X
add_edge!(g_iv, 4, 3)  # U → Y

println("Graph: Z → X → Y, U → X, U → Y")
instruments = find_instruments(g_iv, 2, 3)
println("  Valid instruments for X → Y: ", instruments)  # [1] = {Z}
println()

# ============================================================================
# Example 6: Markov Boundary
# ============================================================================

println("Example 6: Markov Boundary\n")

# Complex graph: C → A, C → Y, A → M, A → Y, M → Y, Z → W
g_mb = DiGraph(6)
add_edge!(g_mb, 1, 2)  # C → A
add_edge!(g_mb, 1, 3)  # C → Y
add_edge!(g_mb, 2, 4)  # A → M
add_edge!(g_mb, 2, 3)  # A → Y
add_edge!(g_mb, 4, 3)  # M → Y
add_edge!(g_mb, 5, 6)  # Z → W (unrelated)

println("Graph: C → A, C → Y, A → M, A → Y, M → Y, Z → W")
mb_Y = markov_boundary(g_mb, 3)  # Y
println("  Markov boundary of Y: ", mb_Y)  # Set([1, 2, 4]) = {C, A, M}
println("  Parents of Y: ", get_parents(g_mb, 3))  # Set([1, 2, 4])
println("  Children of Y: ", get_children(g_mb, 3))  # Set()
println()

# ============================================================================
# Example 7: Graph Set Operations
# ============================================================================

println("Example 7: Graph Set Operations\n")

g_sets = DiGraph(4)
add_edge!(g_sets, 1, 2)  # A → B
add_edge!(g_sets, 1, 3)  # A → C
add_edge!(g_sets, 2, 4)  # B → D
add_edge!(g_sets, 3, 4)  # C → D

println("Graph: A → B → D, A → C → D")
println("  Ancestors of D: ", get_ancestors(g_sets, 4))  # Set([1, 2, 3])
println("  Descendants of A: ", get_descendants(g_sets, 1))  # Set([2, 3, 4])
println("  Parents of D: ", get_parents(g_sets, 4))  # Set([2, 3])
println("  Children of A: ", get_children(g_sets, 1))  # Set([2, 3])
println()

println("=== Examples Complete ===")
