# Representation bridge: high-dim spectrum → Lux codes → mediation columns
#
# Requires Lux (optional). From the CDCS book env:
#   julia --project=. --threads=auto packages/CausalDynamics.jl/examples/representation_bridge.jl
#
# CausalDynamics has no Lux hard dependency: the encoder is a user callable.

using CausalDynamics
using DataFrames
using Random
using Statistics

const HAS_LUX = try
    @eval using Lux
    true
catch
    false
end

"""
    simulate_spectrum_mediation(n; p, rng)

Synthetic DGP ``A → M* → Y`` with spectrum ``S`` a noisy embedding of ``M*``.
Returns `(S, df_tabular, truth)` where `truth` holds the latent mediator.
"""
function simulate_spectrum_mediation(
    n::Int;
    p::Int = 64,
    rng::AbstractRNG = Random.Xoshiro(1),
)
    A = Float64.(rand(rng, n) .< 0.5)
    W = randn(rng, n)
    Mstar = 1.2 .* A .+ 0.4 .* W .+ 0.35 .* randn(rng, n)
    Y = 1.8 .* Mstar .+ 0.5 .* W .+ 0.25 .* randn(rng, n)
    # Embed M* in a smooth spectral bump; rest is noise
    grid = range(0, 1; length = p)
    bump = exp.(-((collect(grid) .- 0.4) ./ 0.08) .^ 2)
    S = randn(rng, n, p) .* 0.15
    for i in 1:n
        S[i, :] .+= Mstar[i] .* bump
    end
    df = DataFrame(A = A, W = W, Y = Y)
    truth = (Mstar = Mstar, β_AM = 1.2, β_MY = 1.8)
    return S, df, truth
end

"""
    make_lux_mlp_encoder(p, d; rng) -> (encode, ps, st)

Small Lux MLP ``p → 16 → d``. Returns a batch encoder ``S ↦ n×d`` matrix.
"""
function make_lux_mlp_encoder(p::Int, d::Int; rng::AbstractRNG = Random.Xoshiro(2))
    HAS_LUX || error("Lux.jl is required for this encoder; Pkg.add(\"Lux\")")
    nn = Chain(Dense(p => 16, tanh), Dense(16 => d))
    ps, st = Lux.setup(rng, nn)
    function encode(S::AbstractMatrix{<:Real})
        # Lux expects features × batch; we store rows as samples
        X = Float32.(permutedims(S))  # p × n
        Y, _ = Lux.apply(nn, X, ps, st)
        return Float64.(permutedims(Y))  # n × d
    end
    return encode, ps, st
end

"""
    make_projection_encoder(p, d; rng) -> Function

Fallback without Lux: random projection ``S ↦ S * B``.
"""
function make_projection_encoder(p::Int, d::Int; rng::AbstractRNG = Random.Xoshiro(2))
    B = randn(rng, p, d) ./ sqrt(p)
    return S -> S * B
end

function main()
    n, p, d = 300, 64, 2
    rng = Random.Xoshiro(7)
    S, df, truth = simulate_spectrum_mediation(n; p = p, rng = rng)

    encode = if HAS_LUX
        enc, _, _ = make_lux_mlp_encoder(p, d; rng = Random.Xoshiro(3))
        println("Encoder: Lux MLP ($p → 16 → $d), untrained weights (demo)")
        enc
    else
        println("Lux not loaded; using random projection encoder")
        make_projection_encoder(p, d; rng = Random.Xoshiro(3))
    end

    spec = RepresentationSpec(
        :spectrum,
        [:z1, :z2],
        encode;
        role = :definitional,
    )
    cert = representation_certificate(spec)
    println("Certificate: ", cert)

    wide = encode_to_panel(df, S, spec)
    println("Columns: ", names(wide))
    println("Code means: z1=", round(mean(wide.z1); digits = 3),
            " z2=", round(mean(wide.z2); digits = 3))

    # Hand-off to CausalMediation would use mediators = [:z1, :z2]:
    #   MediationSpec(:A, :Y; mediators = [:z1, :z2], covariates = [:W])
    # Fit encoders on training folds (or freeze a pretrained map) before EIF.
    cor_z1 = cor(wide.z1, truth.Mstar)
    cor_z2 = cor(wide.z2, truth.Mstar)
    println("corr(z, M*): ", round(cor_z1; digits = 3), ", ", round(cor_z2; digits = 3))
    println("Next: MediationSpec(:A, :Y; mediators = [:z1, :z2], covariates = [:W])")
    return wide, cert, truth
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end
