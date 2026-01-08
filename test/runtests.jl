using CausalDynamics
using Test
using Graphs

@testset "CausalDynamics.jl" begin
include("test_graphs.jl")
include("test_identification.jl")
include("test_scm.jl")
include("test_utils.jl")
include("test_integration.jl")
include("test_best_practices.jl")
end
