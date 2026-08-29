"""Structural response indicators `R` attach via [`MissingnessSpec`](@ref)
([`certify_missingness`](@ref) / `identify(...; missingness=)`).
This module owns the **wire format**: binary observation masks and refusal to
silently promote `Missing` to `Float64`. Numerical policies (`:drop`, `:ipcw`,
…) live in CausalTargeted / CausalMediation.
"""

"""
    ObservationMask

Binary response indicators aligned with named columns.

# Fields
- `columns`: column symbols (one per mask column)
- `observed`: `n × length(columns)` bit matrix; `true` means `R = 1` (observed)
- `time_indexed`: if `true`, columns are occasions of a timed process (e.g. `:y1`, `:y2`)
"""
struct ObservationMask
    columns::Vector{Symbol}
    observed::BitMatrix
    time_indexed::Bool
end

"""
    n_units(mask::ObservationMask) -> Int

Number of units (rows) in the mask.
"""
n_units(mask::ObservationMask) = size(mask.observed, 1)

"""
    miss_rates(mask::ObservationMask) -> Dict{Symbol, Float64}

Fraction of units with `R = 0` for each column.
"""
function miss_rates(mask::ObservationMask)
    n = n_units(mask)
    n == 0 && return Dict{Symbol, Float64}(c => NaN for c in mask.columns)
    return Dict{Symbol, Float64}(
        mask.columns[j] => 1.0 - (Base.count(mask.observed[:, j]) / n)
        for j in eachindex(mask.columns)
    )
end

"""
    observation_mask(data; columns, time_indexed=false) -> ObservationMask

Build an [`ObservationMask`](@ref) from a column dictionary (or named vectors).
Entries that are `missing` become `R = 0`; all other values are `R = 1`.
Does not invent filled values.
"""
function observation_mask(
    data::AbstractDict{Symbol, <:AbstractVector};
    columns::AbstractVector{Symbol} = collect(keys(data)),
    time_indexed::Bool = false,
)
    cols = collect(Symbol, columns)
    isempty(cols) && throw(ArgumentError("observation_mask requires at least one column"))
    n = length(data[cols[1]])
    for c in cols
        haskey(data, c) || throw(ArgumentError("column :$c not in data"))
        length(data[c]) == n || throw(ArgumentError(
            "column length mismatch for :$c (expected $n, got $(length(data[c])))",
        ))
    end
    observed = BitMatrix(undef, n, length(cols))
    for (j, c) in enumerate(cols)
        col = data[c]
        @inbounds for i in 1:n
            observed[i, j] = !ismissing(col[i])
        end
    end
    return ObservationMask(cols, observed, time_indexed)
end

"""
    require_complete_values(x; context="values") -> x

Return `x` unchanged if it contains no `missing`. Otherwise throw
`ArgumentError` naming `context` and directing the caller to an Observable
missingness policy (CausalTargeted `handle_missing_data` or an explicit mask).
"""
function require_complete_values(x; context::AbstractString = "values")
    if any(ismissing, x)
        throw(ArgumentError(
            "$context contain(s) missing values; CausalDynamics refuses silent " *
            "Missing → Float64 coercion. Supply complete values, apply an " *
            "ObservationMask explicitly, or use an Observable policy " *
            "(e.g. CausalTargeted.handle_missing_data).",
        ))
    end
    return x
end

"""
    apply_observation_mask(values, observed) -> Vector

Return a copy of `values` with `missing` wherever `observed` is `false`.
Lengths must match. Does not impute.
"""
function apply_observation_mask(
    values::AbstractVector,
    observed::AbstractVector{Bool},
)
    n = length(values)
    length(observed) == n || throw(ArgumentError(
        "length mismatch between values ($n) and observed ($(length(observed)))",
    ))
    T = promote_type(eltype(values), Missing)
    out = Vector{T}(undef, n)
    @inbounds for i in 1:n
        out[i] = observed[i] ? values[i] : missing
    end
    return out
end

"""
    require_complete_matrix(X; context="matrix") -> X

Reject matrices whose eltype admits `Missing` and that contain any missing entry.
Used by [`encode_to_panel`](@ref) so high-dim assays are completed (or rows
dropped) under an Observable policy before encoding.
"""
function require_complete_matrix(X::AbstractMatrix; context::AbstractString = "matrix")
    if Missing <: eltype(X)
        any(ismissing, X) && throw(ArgumentError(
            "$context contains missing values; apply an Observable missingness " *
            "policy (drop incomplete rows / impute) before encode_to_panel or " *
            "train_mechanisms!",
        ))
    end
    return X
end

