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
    return IdentificationResult{eltype(result.adjustment)}(
        result.query,
        result.graph_hash,
        adj,
        meds,
        moc,
        result.strategy,
        result.identifiable,
        result.assumptions,
        result.temporal_nodes,
        result.missingness,
    )
end

export ColumnResolver, IdentityColumnResolver, DictColumnResolver
export resolve_columns, resolve_identification_columns
