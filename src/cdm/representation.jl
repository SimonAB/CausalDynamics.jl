"""High-dim → low-dim representation bridge (no deep-learning hard dependency).

Encoders (CNN, MLP, PCA, …) are user-supplied callables. CausalDynamics records
the map and emits tabular code columns for identification and estimation.
"""

const REPRESENTATION_ROLES = (:measurement, :definitional)

"""
    RepresentationSpec(source, code_names, encode; role=:measurement)

Declare how a high-dimensional input becomes low-dimensional codes for the
causal graph and estimation APIs.

# Fields
- `source`: label for the high-dim input (documentation / certificate; not a
  DataFrame column requirement)
- `code_names`: symbols for the emitted code columns (length `d`)
- `encode`: callable on an ``n × p`` matrix. Return an ``n × d`` matrix, or a
  length-`n` vector of length-`d` vectors / NamedTuples whose keys match
  `code_names` when NamedTuples are used
- `role`: `:measurement` (codes observe a latent mediator) or `:definitional`
  (the mediator *is* the encoder output)

Identification and EIF/TMLE see only `code_names`, not CNN layers.
"""
struct RepresentationSpec
    source::Symbol
    code_names::Vector{Symbol}
    encode::Any
    role::Symbol
end

function RepresentationSpec(
    source::Symbol,
    code_names::AbstractVector{Symbol},
    encode;
    role::Symbol = :measurement,
)
    role in REPRESENTATION_ROLES || throw(ArgumentError(
        "role must be one of $REPRESENTATION_ROLES; got :$role",
    ))
    isempty(code_names) && throw(ArgumentError("code_names must be non-empty"))
    names = Symbol[Symbol(c) for c in code_names]
    length(unique(names)) == length(names) || throw(ArgumentError(
        "code_names must be unique; got $names",
    ))
    return RepresentationSpec(Symbol(source), names, encode, role)
end

"""
    representation_certificate(spec) -> NamedTuple

Auditable metadata for run records: `role`, `source`, `code_names`, and a
stable hash of the encoder's type (not weights).
"""
function representation_certificate(spec::RepresentationSpec)
    return (
        role = spec.role,
        source = spec.source,
        code_names = copy(spec.code_names),
        encode_type = string(typeof(spec.encode)),
        encode_type_hash = hash(typeof(spec.encode)),
        n_codes = length(spec.code_names),
    )
end

"""
    encode_to_panel(X, spec; tabular=nothing) -> Dict{Symbol, Vector{Float64}}

Apply `spec.encode` to the high-dim matrix `X` (`n × p`) and return a column
dictionary with `spec.code_names`. Optional `tabular` supplies additional
columns (e.g. `:A`, `:W`, `:Y`) of length `n`; they are copied unchanged.

Does not require DataFrames. For a `DataFrame` result, load DataFrames so the
weakdep extension is available and call
`encode_to_panel(df, X, spec)`.
"""
function encode_to_panel(
    X::AbstractMatrix,
    spec::RepresentationSpec;
    tabular::Union{Nothing, AbstractDict} = nothing,
)
    require_complete_matrix(X; context = "encode_to_panel input X")
    n, _ = size(X)
    n >= 1 || throw(ArgumentError("X must have at least one row"))
    d = length(spec.code_names)
    Xr = X isa AbstractMatrix{<:Real} ? X : map(Float64, X)
    codes = _materialise_codes(spec.encode(Xr), n, d, spec.code_names)

    out = Dict{Symbol, Vector{Float64}}()
    for (j, name) in enumerate(spec.code_names)
        out[name] = codes[:, j]
    end

    if tabular !== nothing
        for (k, v) in tabular
            key = Symbol(k)
            length(v) == n || throw(ArgumentError(
                "tabular column :$key has length $(length(v)), expected n=$n",
            ))
            haskey(out, key) && throw(ArgumentError(
                "tabular column :$key collides with code name",
            ))
            out[key] = Float64.(v)
        end
    end
    return out
end

"""
    _materialise_codes(raw, n, d, code_names) -> Matrix{Float64}

Normalise encoder output to an ``n × d`` `Float64` matrix.
"""
function _materialise_codes(raw, n::Int, d::Int, code_names::Vector{Symbol})
    if raw isa AbstractMatrix
        size(raw, 1) == n || throw(ArgumentError(
            "encode returned matrix with $(size(raw, 1)) rows; expected n=$n",
        ))
        size(raw, 2) == d || throw(ArgumentError(
            "encode returned $(size(raw, 2)) columns; expected d=$d ($(code_names))",
        ))
        return Float64.(raw)
    end
    if raw isa AbstractVector
        length(raw) == n || throw(ArgumentError(
            "encode returned vector of length $(length(raw)); expected n=$n",
        ))
        mat = Matrix{Float64}(undef, n, d)
        for i in 1:n
            row = raw[i]
            if row isa NamedTuple
                for (j, name) in enumerate(code_names)
                    haskey(row, name) || throw(ArgumentError(
                        "encode NamedTuple at row $i missing key :$name",
                    ))
                    mat[i, j] = Float64(row[name])
                end
            elseif row isa AbstractVector
                length(row) == d || throw(ArgumentError(
                    "encode row $i has length $(length(row)); expected d=$d",
                ))
                mat[i, :] .= Float64.(row)
            else
                throw(ArgumentError(
                    "encode row $i must be a NamedTuple or AbstractVector; got $(typeof(row))",
                ))
            end
        end
        return mat
    end
    throw(ArgumentError(
        "encode must return an n×d matrix or length-n vector of rows; got $(typeof(raw))",
    ))
end

export RepresentationSpec, representation_certificate, encode_to_panel
