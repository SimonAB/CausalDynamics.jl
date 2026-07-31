"""
    ODE parent discovery for continuous CDMs

Rank candidate parent sets for a target continuous-CDM coordinate by
leave-one-environment stability of linear-in-parameters mechanisms
``Ẏ = f(X_S)``. The reference method is CausalKinetiX
[@pfister2019causalkinetix]. The API uses ordinary dynamical language
(ODE parents / continuous CDM); reserve “invariant” for prose that glosses
cross-environment mechanism stability, not as the standing name.

Differentiation defaults to finite differences; load `DataInterpolations` for
cubic-spline derivatives via the package extension.
"""

"""
    ODEParentRanking

Result of [`infer_ode_parents`](@ref): candidate parent-index sets, their
cross-environment instability scores (lower is better), per-variable inclusion
scores, and a variable ranking (best first).
"""
struct ODEParentRanking
    models::Vector{Vector{Int}}
    model_scores::Vector{Float64}
    variable_scores::Vector{Float64}
    ranking::Vector{Int}
    target::Int
end

"""
    has_data_interpolations() -> Bool

Return `true` when the DataInterpolations extension is loaded.
"""
function has_data_interpolations()
    return !isnothing(Base.get_extension(@__MODULE__, :CausalDynamicsDataInterpolationsExt))
end

function _require_data_interpolations!(f::Symbol)
    ext = Base.get_extension(@__MODULE__, :CausalDynamicsDataInterpolationsExt)
    ext === nothing && error(
        "DataInterpolations extension is not loaded. Run: using DataInterpolations\n" *
        "Then call CausalDynamics.$f(...). See docs/METHODS_ADOPTION.md.",
    )
    return ext
end

"""
    _index_combinations(xs, k) -> Vector{Vector{Int}}

Unordered combinations of length `k` from `xs` (no Combinatorics.jl dependency).
"""
function _index_combinations(xs::Vector{Int}, k::Integer)
    n = length(xs)
    k > n && return Vector{Vector{Int}}()
    k < 1 && return Vector{Vector{Int}}()
    out = Vector{Vector{Int}}()
    c = collect(1:k)
    while true
        push!(out, xs[c])
        i = k
        while i ≥ 1 && c[i] == n - k + i
            i -= 1
        end
        i < 1 && break
        c[i] += 1
        for j in (i + 1):k
            c[j] = c[j - 1] + 1
        end
    end
    return out
end

"""
    candidate_parent_sets(d; max_size=2) -> Vector{Vector{Int}}

All non-empty subsets of `{1,…,d}` with size at most `max_size` (1-based indices).
"""
function candidate_parent_sets(d::Integer; max_size::Integer = 2)
    d < 1 && throw(ArgumentError("d must be ≥ 1"))
    max_size < 1 && throw(ArgumentError("max_size must be ≥ 1"))
    models = Vector{Int}[]
    idxs = collect(1:d)
    for k in 1:min(max_size, d)
        append!(models, _index_combinations(idxs, k))
    end
    return models
end

