"""
    MissingnessSpec

Structural claim about response indicators for incomplete observation.

# Fields
- `response`: outcome (or panel) symbols that may be unobserved (`Y`, `Y1`, …)
- `regime`: `:mcar`, `:mar`, or `:mnar`
- `conditioning_set`: covariates claimed for ``P(R=1 \\mid \\cdot)`` under MAR
- `time_indexed`: whether `response` indexes occasions of a timed process
- `indicators`: optional explicit `R` node symbols (default: derived as `R_<response>`)

Does not estimate anything; use [`certify_missingness`](@ref) / `identify(...; missingness=)`.
"""
struct MissingnessSpec
    response::Vector{Symbol}
    regime::Symbol
    conditioning_set::Vector{Symbol}
    time_indexed::Bool
    indicators::Vector{Symbol}
end

const _MISSINGNESS_REGIMES = (:mcar, :mar, :mnar)

function _default_indicators(response::AbstractVector{Symbol})
    return [Symbol("R_", string(y)) for y in response]
end

"""
    MissingnessSpec(response; regime=:mar, conditioning_set=Symbol[], time_indexed=false, indicators=nothing)
"""
function MissingnessSpec(
    response::AbstractVector{Symbol};
    regime::Symbol = :mar,
    conditioning_set::AbstractVector{Symbol} = Symbol[],
    time_indexed::Bool = false,
    indicators = nothing,
)
    regime in _MISSINGNESS_REGIMES || throw(ArgumentError(
        "missingness regime must be one of $(_MISSINGNESS_REGIMES); got :$regime",
    ))
    resp = collect(Symbol, response)
    isempty(resp) && throw(ArgumentError("MissingnessSpec requires at least one response symbol"))
    inds = indicators === nothing ? _default_indicators(resp) : collect(Symbol, indicators)
    length(inds) == length(resp) || throw(ArgumentError(
        "indicators length $(length(inds)) must match response length $(length(resp))",
    ))
    return MissingnessSpec(resp, regime, collect(Symbol, conditioning_set), time_indexed, inds)
end

MissingnessSpec(response::Symbol; kwargs...) = MissingnessSpec([response]; kwargs...)

"""
    MissingnessCertificate

Result of [`certify_missingness`](@ref): whether the stated missingness regime
identifies interventional / associational targets under incomplete observation.

Causal total-effect identification (`IdentificationResult.identifiable`) remains
separate; estimators should consult both fields.
"""
struct MissingnessCertificate
    response::Vector{Symbol}
    indicators::Vector{Symbol}
    regime::Symbol
    mar_set::Vector{Symbol}
    identifiable::Bool
    status::Symbol
    assumptions::Vector{Symbol}
    time_indexed::Bool
    note::String
end

"""
    certify_missingness(spec::MissingnessSpec) -> MissingnessCertificate

Map a [`MissingnessSpec`](@ref) to an identification certificate:

- `:mcar` — identified with empty `mar_set`
- `:mar` — identified iff `conditioning_set` is nonempty
- `:mnar` — unidentified without further modelling assumptions (Phase 3)

Optional `graph` / `node_names` are reserved for future edge checks against `R`
nodes; they do not change the Phase 3 decision rule.
"""
function certify_missingness(
    spec::MissingnessSpec;
    graph = nothing,
    node_names = nothing,
)
    # graph / node_names reserved for Phase 3+ parent checks of R nodes
    _ = graph
    _ = node_names
    if spec.regime === :mcar
        return MissingnessCertificate(
            spec.response, spec.indicators, :mcar, Symbol[],
            true, :identified, [:mcar], spec.time_indexed,
            "MCAR: response indicators independent of all variables",
        )
    elseif spec.regime === :mar
        if isempty(spec.conditioning_set)
            return MissingnessCertificate(
                spec.response, spec.indicators, :mar, Symbol[],
                false, :unidentified, [:mar], spec.time_indexed,
                "MAR requires a nonempty conditioning_set for P(R=1 | ·)",
            )
        end
        return MissingnessCertificate(
            spec.response, spec.indicators, :mar, copy(spec.conditioning_set),
            true, :identified, [:mar], spec.time_indexed,
            "MAR given conditioning_set; Observable IPCW may use this mar_set",
        )
    elseif spec.regime === :mnar
        return MissingnessCertificate(
            spec.response, spec.indicators, :mnar, copy(spec.conditioning_set),
            false, :unidentified, [:mnar], spec.time_indexed,
            "MNAR is unidentified without further assumptions (pattern mixture, shared U, …)",
        )
    else
        throw(ArgumentError("unknown missingness regime :$(spec.regime)"))
    end
end

export MissingnessSpec, MissingnessCertificate, certify_missingness
