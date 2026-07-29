# SciML ↔ CausalDynamics composition recipe (no SciML hard dep in the package).
# Run from the package root:
#   julia --project=. examples/sciml_cdm_recipe.jl
#
# Requires OrdinaryDiffEq in your environment.

using CausalDynamics
using Graphs
using Random

function main()
    # ── 1. Identification (static summary graph) ─────────────────────
    g = DiGraph(3)
    add_edge!(g, 1, 2)
    add_edge!(g, 1, 3)
    add_edge!(g, 2, 3)
    println("Backdoor adjustment set X → Y: ", backdoor_adjustment_set(g, 2, 3))

    # ── 2. Discrete-time trajectory (package-native CDM) ─────────────
    cdm = DiscreteTimeCDM(
        [:x, :y];
        initialise = (rng) -> (x = 1.0, y = 0.0),
        sample_noise = (rng, state, t) -> (u_x = 0.1 * randn(rng), u_y = 0.05 * randn(rng)),
        step = (state, t, noise, intervention) -> begin
            x = 0.9 * state.x + noise.u_x
            y = x + noise.u_y
            (x = x, y = y)
        end,
    )
    traj = simulate(cdm, 50; rng = Random.Xoshiro(0))
    println("Discrete CDM terminal Y: ", round(traj.series[:y][end]; digits = 3))

    # ── 3. Continuous CDM via SciML extension ────────────────────────
    if Base.find_package("OrdinaryDiffEq") !== nothing
        using OrdinaryDiffEq
        spec = ContinuousCDMSpec([:prey, :predator])
        function lotka!(du, u, p, t)
            X, Y = u
            du[1] = p.r * X - p.α * X * Y
            du[2] = p.β * X * Y - p.δ * Y
            return nothing
        end
        p = (r = 1.0, α = 0.1, β = 0.02, δ = 0.5)
        sol = solve_cdm(spec, lotka!, [40.0, 9.0], (0.0, 10.0), p)
        term = terminal_state(spec, sol)
        println("ODE terminal prey: ", round(term.prey; digits = 2))
    else
        println("OrdinaryDiffEq not loaded — skipping ODE demo (install in your env).")
    end

    return traj
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
