"""
    counterfactual_graph(scm::GraphSCM, intervention::DoIntervention)

Generate a counterfactual (twin-network) graph for reasoning about what
would have happened under an alternative intervention, for the same unit.

Counterfactual reasoning requires three steps (Pearl 2009, Chapter 7):
1. **Abduction**: Infer exogenous noise values U from observed evidence
2. **Action**: Apply the intervention to create the mutilated model
3. **Prediction**: Simulate the mutilated model with the same U

This function performs step 2 — creating the mutilated SCM that shares
the same exogenous noise structure as the original.

# Arguments
- `scm::GraphSCM`: Original Structural Causal Model
- `intervention::DoIntervention`: Intervention for the counterfactual world

# Returns
- `GraphSCM`: Mutilated SCM (identical to `apply_intervention` output, but
  semantically used for counterfactual reasoning with shared exogenous noise)

# Examples

```julia
using CausalDynamics, Graphs

# SCM: Z → X → Y
g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 2, 3)

equations = Dict{Int, Function}(
    1 => (u) -> u,
    2 => (z, u) -> z + u,
    3 => (x, u) -> 2x + u
)

scm = GraphSCM(g, equations, Set{Int}())

# Step 1: Abduction — infer U from observations
U_observed = Dict(1 => 1.0, 2 => 0.5, 3 => -0.3)

# Step 2: Action — create counterfactual graph
intervention = do_intervention(2, 10.0)  # What if X had been 10?
scm_cf = counterfactual_graph(scm, intervention)

# Step 3: Prediction — simulate with SAME exogenous noise
factual = simulate_scm(scm, U_observed)
counterfactual = simulate_scm(scm_cf, U_observed)

# factual[3]      = 2 * (1.0 + 0.5) + (-0.3) = 2.7
# counterfactual[3] = 2 * 10.0 + (-0.3) = 19.7
```

# Notes
- **Shared exogenous noise**: The key to counterfactual reasoning is using
  the SAME exogenous noise realisation U for both factual and counterfactual worlds.
  This ensures we reason about the same unit (individual/occasion).
- For deterministic SCMs, abduction is straightforward (solve for U).
- For stochastic SCMs, abduction requires posterior inference P(U | evidence).
- The returned SCM is structurally identical to `apply_intervention(scm, intervention)`,
  but the semantic intent is different: counterfactual (same U) vs interventional
  (marginalising over U).

# References
- Pearl, J. (2009). *Causality*, Chapter 7
- Shpitser, I., & Pearl, J. (2009). Complete identification methods for the causal hierarchy

# See Also
- `apply_intervention`: Apply intervention (for interventional reasoning)
- `simulate_scm`: Simulate SCM forward given exogenous noise
- `compute_counterfactual`: Full counterfactual computation (abduction + action + prediction)
"""
function counterfactual_graph(scm::GraphSCM, intervention::DoIntervention)
    return apply_intervention(scm, intervention)
end

"""
    compute_counterfactual(scm::GraphSCM, intervention::DoIntervention,
                           exogenous_values::Dict{Int, <:Any})

Perform full counterfactual computation: given an SCM, an intervention,
and the exogenous noise realisation for a specific unit, compute both
the factual and counterfactual outcomes.

This implements Pearl's three-step procedure:
1. **Abduction**: Use provided exogenous values (assumed already inferred)
2. **Action**: Create mutilated model via `counterfactual_graph`
3. **Prediction**: Simulate both factual and counterfactual worlds

# Arguments
- `scm::GraphSCM`: Original Structural Causal Model
- `intervention::DoIntervention`: Counterfactual intervention
- `exogenous_values::Dict{Int, <:Any}`: Exogenous noise values for this unit

# Returns
- `NamedTuple{(:factual, :counterfactual)}`: Named tuple with:
  - `factual::Dict{Int, Any}`: Values under the original SCM
  - `counterfactual::Dict{Int, Any}`: Values under the counterfactual intervention

# Examples

```julia
using CausalDynamics, Graphs

g = DiGraph(3)
add_edge!(g, 1, 2)
add_edge!(g, 2, 3)

equations = Dict{Int, Function}(
    1 => (u) -> u,
    2 => (z, u) -> z + u,
    3 => (x, u) -> 2x + u
)

scm = GraphSCM(g, equations, Set{Int}())
U = Dict(1 => 1.0, 2 => 0.5, 3 => -0.3)

result = compute_counterfactual(scm, do_intervention(2, 10.0), U)
result.factual[3]       # 2.7
result.counterfactual[3] # 19.7
```
"""
function compute_counterfactual(scm::GraphSCM, intervention::DoIntervention,
                                 exogenous_values::Dict{Int, T}) where T
    factual = simulate_scm(scm, exogenous_values)
    scm_cf = counterfactual_graph(scm, intervention)
    counterfactual = simulate_scm(scm_cf, exogenous_values)
    return (factual=factual, counterfactual=counterfactual)
end

export counterfactual_graph, compute_counterfactual
