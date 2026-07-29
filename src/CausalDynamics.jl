"""
    CausalDynamics.jl

Causal graph operations and identification for **Causal Dynamical Models (CDMs)**,
with a lightweight SCM layer and discrete-time trajectory simulation.

This package provides:

- Causal graph operations (d-separation, paths, sets)
- Hypergraph support for higher-order causal interactions
- Identification algorithms (backdoor, frontdoor, instruments, adjustment)
- Structural Causal Model (`GraphSCM`) simulation and `do(·)` interventions
- Discrete-time CDMs (`DiscreteTimeCDM`, `DoSequence`, shared-`U` `counterfactual`)
- Optional plotting via [DAGMakie.jl](https://github.com/SimonAB/DAGMakie.jl)
- Identification façades over [CausalInference.jl](https://github.com/SimonAB/CausalInference.jl)
- Optional RxInfer / GraphPPL backdoor inference extension

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
- Shpitser, I., & Pearl, J. (2006). Identification of joint interventional distributions
"""
module CausalDynamics

using Graphs
using CausalInference
using Random

# Re-export commonly used types from Graphs.jl
import Graphs: DiGraph, SimpleDiGraph, inneighbors, outneighbors, vertices, add_edge!, has_edge
export DiGraph, SimpleDiGraph

# Graph operations (order matters - d_separation needs sets, paths needs d_separation)
include("graphs/validation.jl")
include("graphs/sets.jl")
include("graphs/d_separation.jl")  # d_separation needs sets
include("graphs/paths.jl")  # paths needs d_separation
include("graphs/hypergraph.jl")  # hypergraph for higher-order interactions
include("graphs/causal_graph.jl")  # CausalGraph with properties
include("graphs/time_indexed.jl")  # unrolled lag DAGs for discrete-time ID

# Identification algorithms
include("identification/queries.jl")
include("identification/result.jl")
include("identification/resolver.jl")
include("identification/backdoor.jl")
include("identification/frontdoor.jl")
include("identification/instruments.jl")
include("identification/adjustment.jl")
include("identification/do_calculus.jl")
include("identification/identify.jl")
include("identification/report.jl")

# SCM framework
include("scm/scm.jl")
include("scm/symbolic_scm.jl")
include("scm/interventions.jl")
include("scm/counterfactuals.jl")

# Discrete-time Causal Dynamical Models
include("cdm/discrete_cdm.jl")

# Utilities
include("utils/graph_utils.jl")
include("utils/symbolic_utils.jl")
include("utils/visualization.jl")

# Integration with other packages
include("integration/tmle.jl")
include("integration/ppl.jl")
include("integration/rxinfer.jl")
include("integration/discovery.jl")
include("integration/sciml.jl")

end # module
