# Integration with TMLE.jl

CausalDynamics.jl is designed to work seamlessly with [TMLE.jl](https://github.com/TARGENE/TMLE.jl) for complete causal inference workflows. CausalDynamics.jl handles **identification** (determining what to adjust for), while TMLE.jl handles **estimation** (computing causal effects from data).

## Workflow

The typical workflow is:

1. **Identify adjustment set** using CausalDynamics.jl
2. **Estimate causal effect** using TMLE.jl with the identified adjustment set

## Basic Integration

### Step 1: Identify Adjustment Set

```julia
using CausalDynamics, Graphs

# Create causal graph: Z → X → Y, Z → Y
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Find backdoor adjustment set
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1]) = {Z}
```

### Step 2: Prepare for TMLE.jl

```julia
# Map node indices to variable names
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)

# Prepare confounders for TMLE.jl
confounders, identifiable = prepare_for_tmle(g, 2, 3; node_names=node_names)
# Returns: ([:Z], true)
```

### Step 3: Estimate Effect

```julia
using TMLE, DataFrames

# Load your data
data = DataFrame(
    Z = [...],
    X = [...],
    Y = [...]
)

# Estimate effect using TMLE
result = TMLE.tmle(
    data,
    treatment=:X,
    outcome=:Y,
    confounders=confounders  # [:Z] from step 2
)
```

## Convenience Functions

### `estimate_effect`: All-in-One

The `estimate_effect` function combines identification and estimation:

```julia
using CausalDynamics, TMLE, DataFrames

# Create graph and data
g = create_causal_graph([(1, 2), (1, 3), (2, 3)])
data = DataFrame(Z=[...], X=[...], Y=[...])

# Identify and estimate in one step
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
result = estimate_effect(g, data, 2, 3; node_names=node_names)
```

### `get_tmle_confounders`: Quick Confounder Extraction

If you just need the confounders vector:

```julia
confounders = get_tmle_confounders(g, 2, 3; node_names=node_names)
# Returns: [:Z]
```

## Examples

### Example 1: Confounding

```julia
using CausalDynamics, TMLE, DataFrames, Graphs

# Graph: Z → X → Y, Z → Y
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Prepare for TMLE
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
confounders, identifiable = prepare_for_tmle(g, 2, 3; node_names=node_names)

# Estimate (requires data)
# result = TMLE.tmle(data, treatment=:X, outcome=:Y, confounders=confounders)
```

### Example 2: No Confounding

```julia
# Graph: X → Y only
g = DiGraph(2)
add_edge!(g, 1, 2)  # X → Y

node_names = Dict(1 => :X, 2 => :Y)
confounders, identifiable = prepare_for_tmle(g, 1, 2; node_names=node_names)
# Returns: ([], true) - no adjustment needed
```

### Example 3: Multiple Confounders

```julia
# Graph: Z1 → X → Y, Z2 → X → Y, Z1 → Y, Z2 → Y
g = DiGraph(4)
add_edge!(g, 1, 2)  # Z1 → X
add_edge!(g, 3, 2)  # Z2 → X
add_edge!(g, 1, 4)  # Z1 → Y
add_edge!(g, 3, 4)  # Z2 → Y
add_edge!(g, 2, 4)  # X → Y

node_names = Dict(1 => :Z1, 2 => :X, 3 => :Z2, 4 => :Y)
confounders, identifiable = prepare_for_tmle(g, 2, 4; node_names=node_names)
# Returns confounders including Z1 and/or Z2
```

## API Reference

```@docs
prepare_for_tmle
estimate_effect
get_tmle_confounders
```

## Notes

- **TMLE.jl must be loaded**: Use `using TMLE` before calling `estimate_effect`
- **Node names**: If your graph uses integer indices but data uses named columns, provide `node_names` mapping
- **Identifiability**: Functions check if effects are identifiable via backdoor adjustment
- **Warnings**: If no adjustment set is found, a warning is issued but estimation may still proceed

## Integration with StateSpaceDynamics.jl

CausalDynamics.jl and [StateSpaceDynamics.jl](https://github.com/depasquale-lab/StateSpaceDynamics.jl) are complementary packages used together in Causal Dynamical Models (CDMs):

- **CausalDynamics.jl**: Analyzes causal graph structure, identifies adjustment sets
- **StateSpaceDynamics.jl**: Performs state-space inference (filtering, smoothing, parameter learning)

Both are components of CDMs but serve different purposes. Unlike TMLE.jl integration (which has a direct workflow), StateSpaceDynamics.jl is used for different tasks within CDMs:

```julia
using CausalDynamics, StateSpaceDynamics

# Analyze graph structure (CausalDynamics.jl)
g = create_causal_graph([...])
adj_set = backdoor_adjustment_set(g, X, Y)

# Do SSM inference (StateSpaceDynamics.jl)
ssm = LinearDynamicalSystem(...)
filtered_states = filter(ssm, observations)

# Both are part of CDM, but serve different purposes
```

See the [CDCS Book](https://simonab.quarto.pub/cdcs/) for comprehensive examples of using both packages together in CDM workflows.

## Integration with UniversalDiffEq.jl

CausalDynamics.jl and [UniversalDiffEq.jl](https://github.com/Jack-H-Buckner/UniversalDiffEq.jl) are complementary packages for Causal Dynamical Models (CDMs):

- **CausalDynamics.jl**: Identifies causal structure and adjustment sets from graphs
- **UniversalDiffEq.jl**: Learns dynamics from time series data using Universal Differential Equations (UDEs)

### Workflow

UniversalDiffEq.jl builds UDEs that combine neural networks with parametric equations to learn nonlinear dynamics from time series data. When combined with CausalDynamics.jl:

1. **Identify causal structure** (CausalDynamics.jl)
2. **Learn dynamics** respecting that structure (UniversalDiffEq.jl)
3. **Analyze interventions** using the learned dynamics

```julia
using CausalDynamics, UniversalDiffEq, Graphs, DataFrames

# Step 1: Analyze causal structure (CausalDynamics.jl)
g = create_causal_graph([(Z, X), (Z, Y), (X, Y)])
adj_set = backdoor_adjustment_set(g, X, Y)  # Set([Z])

# Step 2: Learn dynamics from time series (UniversalDiffEq.jl)
# UniversalDiffEq.jl learns UDE: du/dt = f(u) where f combines
# known parametric terms with neural networks
data = DataFrame(...)  # Time series data
model = CustomDerivatives(data, dudt, init_parameters)
train!(model)

# Step 3: Use learned dynamics for causal analysis
# The learned UDE respects the causal structure identified above
forecast = plot_forecast(model, 50)
```

### Key Features of UniversalDiffEq.jl

- **Universal Differential Equations**: Combines neural networks with parametric ODEs/SDEs
- **Training Routines**: Designed for noisy time series with observation error
- **Forecasting**: Provides forecasting capabilities for learned models
- **State Estimation**: Includes Unscented Kalman Filter for state estimation

### When to Use UniversalDiffEq.jl

Use UniversalDiffEq.jl when:
- You have time series data and want to learn dynamics
- You need to combine known parametric dynamics with unknown nonlinear terms
- You want neural network-enhanced differential equations
- You need forecasting capabilities for learned dynamics

Use CausalDynamics.jl when:
- You need to identify causal structure from graphs
- You want to determine adjustment sets for causal inference
- You need to validate causal relationships

Both packages can be used together in complete CDM workflows where causal structure informs dynamics learning, and learned dynamics enable intervention analysis.

See the [CDCS Book](https://simonab.quarto.pub/cdcs/) for comprehensive examples of combining causal structure analysis with dynamics learning.

## Integration with SciML Ecosystem

CausalDynamics.jl is designed to work with the [SciML ecosystem](https://sciml.ai/) for Causal Dynamical Models (CDMs). The SciML packages provide the dynamical systems and symbolic computation infrastructure, while CausalDynamics.jl provides causal graph operations.

### DifferentialEquations.jl

For dynamical systems with causal structure and interventions:

```julia
using CausalDynamics, DifferentialEquations, Graphs

# Analyze causal structure of dynamical system
g = create_causal_graph([...])
adj_set = backdoor_adjustment_set(g, X, Y)

# Define ODE/SDE with causal structure
function dynamics!(du, u, p, t)
    # System dynamics respecting causal graph structure
end

# Simulate with interventions
prob = ODEProblem(dynamics!, u0, tspan, p)
sol = solve(prob)
```

### ModelingToolkit.jl and Symbolics.jl

CausalDynamics.jl uses ModelingToolkit.jl and Symbolics.jl for symbolic SCM representation and do-calculus:

- **Symbolic SCMs**: Represent structural equations symbolically
- **Do-calculus**: Symbolic manipulation for identification
- **Intervention operators**: Symbolic application of `do(·)` operators

```julia
using CausalDynamics, ModelingToolkit, Symbolics

# Create symbolic SCM (future feature)
# scm = create_symbolic_scm(g, equations)
# result = apply_intervention(scm, :X, 1.0)
```

These packages enable symbolic computation for advanced causal inference tasks.

## Integration with Turing.jl

CausalDynamics.jl complements [@turing.jl] for Bayesian causal inference:

- **CausalDynamics.jl**: Identifies adjustment sets, validates causal structure
- **Turing.jl** [@turing.jl]: Performs Bayesian inference for causal effects and parameters

### Workflow

```julia
using CausalDynamics, Turing, Graphs, DataFrames

# Step 1: Identify adjustment set
g = create_causal_graph([(Z, X), (Z, Y), (X, Y)])
adj_set = backdoor_adjustment_set(g, X, Y)  # Set([Z])

# Step 2: Define Bayesian causal model
@model function causal_model(data, confounders)
    # Priors on confounders (from identified adjustment set)
    β_z ~ Normal(0, 1)
    
    # Treatment effect
    τ ~ Normal(0, 1)
    
    # Outcome model with adjustment
    for i in 1:length(data.Y)
        data.Y[i] ~ Normal(τ * data.X[i] + β_z * data.Z[i], 1.0)
    end
end

# Step 3: Inference
chain = sample(causal_model(data, collect(adj_set)), NUTS(), 1000)
```

### Benefits

- **Validated Structure**: CausalDynamics.jl ensures correct adjustment
- **Bayesian Inference**: [@turing.jl] provides flexible probabilistic programming
- **Uncertainty Quantification**: Full posterior distributions for causal effects

## Complete CDM Workflow

CausalDynamics.jl integrates with multiple packages for complete CDM workflows:

```julia
using CausalDynamics, TMLE, StateSpaceDynamics, UniversalDiffEq, DifferentialEquations, Turing

# 1. Analyze causal structure (CausalDynamics.jl)
g = create_causal_graph([...])
adj_set = backdoor_adjustment_set(g, X, Y)

# 2. Estimate effects (TMLE.jl)
result = estimate_effect(g, data, X, Y; node_names=node_names)

# 3. Learn dynamics from time series (UniversalDiffEq.jl)
model = CustomDerivatives(time_series_data, dudt, init_parameters)
train!(model)

# 4. Infer latent states (StateSpaceDynamics.jl)
ssm = LinearDynamicalSystem(...)
filtered = filter(ssm, observations)

# 5. Simulate interventions (DifferentialEquations.jl)
prob = ODEProblem(dynamics!, u0, tspan, p)
sol = solve(prob)

# 6. Bayesian inference ([@turing.jl])
chain = sample(causal_model(data, adj_set), NUTS(), 1000)
```

Each package serves a specific role in the CDM framework:
- **CausalDynamics.jl**: Causal structure and identification
- **TMLE.jl**: Causal effect estimation
- **UniversalDiffEq.jl**: Learning dynamics from time series
- **StateSpaceDynamics.jl**: State-space inference
- **DifferentialEquations.jl**: ODE/SDE solving
- **Turing.jl** [@turing.jl]: Bayesian inference

## Further Reading

- [TMLE.jl Documentation](https://targene.github.io/TMLE.jl/stable/)
- [TMLE.jl GitHub Repository](https://github.com/TARGENE/TMLE.jl)
- [UniversalDiffEq.jl Documentation](https://jack-h-buckner.github.io/UniversalDiffEq.jl/dev/)
- [UniversalDiffEq.jl GitHub Repository](https://github.com/Jack-H-Buckner/UniversalDiffEq.jl)
- [StateSpaceDynamics.jl Documentation](https://depasquale-lab.github.io/StateSpaceDynamics.jl/stable/)
- [StateSpaceDynamics.jl GitHub Repository](https://github.com/depasquale-lab/StateSpaceDynamics.jl)
- [SciML Ecosystem](https://sciml.ai/) - DifferentialEquations.jl, ModelingToolkit.jl, Symbolics.jl
- [Turing.jl Documentation](https://turing.ml/dev/)
- [Turing.jl GitHub Repository](https://github.com/TuringLang/Turing.jl)
- CausalDynamics.jl [API Reference](@ref) for identification functions
