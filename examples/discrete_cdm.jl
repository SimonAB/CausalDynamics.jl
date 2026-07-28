# Discrete-time CDM: observational simulate + shared-U counterfactual
using CausalDynamics
using Random

"""
Build a linear AR CDM: ``A_t = 0.5 A_{t-1} + U^a_t``, ``Y_t = 2 A_t + U^y_t``.
"""
function linear_ar_cdm()
    return DiscreteTimeCDM(
        [:a, :y];
        initialise = (rng) -> (a = 0.0, y = 0.0),
        sample_noise = (rng, state, t) -> (u_a = randn(rng), u_y = randn(rng)),
        step = (state, t, noise, intervention) -> begin
            a = intervention_value(intervention, :a, t, 0.5 * state.a + noise.u_a)
            y = 2a + noise.u_y
            (a = a, y = y)
        end,
    )
end

function main()
    cdm = linear_ar_cdm()
    T = 20
    factual = simulate(cdm, T; rng = Random.Xoshiro(7))
    cf = counterfactual(cdm, factual.noise; intervention = do_sequence(:a, fill(1.0, T)))
    println("factual mean Y: ", round(sum(factual.series[:y]) / T; digits = 3))
    println("cf do(A=1) mean Y: ", round(sum(cf.series[:y]) / T; digits = 3))
    return factual, cf
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
