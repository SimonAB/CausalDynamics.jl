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

"""
    session_slice(df, session; id=:id, session_col=nothing, rename_occasion=true) -> DataFrame

Extract one capture occasion from a long table (one row per unit × session). When
`session_col` is set, filter rows where that column equals `session`. With
`rename_occasion=true`, strip a trailing session suffix from column names
(e.g. `fec_4` → `fec`).
"""
function CausalDynamics.session_slice(
    df::DataFrame,
    session::Integer;
    id::Symbol = :id,
    session_col::Union{Nothing, Symbol} = nothing,
    rename_occasion::Bool = true,
)
    session = Int(session)
    out = if session_col === nothing
        copy(df)
    else
        mask = [v == session for v in df[!, session_col]]
        df[mask, :]
    end
    if rename_occasion && session_col !== nothing
        suffix = string(session)
        for col in propertynames(out)
            col == id && continue
            col == session_col && continue
            scol = string(col)
            if endswith(scol, suffix)
                new_name = Symbol(scol[1:(end - length(suffix))])
                if !(new_name in propertynames(out))
                    rename!(out, col => new_name)
                end
            end
        end
    end
    return out
end

end