"""
    finite_difference_derivative(t, y) -> Vector{Float64}

Central finite differences on possibly irregular grids (one-sided at endpoints).
"""
function finite_difference_derivative(t::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    length(t) == length(y) || throw(ArgumentError("t and y length mismatch"))
    n = length(t)
    n < 2 && throw(ArgumentError("need at least 2 time points"))
    dy = Vector{Float64}(undef, n)
    dy[1] = (Float64(y[2]) - Float64(y[1])) / (Float64(t[2]) - Float64(t[1]))
    @inbounds for i in 2:(n - 1)
        dy[i] = (Float64(y[i + 1]) - Float64(y[i - 1])) / (Float64(t[i + 1]) - Float64(t[i - 1]))
    end
    dy[n] = (Float64(y[n]) - Float64(y[n - 1])) / (Float64(t[n]) - Float64(t[n - 1]))
    return dy
end

"""
    _ols_with_intercept(X, y) -> (β, fitted)

Ordinary least squares of `y` on `X` with an intercept column.
"""
function _ols_with_intercept(X::AbstractMatrix{<:Real}, y::AbstractVector{<:Real})
    n = size(X, 1)
    length(y) == n || throw(ArgumentError("X/y row mismatch"))
    A = hcat(ones(n), Matrix{Float64}(X))
    β = A \ Vector{Float64}(y)
    return β, A * β
end

"""
    _loo_env_derivative_score(X_by_env, dY_by_env) -> Float64

Leave-one-environment-out instability score
``T = mean_e ‖dY_e - X_e β_{-e}‖² / ‖dY_e - mean(dY_e)‖²``
(lower means more stable prediction across held-out environments).
"""
function _loo_env_derivative_score(
    X_by_env::Vector{<:AbstractMatrix{<:Real}},
    dY_by_env::Vector{<:AbstractVector{<:Real}},
)
    E = length(X_by_env)
    E == length(dY_by_env) || throw(ArgumentError("environment count mismatch"))
    E < 2 && throw(ArgumentError("need ≥ 2 environments for leave-one-out scoring"))
    scores = Vector{Float64}(undef, E)
    for e in 1:E
        Xtr = vcat((X_by_env[j] for j in 1:E if j != e)...)
        ytr = vcat((dY_by_env[j] for j in 1:E if j != e)...)
        β, _ = _ols_with_intercept(Xtr, ytr)
        Xe = hcat(ones(size(X_by_env[e], 1)), Matrix{Float64}(X_by_env[e]))
        pred = Xe * β
        ye = Vector{Float64}(dY_by_env[e])
        rss_b = sum(abs2, ye .- pred)
        μ = sum(ye) / length(ye)
        rss_a = sum(abs2, ye .- μ)
        scores[e] = rss_a < 1e-12 ? rss_b : (rss_b - rss_a) / rss_a
    end
    return sum(scores) / E
end

"""
    aggregate_parent_inclusion(models, model_scores; K=nothing, n_variables=nothing)

Inclusion frequency among the `K` lowest-scoring models (default: about one
third of the model list). Returns `(variable_scores, ranking)` where `ranking`
lists variable indices best-first.
"""
function aggregate_parent_inclusion(
    models::AbstractVector{<:AbstractVector{<:Integer}},
    model_scores::AbstractVector{<:Real};
    K::Union{Nothing, Integer} = nothing,
    n_variables::Union{Nothing, Integer} = nothing,
)
    length(models) == length(model_scores) || throw(ArgumentError("models/scores length mismatch"))
    d = if n_variables === nothing
        maximum(maximum(m; init = 0) for m in models; init = 0)
    else
        Int(n_variables)
    end
    d < 1 && return (Float64[], Int[])
    order = sortperm(model_scores)
    k = K === nothing ? max(1, cld(length(models), 3)) : Int(K)
    k = clamp(k, 1, length(models))
    vs = zeros(Float64, d)
    @inbounds for idx in @view order[1:k]
        for j in models[idx]
            vs[j] += 1
        end
    end
    vs ./= k
    ranking = sortperm(vs; rev = true)
    return vs, ranking
end

"""
    score_ode_parent_sets(times, trajectories, env, target, models; differentiate=nothing)

Score each candidate parent-index set for target coordinate `target`.

# Arguments
- `times`: length-`L` observation grid
- `trajectories`: vector of `d × L` matrices (one per repetition)
- `env`: environment id per repetition
- `target`: 1-based target coordinate
- `models`: candidate parent-index sets
- `differentiate`: `(t, y) -> dy` (defaults to [`finite_difference_derivative`](@ref))
"""
function score_ode_parent_sets(
    times::AbstractVector{<:Real},
    trajectories::AbstractVector{<:AbstractMatrix{<:Real}},
    env::AbstractVector{<:Integer},
    target::Integer,
    models::AbstractVector{<:AbstractVector{<:Integer}};
    differentiate = nothing,
)
    length(trajectories) == length(env) || throw(ArgumentError("trajectories/env length mismatch"))
    isempty(trajectories) && throw(ArgumentError("empty trajectories"))
    d, L = size(trajectories[1])
    length(times) == L || throw(ArgumentError("times length must equal L"))
    (1 ≤ target ≤ d) || throw(ArgumentError("target out of range"))
    for (i, traj) in pairs(trajectories)
        size(traj) == (d, L) || throw(ArgumentError(
            "trajectory $i has size $(size(traj)); expected ($d, $L)",
        ))
    end
    for S in models
        for j in S
            (1 ≤ j ≤ d) || throw(ArgumentError("parent index $j out of range 1:$d"))
        end
    end
    diff_fn = differentiate === nothing ? finite_difference_derivative : differentiate
    t = collect(Float64, times)

    envs = sort!(unique(env))
    X_by_env = Matrix{Float64}[]
    dY_by_env = Vector{Float64}[]
    sizehint!(X_by_env, length(envs))
    sizehint!(dY_by_env, length(envs))
    for e in envs
        reps = [trajectories[i] for i in eachindex(env) if env[i] == e]
        Xmean = sum(reps) ./ length(reps)
        y = vec(Xmean[target, :])
        dy = diff_fn(t, y)
        push!(X_by_env, Matrix(transpose(Xmean)))  # L × d
        push!(dY_by_env, dy)
    end

    scores = Vector{Float64}(undef, length(models))
    for (m, S) in enumerate(models)
        Xs = [view(X_by_env[e], :, S) for e in eachindex(X_by_env)]
        scores[m] = _loo_env_derivative_score(Xs, dY_by_env)
    end
    return scores
end

"""
    infer_ode_parents(times, trajectories, env, target; max_size=2, K=nothing)

Infer an [`ODEParentRanking`](@ref) for main-effect parent sets of `target`.

Uses cubic-spline derivatives when DataInterpolations is loaded; otherwise finite
differences. Reference method: CausalKinetiX [@pfister2019causalkinetix].
"""
function infer_ode_parents(
    times::AbstractVector{<:Real},
    trajectories::AbstractVector{<:AbstractMatrix{<:Real}},
    env::AbstractVector{<:Integer},
    target::Integer;
    max_size::Integer = 2,
    K::Union{Nothing, Integer} = nothing,
)
    d = size(trajectories[1], 1)
    models = [
        m for m in candidate_parent_sets(d; max_size = max_size)
        if !(length(m) == 1 && only(m) == target)
    ]
    differentiate = if has_data_interpolations()
        _require_data_interpolations!(:infer_ode_parents).spline_derivative
    else
        nothing
    end
    scores = score_ode_parent_sets(
        times, trajectories, env, target, models;
        differentiate = differentiate,
    )
    vs, ranking = aggregate_parent_inclusion(models, scores; K = K, n_variables = d)
    return ODEParentRanking(models, scores, vs, ranking, Int(target))
end

"""
    ode_parent_ranking_to_continuous_spec(result, variables; max_parents=2) -> ContinuousCDMSpec

Map an [`ODEParentRanking`](@ref) onto a [`ContinuousCDMSpec`](@ref) parent map
for the ranked target.
"""
function ode_parent_ranking_to_continuous_spec(
    result::ODEParentRanking,
    variables::AbstractVector{Symbol};
    max_parents::Integer = 2,
)
    length(variables) == length(result.variable_scores) || throw(ArgumentError(
        "variables length must match ODE parent ranking dimension",
    ))
    target = variables[result.target]
    ranks = similar(result.ranking)
    for (r, j) in enumerate(result.ranking)
        ranks[j] = r
    end
    parents = ranked_variables_to_parents(
        ranks, variables; target = target, max_parents = max_parents,
    )
    return ContinuousCDMSpec(variables; parents = parents)
end

export ODEParentRanking,
    has_data_interpolations,
    candidate_parent_sets,
    finite_difference_derivative,
    score_ode_parent_sets,
    infer_ode_parents,
    ode_parent_ranking_to_continuous_spec,
    aggregate_parent_inclusion