"""
    apply_missingness_mechanism(data, spec; intercept, coefficients, rng)
        -> (Dict{Symbol, Vector}, ObservationMask)

Generative incompleteness for Dynamical × L2 oracles: start from **complete**
columns and set `spec.response` entries to `missing` under

- `:mcar` — Bernoulli with success probability ``\\mathrm{logistic}(\\mathrm{intercept})``
  of being *missing*
- `:mar` — ``P(R=0 \\mid W) = \\mathrm{logistic}(\\mathrm{intercept} + \\beta'W)``
- `:mnar` — throws (not simulated without further assumptions)

`coefficients` defaults to `0.8` for each symbol in `spec.conditioning_set`.
Returns a new column dictionary (response columns become `Union{Missing,Float64}`)
and the corresponding [`ObservationMask`](@ref).
"""
function apply_missingness_mechanism(
    data::AbstractDict{Symbol, <:AbstractVector},
    spec::MissingnessSpec;
    intercept::Real = -1.2,
    coefficients = nothing,
    rng::Random.AbstractRNG = Random.default_rng(),
)
    spec.regime === :mnar && throw(ArgumentError(
        "apply_missingness_mechanism does not simulate MNAR without further assumptions; " *
        "use MissingnessSpec with :mcar or :mar",
    ))
    cols = collect(keys(data))
    isempty(cols) && throw(ArgumentError("data has no columns"))
    n = length(data[first(cols)])
    for (k, v) in data
        length(v) == n || throw(ArgumentError("column length mismatch for :$k"))
        any(ismissing, v) && throw(ArgumentError(
            "apply_missingness_mechanism expects complete input; :$k already has missing",
        ))
    end
    for y in spec.response
        haskey(data, y) || throw(ArgumentError("response :$y not in data"))
    end
    for w in spec.conditioning_set
        haskey(data, w) || throw(ArgumentError("conditioning :$w not in data"))
    end

    β = if coefficients === nothing
        Dict{Symbol, Float64}(w => 0.8 for w in spec.conditioning_set)
    elseif coefficients isa AbstractDict
        Dict{Symbol, Float64}(Symbol(k) => Float64(v) for (k, v) in coefficients)
    else
        throw(ArgumentError("coefficients must be nothing or a Dict of Symbol => Real"))
    end

    out = Dict{Symbol, Vector}(k => copy(v) for (k, v) in data)
    for y in spec.response
        out[y] = Vector{Union{Float64, Missing}}(Float64.(data[y]))
    end

    for i in 1:n
        η = Float64(intercept)
        if spec.regime === :mar
            for w in spec.conditioning_set
                η += β[w] * Float64(data[w][i])
            end
        end
        p_miss = 1.0 / (1.0 + exp(-η))
        if rand(rng) < p_miss
            for y in spec.response
                out[y][i] = missing
            end
        end
    end

    mask = observation_mask(
        Dict(y => out[y] for y in spec.response);
        columns = spec.response,
        time_indexed = spec.time_indexed,
    )
    return out, mask
end

"""
    apply_missingness_mechanism(panel::CDMPanel, spec; kwargs...)
        -> (Dict{Symbol, Vector}, ObservationMask)

Apply [`apply_missingness_mechanism`](@ref) to the wide columns of a complete
[`CDMPanel`](@ref).
"""
function apply_missingness_mechanism(
    panel::CDMPanel,
    spec::MissingnessSpec;
    kwargs...,
)
    data = Dict{Symbol, Vector}(
        c => copy(panel.data[c]) for c in panel.column_order
    )
    return apply_missingness_mechanism(data, spec; kwargs...)
end

"""
    simulate_incomplete_panel(cdm, n, T; missingness, kwargs...)
        -> (Dict{Symbol, Vector}, ObservationMask, CDMPanel)

Simulate a complete [`CDMPanel`](@ref), then apply
[`apply_missingness_mechanism`](@ref) under `missingness::MissingnessSpec`.
Returns `(incomplete_columns, mask, complete_panel)`.

Extra keywords `intercept`, `coefficients`, and `rng_missing` are forwarded to
the missingness mechanism; all other keywords go to [`simulate_panel`](@ref).
"""
function simulate_incomplete_panel(
    cdm::DiscreteTimeCDM,
    n::Integer,
    T::Integer;
    missingness::MissingnessSpec,
    intercept::Real = -1.2,
    coefficients = nothing,
    rng_missing::Union{Nothing, Random.AbstractRNG} = nothing,
    rng::Random.AbstractRNG = Random.default_rng(),
    kwargs...,
)
    panel = simulate_panel(cdm, n, T; rng = rng, kwargs...)
    miss_rng = rng_missing === nothing ? rng : rng_missing
    incomplete, mask = apply_missingness_mechanism(
        panel, missingness;
        intercept = intercept, coefficients = coefficients, rng = miss_rng,
    )
    return incomplete, mask, panel
end

export ObservationMask, observation_mask, n_units, miss_rates
export require_complete_values, require_complete_matrix, apply_observation_mask
export apply_missingness_mechanism, simulate_incomplete_panel
