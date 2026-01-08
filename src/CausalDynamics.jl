"""
    CausalDynamics.jl

A Julia package for causal graph operations and identification algorithms,
designed for Causal Dynamical Models (CDMs) and integration with the SciML ecosystem.

This package provides:
- Causal graph operations (d-separation, paths, sets)
- Identification algorithms (backdoor, frontdoor, do-calculus)
- Structural Causal Model (SCM) framework
- Intervention operators and counterfactual reasoning

# Examples

```julia
using CausalDynamics
using Graphs

# Create a causal graph
g = DiGraph(4)
add_edge!(g, 1, 2)  # X → Y
add_edge!(g, 3, 1)  # Z → X
add_edge!(g, 3, 2)  # Z → Y

# Check d-separation
d_separated(g, 1, 2, [3])  # true (Z blocks the path)

# Find backdoor adjustment set
backdoor_adjustment_set(g, 1, 2)  # [3]
```

# References

- Pearl, J. (2009). *Causality: Models, Reasoning, and Inference*
- Hofmann et al. (2023). Spectral DCM with ModelingToolkit.jl
- Shpitser, I., & Pearl, J. (2006). Identification of joint interventional distributions
"""
module CausalDynamics

using Graphs
using ModelingToolkit
using Symbolics
using ForwardDiff

# Re-export commonly used types from Graphs.jl
import Graphs: DiGraph, SimpleDiGraph, inneighbors, outneighbors, vertices, add_edge!, has_edge
export DiGraph, SimpleDiGraph

# Graph operations (order matters - d_separation needs sets, paths needs d_separation)
include("graphs/validation.jl")
include("graphs/sets.jl")
include("graphs/d_separation.jl")  # d_separation needs sets
include("graphs/paths.jl")  # paths needs d_separation

# Identification algorithms
include("identification/backdoor.jl")
include("identification/frontdoor.jl")
include("identification/instruments.jl")
include("identification/adjustment.jl")
include("identification/do_calculus.jl")

# SCM framework
include("scm/scm.jl")
include("scm/symbolic_scm.jl")
include("scm/interventions.jl")
include("scm/counterfactuals.jl")

# Utilities
include("utils/graph_utils.jl")
include("utils/symbolic_utils.jl")
include("utils/visualization.jl")

# Integration with other packages
include("integration/tmle.jl")

end # module
