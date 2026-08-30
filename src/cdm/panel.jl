"""Observational wide panels from discrete-time CDM trajectories.

Column naming (default): baseline symbols kept as-is (value at ``t = 1``);
timed symbols become ``Symbol(string(var), t)`` (e.g. `:a` → `:a1`, `:a2`);
terminal symbols use the bare name at occasion ``T`` (e.g. `:y` at last time).

This layout matches CausalTargeted [`SequentialPolicy`](@ref) wide tables.
"""

"""
    panel_column_name(var, t) -> Symbol

Default time-indexed column name: concatenate the variable symbol and occasion
index with no separator (`:a`, `2` → `:a2`).
"""
panel_column_name(var::Symbol, t::Integer) = Symbol(string(var), Int(t))

"""
    CDMPanel

Wide observational panel from ``n`` independent [`DiscreteTimeCDM`](@ref)
trajectories of length ``T``.

# Fields
- `n`, `T`: dimensions
- `data`: column name → length-`n` vectors
- `column_order`: stable column order for table conversion
- `variables`: endogenous symbols from the CDM
- `baseline`, `timed`, `terminal`: role partition used when building columns
- `temporal_spec`: optional [`TemporalDAGSpec`](@ref) for downstream ID
"""
struct CDMPanel
    n::Int
    T::Int
    data::Dict{Symbol, Vector{Float64}}
    column_order::Vector{Symbol}
    variables::Vector{Symbol}
    baseline::Vector{Symbol}
    timed::Vector{Symbol}
    terminal::Vector{Symbol}
    temporal_spec::Union{Nothing, TemporalDAGSpec}
end

"""
    trajectory_wide_row(traj; baseline, timed, terminal, name_fn) -> Dict{Symbol, Float64}

Flatten one [`CDMTrajectory`](@ref) into a wide named row.
"""
function trajectory_wide_row(
    traj::CDMTrajectory;
    baseline::AbstractVector{Symbol} = Symbol[],
    timed::AbstractVector{Symbol} = Symbol[],
    terminal::AbstractVector{Symbol} = Symbol[],
    name_fn = panel_column_name,
)
    row = Dict{Symbol, Float64}()
    for v in baseline
        haskey(traj.series, v) || throw(ArgumentError(
            "baseline :$v missing from trajectory; available: $(collect(keys(traj.series)))",
        ))
        row[v] = Float64(traj.series[v][1])
    end
    for v in timed
        haskey(traj.series, v) || throw(ArgumentError(
            "timed :$v missing from trajectory; available: $(collect(keys(traj.series)))",
        ))
        for t in 1:traj.T
            row[name_fn(v, t)] = Float64(traj.series[v][t])
        end
    end
    for v in terminal
        haskey(traj.series, v) || throw(ArgumentError(
            "terminal :$v missing from trajectory; available: $(collect(keys(traj.series)))",
        ))
        row[v] = Float64(traj.series[v][end])
    end
    return row
end

function _default_roles(cdm::DiscreteTimeCDM, baseline, timed, terminal)
    vars = cdm.variables
    base = collect(Symbol, baseline)
    term = collect(Symbol, terminal)
    timed_vars = if timed === nothing
        setdiff(vars, union(base, term))
    else
        collect(Symbol, timed)
    end
    for v in Iterators.flatten((base, timed_vars, term))
        v in vars || throw(ArgumentError(
            "variable :$v is not in cdm.variables=$(vars)",
        ))
    end
    return base, timed_vars, term
end

function _column_order(T::Int, baseline, timed, terminal, name_fn)
    order = Symbol[]
    append!(order, baseline)
    for t in 1:T
        for v in timed
            push!(order, name_fn(v, t))
        end
    end
    append!(order, terminal)
    return order
end

