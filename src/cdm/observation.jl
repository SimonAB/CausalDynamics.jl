"""Latent → observable bridges for panel construction (no filter algorithms).

Callers supply inferred or simulated latent series; this module maps them onto
observed columns for [`simulate_panel`](@ref) / [`CDMPanel`](@ref) hand-off.
"""

"""
    ObservationBridge(mapping; measure=nothing)

Declare how latent (or endogenous) series become estimation columns.

# Fields
- `mapping`: when `measure` is `nothing`, source series symbol → panel symbol;
  when `measure` is set, optional rename of measure output keys → panel symbols
  (missing keys keep their measure names)
- `measure`: optional `(state_nt, t) -> NamedTuple` producing observed values from
  the full endogenous state at occasion `t`
"""
struct ObservationBridge
    mapping::Dict{Symbol, Symbol}
    measure::Any
end

function ObservationBridge(
    mapping::AbstractDict;
    measure = nothing,
)
    return ObservationBridge(
        Dict{Symbol, Symbol}(Symbol(k) => Symbol(v) for (k, v) in mapping),
        measure,
    )
end

"""
    identity_observation(variables) -> ObservationBridge

Bridge that exposes each symbol under its own name (no measurement map).
"""
identity_observation(variables::AbstractVector{Symbol}) =
    ObservationBridge(Dict(v => v for v in variables))

"""
    observe_series(series, bridge) -> Dict{Symbol, Vector{Float64}}

Apply an [`ObservationBridge`](@ref) to a `Dict` of equal-length series.
"""
function observe_series(
    series::Dict{Symbol, <:AbstractVector},
    bridge::ObservationBridge,
)
    isempty(series) && throw(ArgumentError("series dictionary is empty"))
    T = length(first(values(series)))
    for (k, v) in series
        length(v) == T || throw(ArgumentError(
            "series :$k has length $(length(v)), expected $T",
        ))
    end

    out = Dict{Symbol, Vector{Float64}}()
    if bridge.measure === nothing
        for (src, dest) in bridge.mapping
            haskey(series, src) || throw(ArgumentError(
                "bridge source :$src missing; available: $(collect(keys(series)))",
            ))
            out[dest] = Float64.(series[src])
        end
        return out
    end

    keys_src = Tuple(sort!(collect(keys(series))))
    for t in 1:T
        state = NamedTuple{keys_src}(ntuple(i -> series[keys_src[i]][t], length(keys_src)))
        obs = bridge.measure(state, t)
        obs isa NamedTuple || throw(ArgumentError(
            "ObservationBridge.measure must return a NamedTuple; got $(typeof(obs))",
        ))
        for (k, val) in pairs(obs)
            dest = get(bridge.mapping, k, k)
            if !haskey(out, dest)
                out[dest] = Vector{Float64}(undef, T)
            end
            out[dest][t] = Float64(val)
        end
    end
    # Pass through any mapped source series not produced by measure (e.g. covariates)
    for (src, dest) in bridge.mapping
        haskey(out, dest) && continue
        haskey(series, src) || continue
        out[dest] = Float64.(series[src])
    end
    return out
end

"""
    observe_trajectory(traj, bridge) -> Dict{Symbol, Vector{Float64}}

Observe a [`CDMTrajectory`](@ref) endogenous series through `bridge`.
"""
function observe_trajectory(traj::CDMTrajectory, bridge::ObservationBridge)
    return observe_series(traj.series, bridge)
end

