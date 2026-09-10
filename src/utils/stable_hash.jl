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

"""Return a type-tagged, length-stable encoding of a literal intervention value."""
function _canonical_literal(value::Symbol)
    return "Symbol=$(value)"
end

function _canonical_literal(value::AbstractString)
    return "String=$(value)"
end

function _canonical_literal(value::Integer)
    return "$(nameof(typeof(value)))=$(value)"
end

function _canonical_literal(value::AbstractFloat)
    return "$(nameof(typeof(value)))=$(value)"
end

function _canonical_literal(value::UnitRange)
    return "UnitRange=$(_canonical_literal(value.start)):$(_canonical_literal(value.stop))"
end

function _canonical_literal(value)
    text = string(value)
    return "$(nameof(typeof(value)))=$(ncodeunits(text)):$(text)"
end

"""Join canonical field strings with length prefixes."""
function _canonical_fields(xs)
    return join(["$(ncodeunits(string(x))):$(x)" for x in xs], "|")
end

"""Encode the shared intervention-descriptor field tuple."""
function _canonical_descriptor_fields(target, replacement, replacement_id, interval, scope,
    stochasticity, cointerventions)
    cointervention_text = join(
        ["$(ncodeunits(string(x))):$(x)" for x in sort(collect(cointerventions))],
        "|",
    )
    fields = (
        string(target), string(replacement), string(replacement_id),
        _canonical_literal(interval), string(scope), string(stochasticity),
        cointervention_text,
    )
    return _canonical_fields(fields)
end

"""Return a length-prefixed representation of one seed component."""
function _canonical_seed_component(part)
    type_text = string(typeof(part))
    value_text = _canonical_literal(part)
    return "$(ncodeunits(type_text)):$type_text$(ncodeunits(value_text)):$value_text"
end

"""
    stable_seed(parts...) -> UInt

Derive a deterministic seed from declared primitive or otherwise canonically
represented components. Length prefixes prevent delimiter collisions.
"""
function stable_seed(parts...)
    canonical = join(_canonical_seed_component.(parts), "")
    return UInt(stable_hash64(canonical))
end

"""
    stable_rng_seed(rng) -> UInt

Derive a seed from a copy of `rng` without advancing the supplied generator.
Cross-version stability depends on the RNG implementation; use an RNG with an
explicit stability guarantee, such as `StableRNG`, when persisted results must
reproduce across Julia releases.
"""
function stable_rng_seed(rng::AbstractRNG)
    copied_rng = copy(rng)
    return UInt(rand(copied_rng, UInt64))
end

export stable_hash64, stable_seed, stable_rng_seed