"""
    simulate_panel(cdm, n, T; rng, intervention, baseline, timed, terminal, name_fn, temporal_spec)

Simulate `n` independent trajectories and stack them as a wide [`CDMPanel`](@ref).

For observational estimation (CausalTargeted sequential LMTP), leave
`intervention = nothing` so treatments follow the natural mechanism.

# Keyword arguments
- `baseline`: symbols emitted once (value at ``t = 1``), e.g. `[:w]`
- `timed`: symbols expanded as `name_fn(v, t)` for ``t = 1:T``; default is all
  endogenous variables not listed in `baseline` or `terminal`
- `terminal`: symbols emitted once from occasion ``T`` (bare name), e.g. `[:y]`
- `name_fn`: `(var::Symbol, t::Int) -> Symbol` (default [`panel_column_name`](@ref))
- `temporal_spec`: optional lag DAG carried for ID hand-off
"""
function simulate_panel(
    cdm::DiscreteTimeCDM,
    n::Integer,
    T::Integer;
    rng::Random.AbstractRNG = Random.default_rng(),
    intervention::Union{Nothing, AbstractIntervention} = nothing,
    baseline::AbstractVector{Symbol} = Symbol[],
    timed::Union{Nothing, AbstractVector{Symbol}} = nothing,
    terminal::AbstractVector{Symbol} = Symbol[],
    name_fn = panel_column_name,
    temporal_spec::Union{Nothing, TemporalDAGSpec} = nothing,
)
    n = Int(n)
    T = Int(T)
    n < 1 && throw(ArgumentError("n must be ≥ 1, got $n"))
    T < 1 && throw(ArgumentError("T must be ≥ 1, got $T"))

    base, timed_vars, term = _default_roles(cdm, baseline, timed, terminal)
    order = _column_order(T, base, timed_vars, term, name_fn)
    data = Dict{Symbol, Vector{Float64}}(c => Vector{Float64}(undef, n) for c in order)

    for i in 1:n
        traj = simulate(cdm, T; rng = rng, intervention = intervention)
        traj.T == T || throw(ArgumentError("trajectory length $(traj.T) ≠ T=$T"))
        row = trajectory_wide_row(
            traj;
            baseline = base,
            timed = timed_vars,
            terminal = term,
            name_fn = name_fn,
        )
        for c in order
            data[c][i] = row[c]
        end
    end

    return CDMPanel(
        n, T, data, order, copy(cdm.variables), base, timed_vars, term, temporal_spec,
    )
end

"""
    NamedTuple(panel::CDMPanel)

Column-ordered named tuple of vectors (pass to `DataFrame` when DataFrames is loaded).
"""
function Base.NamedTuple(panel::CDMPanel)
    names = Tuple(panel.column_order)
    vals = ntuple(i -> panel.data[panel.column_order[i]], length(panel.column_order))
    return NamedTuple{names}(vals)
end

"""
    check_occasion_resolution(query, measured_at; warn=true) -> Vector{NamedTuple}

Check whether a [`TemporalEffectQuery`](@ref) references variables at occasions
that differ from where they were actually measured in the wide panel.

`measured_at` maps DAG node symbols to the occasion index of the wide column
that holds the value (e.g. period-constant contact scores measured once at
occasion 1 but referenced at `t_outcome = 4`).

Returns a vector of issue records; emits `@warn` when `warn=true`.
"""
function check_occasion_resolution(
    query::TemporalEffectQuery,
    measured_at::AbstractDict{Symbol, Int};
    warn::Bool = true,
)
    issues = NamedTuple[]
    for (var, src_t) in measured_at
        ref_t = if var == query.treatment
            query.t_treat
        elseif var == query.outcome
            query.t_outcome
        else
            continue
        end
        src_t == ref_t && continue
        rec = (
            variable = var,
            query_occasion = ref_t,
            source_occasion = src_t,
            message = ":$(var) at query occasion $ref_t uses measurement from occasion $src_t",
        )
        push!(issues, rec)
        if warn
            @warn rec.message variable = var query_occasion = ref_t source_occasion = src_t
        end
    end
    return issues
end

export panel_column_name, CDMPanel, trajectory_wide_row, simulate_panel, check_occasion_resolution
