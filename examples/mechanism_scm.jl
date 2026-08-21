# Static GraphSCM with a Lux mechanism at Y (Phase 2)
#
# julia --project=. --threads=auto packages/CausalDynamics.jl/examples/mechanism_scm.jl

using CausalDynamics
using Graphs
using Lux
using ComponentArrays
using Optimization
using OptimizationOptimisers
using Random

function main()
    rng = Random.Xoshiro(5)
    g = DiGraph(3)
    add_edge!(g, 1, 2)
    add_edge!(g, 2, 3)
    names = Dict(1 => :z, 2 => :x, 3 => :y)

    lib = MechanismLibrary(;
        allowed_parents = Dict(:z => Symbol[], :x => [:z], :y => [:x]),
    )
    attach_lux_mechanism!(lib, :y; parents = [:x], hidden = 8, kind = :static, rng = rng)

    equations = Dict{Int, Function}(
        1 => (u,) -> u,
        2 => (z, u) -> 0.8 * z + u,
        3 => (x, u) -> 0.0,
    )
    scm = graphscm_with_mechanisms(g, equations, Set{Int}(), lib; node_names = names)

    # Teach Y ≈ 2X by matching factuals under shared U
    targets = Float64[]
    us = Dict{Int, Float64}[]
    for i in 1:40
        U = Dict(1 => randn(rng), 2 => 0.1 * randn(rng), 3 => 0.0)
        x = 0.8 * U[1] + U[2]
        push!(targets, 2x)
        push!(us, U)
    end

    loss = function (_ps)
        s = 0.0
        for (U, yt) in zip(us, targets)
            s += abs2(simulate_scm(scm, U)[3] - yt)
        end
        return s / length(targets)
    end

    println("Certificate: ", mechanism_certificate(lib))
    println("Loss before: ", round(loss(nothing); digits = 4))
    train_mechanisms!(lib; loss = loss, maxiters = 300, lr = 0.05)
    # Refresh SCM equations with updated parameters
    scm = graphscm_with_mechanisms(g, equations, Set{Int}(), lib; node_names = names)
    println("Loss after:  ", round(loss(nothing); digits = 4))
    Utest = Dict(1 => 1.0, 2 => 0.0, 3 => 0.0)
    println("simulate Y (expect ~1.6): ", round(simulate_scm(scm, Utest)[3]; digits = 3))
    return scm
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