"""
    panel_from_trajectories(trajs; baseline, timed, terminal, name_fn, bridge)

Stack trajectories into a [`CDMPanel`](@ref). Optional `bridge` is applied to
each trajectory before wide flattening (latent → observed columns).
"""
function panel_from_trajectories(
    trajs::AbstractVector{CDMTrajectory};
    baseline::AbstractVector{Symbol} = Symbol[],
    timed::Union{Nothing, AbstractVector{Symbol}} = nothing,
    terminal::AbstractVector{Symbol} = Symbol[],
    name_fn = panel_column_name,
    bridge::Union{Nothing, ObservationBridge} = nothing,
    temporal_spec::Union{Nothing, TemporalDAGSpec} = nothing,
)
    isempty(trajs) && throw(ArgumentError("trajs is empty"))
    T = trajs[1].T
    n = length(trajs)
    observed = Vector{Dict{Symbol, Vector{<:Real}}}(undef, n)
    for (i, traj) in enumerate(trajs)
        traj.T == T || throw(ArgumentError("trajectory $i has T=$(traj.T), expected $T"))
        series = bridge === nothing ? traj.series : observe_trajectory(traj, bridge)
        observed[i] = series
    end

    vars = sort!(unique(reduce(vcat, [collect(keys(s)) for s in observed]; init = Symbol[])))
    base = collect(Symbol, baseline)
    term = collect(Symbol, terminal)
    timed_vars = timed === nothing ? setdiff(vars, union(base, term)) : collect(Symbol, timed)
    for v in Iterators.flatten((base, timed_vars, term))
        v in vars || throw(ArgumentError("variable :$v not in observed series keys=$vars"))
    end

    order = _column_order(T, base, timed_vars, term, name_fn)
    data = Dict{Symbol, Vector{Float64}}(c => Vector{Float64}(undef, n) for c in order)
    empty_noise = Dict{Symbol, Vector{<:Real}}()
    for i in 1:n
        row = trajectory_wide_row(
            CDMTrajectory(T, Dict{Symbol, Vector{<:Real}}(observed[i]), empty_noise);
            baseline = base,
            timed = timed_vars,
            terminal = term,
            name_fn = name_fn,
        )
        for c in order
            data[c][i] = row[c]
        end
    end
    return CDMPanel(n, T, data, order, vars, base, timed_vars, term, temporal_spec)
end

"""
    panel_from_latent_series(unit_series; T, bridge, baseline, timed, terminal, name_fn)

Build a panel from pre-inferred latent series (e.g. filter/smoother output).

Each element of `unit_series` is a `Dict{Symbol, <:AbstractVector}` of length `T`
(or of equal length, with `T` taken from the first unit when `T === nothing`).
"""
function panel_from_latent_series(
    unit_series::AbstractVector{<:AbstractDict};
    T::Union{Nothing, Integer} = nothing,
    bridge::Union{Nothing, ObservationBridge} = nothing,
    baseline::AbstractVector{Symbol} = Symbol[],
    timed::Union{Nothing, AbstractVector{Symbol}} = nothing,
    terminal::AbstractVector{Symbol} = Symbol[],
    name_fn = panel_column_name,
    temporal_spec::Union{Nothing, TemporalDAGSpec} = nothing,
)
    isempty(unit_series) && throw(ArgumentError("unit_series is empty"))
    series0 = Dict{Symbol, Vector{<:Real}}(
        Symbol(k) => collect(v) for (k, v) in unit_series[1]
    )
    T_use = T === nothing ? length(first(values(series0))) : Int(T)
    trajs = CDMTrajectory[]
    empty_noise = Dict{Symbol, Vector{<:Real}}()
    for (i, s) in enumerate(unit_series)
        d = Dict{Symbol, Vector{<:Real}}(Symbol(k) => collect(v) for (k, v) in s)
        for (k, v) in d
            length(v) == T_use || throw(ArgumentError(
                "unit $i series :$k length $(length(v)) ≠ T=$T_use",
            ))
        end
        obs = bridge === nothing ? d : observe_series(d, bridge)
        push!(trajs, CDMTrajectory(T_use, obs, empty_noise))
    end
    return panel_from_trajectories(
        trajs;
        baseline = baseline,
        timed = timed,
        terminal = terminal,
        name_fn = name_fn,
        bridge = nothing,
        temporal_spec = temporal_spec,
    )
end

"""
    simulate_observed_panel(cdm, n, T; bridge, kwargs...)

Simulate natural trajectories, apply `bridge`, and stack as a [`CDMPanel`](@ref).
"""
function simulate_observed_panel(
    cdm::DiscreteTimeCDM,
    n::Integer,
    T::Integer;
    bridge::ObservationBridge,
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
    trajs = [simulate(cdm, T; rng = rng, intervention = intervention) for _ in 1:n]
    return panel_from_trajectories(
        trajs;
        baseline = baseline,
        timed = timed,
        terminal = terminal,
        name_fn = name_fn,
        bridge = bridge,
        temporal_spec = temporal_spec,
    )
end

export ObservationBridge, identity_observation
export observe_series, observe_trajectory
export panel_from_trajectories, panel_from_latent_series, simulate_observed_panel
