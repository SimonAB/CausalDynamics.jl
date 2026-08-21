module CausalDynamicsDataFramesExt

using CausalDynamics
using DataFrames

"""
    DataFrame(panel::CDMPanel)

Wide `DataFrame` in [`CDMPanel`](@ref) column order.
"""
function DataFrames.DataFrame(panel::CDMPanel; kwargs...)
    return DataFrame(NamedTuple(panel); kwargs...)
end

"""
    encode_to_panel(df, X, spec) -> DataFrame

Append representation codes from high-dim matrix `X` onto a copy of `df`.
Existing columns are preserved; `spec.code_names` must not collide with `df`.
"""
function CausalDynamics.encode_to_panel(
    df::DataFrame,
    X::AbstractMatrix{<:Real},
    spec::RepresentationSpec,
)
    n = nrow(df)
    size(X, 1) == n || throw(ArgumentError(
        "X has $(size(X, 1)) rows; expected nrow(df)=$n",
    ))
    for name in spec.code_names
        name in propertynames(df) && throw(ArgumentError(
            "code name :$name already exists in DataFrame",
        ))
    end
    codes = encode_to_panel(X, spec)
    out = copy(df)
    for name in spec.code_names
        out[!, name] = codes[name]
    end
    return out
end

end
