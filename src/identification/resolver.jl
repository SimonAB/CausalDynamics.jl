"""Map graph nodes to data column names."""

"""
    ColumnResolver

Trait-like API for resolving identification nodes to data columns.
"""
abstract type ColumnResolver end

"""
    IdentityColumnResolver

Pass node labels through unchanged (symbols or indices).
"""
struct IdentityColumnResolver <: ColumnResolver end

"""
    DictColumnResolver(mapping)

Resolve via explicit `node => column` mapping.
"""
struct DictColumnResolver{T} <: ColumnResolver
    mapping::Dict{T, T}
end

"""
    resolve_columns(resolver, nodes, available) -> Vector

Return columns present in `available` that correspond to `nodes`.

- [`IdentityColumnResolver`](@ref): keep `n` when `n in available`.
- [`DictColumnResolver`](@ref): resolve `col = get(r.mapping, n, n)` and keep when `col in available`.
"""
function resolve_columns(::IdentityColumnResolver, nodes::Vector{T}, available::AbstractSet) where {T}
    out = T[]
    for n in nodes
        n in available && push!(out, n)
    end
    return out
end

function resolve_columns(r::DictColumnResolver, nodes::Vector{T}, available::AbstractSet) where {T}
    out = T[]
    for n in nodes
        col = get(r.mapping, n, n)
        col in available && push!(out, col)
    end
    return out
end

"""
    resolve_identification_columns(result, resolver, column_names) -> IdentificationResult

Filter `result.adjustment`, `result.mediators`, and `result.moc` to columns present in `column_names` (as a `Set`), using
[`resolve_columns`](@ref). Query, graph hash, strategy, assumptions, temporal nodes, and missingness metadata are
unchanged. Semantic fingerprint and identification status are preserved as well.
"""
function resolve_identification_columns(
    result::IdentificationResult{T},
    resolver::ColumnResolver,
    column_names,
) where {T}
    avail = Set(column_names)
    adj = resolve_columns(resolver, result.adjustment, avail)
    meds = resolve_columns(resolver, result.mediators, avail)
    moc = resolve_columns(resolver, result.moc, avail)
    return IdentificationResult(
        query = result.query,
        graph_hash = result.graph_hash,
        adjustment = adj,
        mediators = meds,
        moc = moc,
        strategy = result.strategy,
        identifiable = result.identifiable,
        assumptions = result.assumptions,
        temporal_nodes = result.temporal_nodes,
        missingness = result.missingness,
        semantic_fingerprint = result.semantic_fingerprint,
        identification_status = result.identification_status,
    )
end

export ColumnResolver, IdentityColumnResolver, DictColumnResolver
export resolve_columns, resolve_identification_columns
