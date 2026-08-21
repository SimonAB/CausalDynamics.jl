# AgeSCM-pattern 1D CNN encoder stub (Lux; no Flux hard dep).
#
# Spectra are rows of length `p`. The network maps each row to `d` codes.
# Input tensor layout for Lux Conv: (spatial, channels, batch) = (p, 1, n).

"""
    make_cnn_encoder(p, d; hidden_ch=4, kernel=5, rng)

Return `(encode, nn, ps, st)` where `encode(S)` maps an `n×p` matrix to an
`n×d` Float64 code matrix (AgeSCM-style 1D CNN → dense head).
"""
function make_cnn_encoder(
    p::Int,
    d::Int;
    hidden_ch::Int = 4,
    kernel::Int = 5,
    rng = Random.default_rng(),
)
    p >= kernel || throw(ArgumentError("spectrum length p=$p < kernel=$kernel"))
    d >= 1 || throw(ArgumentError("d must be ≥ 1"))
    nn = Chain(
        Conv((kernel,), 1 => hidden_ch, relu; pad = SamePad()),
        Conv((kernel,), hidden_ch => hidden_ch, relu; pad = SamePad()),
        FlattenLayer(),
        Dense(hidden_ch * p => d),
    )
    ps, st = Lux.setup(rng, nn)
    ps = ComponentArray(ps)

    function encode(S::AbstractMatrix)
        n, p_in = size(S)
        p_in == p || throw(ArgumentError("expected p=$p columns; got $p_in"))
        X = reshape(Float32.(transpose(S)), p, 1, n)  # (spatial, ch, batch)
        Y, _ = Lux.apply(nn, X, ps, st)
        # Y is (d, n)
        return Float64.(transpose(Array(Y)))
    end

    return encode, nn, ps, st
end
