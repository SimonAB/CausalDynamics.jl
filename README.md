# CausalDynamics.jl

> ⚠️ **Work in Progress**: This package is under active development and has not yet been submitted to the Julia General registry. APIs may change without notice. Contributions and feedback are welcome!

| Minimum V-1.10 | V-1.11 | V-1.12 | Nightly |
|-----------------|---------------------|---------------------|-------------------------|
| [![Build Status](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI-V1-10.yml/badge.svg)](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI-V1-10.yml) | [![Build Status](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI-V1-11.yml/badge.svg)](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI-V1-11.yml) | [![Build Status](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI-V1-12.yml/badge.svg)](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI-V1-12.yml)| [![Build Status](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI-Nightly.yml/badge.svg)](https://github.com/SimonAB/CausalDynamics.jl/actions/workflows/CI-Nightly.yml)|

[![Docs](https://img.shields.io/badge/docs-dev-blue)](https://simonab.github.io/CausalDynamics.jl/dev/)
[![Code Style: Blue](https://img.shields.io/badge/code%20style-blue-4495d1.svg)](https://github.com/invenia/BlueStyle)

CausalDynamics.jl provides causal graph operations and identification algorithms for Causal Dynamical Models (CDMs). This package implements fundamental causal inference algorithms including d-separation, backdoor and frontdoor criteria, instrumental variables, and structural causal model (SCM) operations. It integrates with the SciML ecosystem (ModelingToolkit.jl, Symbolics.jl, DifferentialEquations.jl) and complements packages like TMLE.jl for causal effect estimation and StateSpaceDynamics.jl for state-space inference.

The package provides a focused implementation of causal graph algorithms. For highly customised causal models or advanced do-calculus operations, please use [ModelingToolkit.jl](https://mtk.sciml.ai/stable/) and [Symbolics.jl](https://symbolics.juliasymbolics.org/stable/) directly.

To install and load CausalDynamics.jl, open Julia and type the following code:

```
]add CausalDynamics
using CausalDynamics
```

To access the latest version under development with the newest features use:

```
add https://github.com/SimonAB/CausalDynamics.jl.git
```

# Tutorial

As a simple example to get started with CausalDynamics.jl, we analyse a causal graph with confounding and identify the adjustment set needed to estimate the causal effect of treatment $X$ on outcome $Y$ in the presence of confounder $Z$.

**Causal Graph**: $Z \to X$, $Z \to Y$, $X \to Y$

**Identification**: The backdoor criterion identifies $Z$ as a sufficient adjustment set to block all backdoor paths from $X$ to $Y$.

```julia
using CausalDynamics, Graphs

# Create causal graph: Z → X → Y, Z → Y (confounding)
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Check d-separation: X and Y are d-separated by Z
d_separated(g, 2, 3, [1])  # true

# Find backdoor adjustment set
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1]) = {Z}
println("Adjustment set: ", adj_set)

# Check if causal effect is identifiable
identifiable = !isempty(adj_set)  # true
```

**Result**: The causal effect of $X$ on $Y$ is identifiable by adjusting for $Z$. This means we can estimate $P(Y \mid do(X))$ from observational data using $P(Y \mid X, Z)$.

## Integration with TMLE.jl

CausalDynamics.jl identifies what to adjust for, and [TMLE.jl](https://github.com/TARGENE/TMLE.jl) estimates the causal effect:

```julia
using CausalDynamics, TMLE, DataFrames, Graphs

# Create causal graph
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 1, 3)  # Z → Y
add_edge!(g, 2, 3)  # X → Y

# Create observational data
data = DataFrame(
    Z = randn(100),
    X = rand([0, 1], 100),
    Y = randn(100)
)

# Identify adjustment set
node_names = Dict(1 => :Z, 2 => :X, 3 => :Y)
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1])

# Estimate causal effect using TMLE
confounders = [node_names[i] for i in adj_set]  # [:Z]
result = TMLE.tmle(data, treatment=:X, outcome=:Y, confounders=confounders)
```

## Integration with DifferentialEquations.jl

For dynamical systems with causal structure:

```julia
using CausalDynamics, DifferentialEquations, Graphs

# Analyse causal structure
g = DiGraph(3)
add_edge!(g, 1, 2)  # Z → X
add_edge!(g, 2, 3)  # X → Y

# Identify adjustment set for intervention
adj_set = backdoor_adjustment_set(g, 2, 3)  # Set([1])

# Define ODE with causal structure
function dynamics!(du, u, p, t)
    # System dynamics respecting causal graph
    du[1] = p.r_z * u[1]  # Z dynamics (exogenous)
    du[2] = p.r_x * u[2] + p.β_zx * u[1]  # X depends on Z
    du[3] = p.r_y * u[3] + p.β_xy * u[2]  # Y depends on X
end

# Simulate with intervention do(X = 1.0)
u0 = [1.0, 0.0, 0.0]
p = (r_z=0.1, r_x=0.2, r_y=0.15, β_zx=0.5, β_xy=0.8)
prob = ODEProblem(dynamics!, u0, (0.0, 10.0), p)
sol = solve(prob)
```

Please see the [documentation](https://simonab.github.io/CausalDynamics.jl/dev/) for detailed tutorials and API reference.

# Acknowledgements

CausalDynamics.jl is part of the Causal Dynamics for Complex Systems (CDCS) project, which provides a unified framework for causal inference in dynamical systems. The package integrates with the broader SciML ecosystem and complements packages like UniversalDiffEq.jl, StateSpaceDynamics.jl, and TMLE.jl for complete Causal Dynamical Model workflows.

See the [CDCS Book](https://simonab.quarto.pub/cdcs/) for comprehensive examples and theoretical background.
