using CausalDynamics
using Test
using Graphs

@testset "CausalDynamics.jl" begin
include("test_graphs.jl")
include("test_identification.jl")
include("test_scm.jl")
include("test_integration.jl")
include("test_best_practices.jl")
include("test_rxinfer.jl")
# Load DAGMakie last so its overlapping path exports do not shadow CausalDynamics in earlier tests.
include("test_utils.jl")
end
