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
        mask.columns[j] => 1.0 - (count(mask.observed[:, j]) / n)
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

export ObservationMask, observation_mask, n_units, miss_rates
export require_complete_values, apply_observation_mask
