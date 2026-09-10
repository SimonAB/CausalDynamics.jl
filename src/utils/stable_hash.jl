"""Deterministic identifiers for certificates, caches and benchmark seeds."""

"""
    stable_hash64(value) -> UInt64

Return a deterministic 64-bit digest of a canonical textual value. Unlike
`Base.hash`, this value is intended for persisted certificates and
cross-version reproducibility.
"""
function stable_hash64(value)
    text = value isa AbstractString ? String(value) : repr(value)
    digest = sha256(codeunits(text))
    return parse(UInt64, bytes2hex(digest[1:8]); base = 16)
end

"""Derive a deterministic seed from declared primitive components."""
function stable_seed(parts...)
    canonical = join(["$(typeof(part)):$(repr(part))" for part in parts], "|")
    return UInt(stable_hash64(canonical))
end

"""Return a reproducible seed from a copy of an RNG without advancing it."""
function stable_rng_seed(rng::AbstractRNG)
    try
        return UInt(rand(copy(rng), UInt))
    catch
        return stable_seed(typeof(rng), repr(rng))
    end
end

export stable_hash64, stable_seed, stable_rng_seed
