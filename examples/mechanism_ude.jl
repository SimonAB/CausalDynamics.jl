# Graph-constrained Lux residual on a continuous CDM (Phase 2)
#
# julia --project=. --threads=auto packages/CausalDynamics.jl/examples/mechanism_ude.jl

using CausalDynamics
using OrdinaryDiffEq
using Lux
using ComponentArrays
using Optimization
using OptimizationOptimisers
using Random

function main()
    rng = Random.Xoshiro(11)
    spec = ContinuousCDMSpec(
        [:z, :x, :y];
        parents = Dict(:z => Symbol[], :x => [:z, :x], :y => [:x, :y]),
    )
    lib = mechanism_library_from_cdm(spec)
    attach_lux_mechanism!(lib, :x; parents = [:z], hidden = 8, rng = rng)

    function known_rhs!(du, u, p, t)
        z, x, y = u
        du[1] = -0.1 * z
        du[2] = -0.2 * x
        du[3] = -0.1 * y + 0.4 * x
        return nothing
    end
    rhs! = build_ode_rhs(known_rhs!, spec, lib)

    function true_rhs!(du, u, p, t)
        z, x, y = u
        du[1] = -0.1 * z
        du[2] = -0.2 * x + 0.5 * z
        du[3] = -0.1 * y + 0.4 * x
        return nothing
    end

    u0 = [2.0, 0.5, 0.0]
    tspan = (0.0, 6.0)
    t_obs = 0.0:0.2:6.0
    data = Array(solve(ODEProblem(true_rhs!, u0, tspan), Tsit5(); saveat = t_obs))

    loss = function (_ps)
        pred = solve(ODEProblem(rhs!, u0, tspan), Tsit5(); saveat = t_obs)
        try
            return sum(abs2, Array(pred) .- data)
        catch
            return 1e6
        end
    end

    println("Certificate: ", mechanism_certificate(lib))
    println("Loss before: ", round(loss(nothing); digits = 4))
    train_mechanisms!(lib; loss = loss, maxiters = 200, lr = 0.05)
    println("Loss after:  ", round(loss(nothing); digits = 4))

    sol_do = solve_cdm(spec, rhs!, u0, tspan, nothing; intervention = do_pin(:z, 1.0))
    println("do(z=1) terminal z: ", round(sol_do.u[end][1]; digits = 4))
    return lib
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
