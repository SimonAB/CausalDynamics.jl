using CausalDynamics
using Test
using Graphs

@testset "CausalDynamics.jl" begin
include("test_graphs.jl")
include("test_identification.jl")
include("test_identification_api.jl")
include("test_causal_graph.jl")
include("test_time_indexed.jl")
include("test_scm.jl")
include("test_cdm.jl")
include("test_policies.jl")
include("test_integration.jl")
include("test_best_practices.jl")
include("test_rxinfer.jl")
include("test_discovery.jl")
include("test_associations.jl")
include("test_sciml.jl")
include("test_iee.jl")
include("test_kinetic_discovery.jl")
# Load DAGMakie last so its overlapping path exports do not shadow CausalDynamics in earlier tests.
include("test_utils.jl")
end
