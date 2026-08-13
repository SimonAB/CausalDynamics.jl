"""
    d_separated(g, X, Y, Z)

Check if nodes `X` and `Y` are d-separated by set `Z` in directed acyclic graph `g`.

Delegates to `CausalInference.dsep`.

# Arguments
- `g`: A directed acyclic graph (DiGraph)
- `X`: Source node or set of nodes
- `Y`: Target node or set of nodes
- `Z`: Conditioning set (vector, set, or single node)

# Returns
- `true` if X and Y are d-separated by Z, `false` otherwise
"""
function d_separated(g::AbstractGraph, X, Y, Z)
    X_set = _as_node_set(X)
    Y_set = _as_node_set(Y)
    Z_set = _as_node_set(Z)

    if !isempty(intersect(X_set, Y_set))
        return true
    end

    return CausalInference.dsep(g, X_set, Y_set, Z_set)
end

function _as_node_set(x::Set)
    return x
end
function _as_node_set(x::AbstractVector)
    return Set(x)
end
function _as_node_set(x::Integer)
    return Set([x])
end
function _as_node_set(::Nothing)
    return Set{Int}()
end

"""
Internal helper for path enumeration: whether `Z` blocks a node sequence `path`.
"""
function _is_path_blocked(g::AbstractGraph, path::Vector{Int}, Z::Set)
    n = length(path)
    n < 3 && return false

    for i in 2:(n - 1)
        node = path[i]
        prev, nxt = path[i - 1], path[i + 1]
        is_collider = has_edge(g, prev, node) && has_edge(g, nxt, node)
        if is_collider
            if node in Z
                continue
            end
            desc = get_descendants(g, node)
            if !isempty(intersect(desc, Z))
                continue
            end
            return true
        else
            if node in Z
                return true
            end
        end
    end
    return false
end

export d_separated
