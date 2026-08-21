# Phase 2b: generative mechanism + additive-noise L3 counterfactual
#
# julia --project=. --threads=auto packages/CausalDynamics.jl/examples/mechanism_counterfactual.jl

using CausalDynamics
using Graphs
using Lux
using ComponentArrays
using Optimization
using OptimizationOptimisers
using Random

function main()
    rng = Random.Xoshiro(21)
    lib = MechanismLibrary(;
        allowed_parents = Dict(:x => Symbol[], :y => [:x]),
    )
    attach_lux_mechanism!(
        lib, :y;
        parents = [:x],
        hidden = 8,
        kind = :generative,
        rng = rng,
    )
    spec = lib.mechanisms[:y]

    xs = range(-1.5, 1.5; length = 50)
    loss = function (_ps)
        s = 0.0
        for x in xs
            s += abs2(generate_from_noise(spec, 0.0, [x]) - 2x)
        end
        return s / length(xs)
    end
    println("Certificate: ", mechanism_certificate(lib))
    println("Loss before: ", round(loss(nothing); digits = 4))
    train_mechanisms!(lib; loss = loss, maxiters = 300, lr = 0.05)
    println("Loss after:  ", round(loss(nothing); digits = 4))

    x_f, u = 1.0, -0.4
    y_f = 2x_f + u
    y_cf = mechanism_counterfactual(spec, y_f, [x_f], [0.0])
    println("factual Y (X=1, U=-0.4): ", round(y_f; digits = 3))
    println("abduced U: ", round(abduce_noise(spec, y_f, [x_f]); digits = 3))
    println("Y under do(X=0), same U (expect ~-0.4): ", round(y_cf; digits = 3))
    return y_cf
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
