"""Map temporal identification certificates to wide-panel column names."""

"""
    OutcomeKind

Outcome family for a DAG node when planning targeted estimation.

Use `OutcomeKind.count_outcome` for nonnegative count nodes (Poisson /
negative binomial routing is reserved for a later planner release).
"""
@enum OutcomeKind begin
    gaussian
    binary
    count_outcome
    hurdle
end

"""
    NodeOutcomeSpec(kind; presence_var=nothing, intensity_var=nothing)

Metadata for how a temporal node is observed in wide panels. For hurdle
outcomes (`OutcomeKind.hurdle`), `presence_var` and `intensity_var` name the
wide-table base symbols (time suffix added via [`panel_column_name`](@ref)).
"""
struct NodeOutcomeSpec
    kind::OutcomeKind
    presence_var::Union{Nothing, Symbol}
    intensity_var::Union{Nothing, Symbol}

    NodeOutcomeSpec(kind::OutcomeKind) = new(kind, nothing, nothing)
    function NodeOutcomeSpec(
        kind::OutcomeKind,
        presence_var::Symbol,
        intensity_var::Symbol,
    )
        return new(kind, presence_var, intensity_var)
    end
end

function _outcome_spec(
    outcome_specs::Dict{Symbol, NodeOutcomeSpec},
    var::Symbol,
)
    return get(outcome_specs, var, NodeOutcomeSpec(gaussian))
end

function _hurdle_panel_columns(
    spec::NodeOutcomeSpec,
    query::TemporalEffectQuery,
    unit::Set{Symbol},
    name_fn,
)
    pres_var = spec.presence_var
    int_var = spec.intensity_var
    pres_var === nothing && throw(ArgumentError(
        "hurdle NodeOutcomeSpec for :$(query.outcome) requires presence_var",
    ))
    int_var === nothing && throw(ArgumentError(
        "hurdle NodeOutcomeSpec for :$(query.outcome) requires intensity_var",
    ))
    presence_col = pres_var in unit ? pres_var : name_fn(pres_var, query.t_outcome)
    intensity_col = int_var in unit ? int_var : name_fn(int_var, query.t_outcome)
    return (presence = presence_col, intensity = intensity_col)
end

"""
    temporal_adjustment_columns(result, unrolling; unit_level, skip, name_fn) -> Vector{Symbol}

Map `result.temporal_nodes` (pairs `(variable, occasion)`) to wide-table column
symbols using [`panel_column_name`](@ref) by default.

Unit-level variables (e.g. randomised arm labels that do not vary by occasion)
can be listed in `unit_level`; they map to the bare symbol regardless of `t`.
Symbols in `skip` are omitted (e.g. `:sex` on sex-stratified panels).
"""
function temporal_adjustment_columns(
    result::IdentificationResult,
    unrolling::TemporalUnrolling;
    unit_level::AbstractVector{Symbol} = Symbol[],
    skip::AbstractVector{Symbol} = [:sex],
    name_fn = panel_column_name,
)
    unit = Set(unit_level)
    omit = Set(skip)
    cols = Symbol[]
    seen = Set{Symbol}()
    for (var, t) in result.temporal_nodes
        var in omit && continue
        col = if var in unit
            var
        else
            name_fn(var, t)
        end
        if col in seen
            continue
        end
        push!(cols, col)
        push!(seen, col)
    end
    return cols
end

"""
    adjustment_columns(unrolling, query; kwargs...) -> Vector{Symbol}

Identify a [`TemporalEffectQuery`](@ref) on `unrolling` and return wide baseline
column names for estimation (convenience wrapper around
[`temporal_adjustment_columns`](@ref)).
"""
function adjustment_columns(
    unrolling::TemporalUnrolling,
    query::TemporalEffectQuery;
    missingness = nothing,
    kwargs...,
)
    result = identify(unrolling, query; missingness = missingness)
    return temporal_adjustment_columns(result, unrolling; kwargs...)
end

"""
    query_panel_columns(query::TemporalEffectQuery; unit_level, name_fn) -> NamedTuple

Wide columns for treatment and outcome implied by a temporal query.
"""
function query_panel_columns(
    query::TemporalEffectQuery;
    unit_level::AbstractVector{Symbol} = Symbol[],
    name_fn = panel_column_name,
    outcome_specs::Dict{Symbol, NodeOutcomeSpec} = Dict{Symbol, NodeOutcomeSpec}(),
)
    unit = Set(unit_level)
    treat_col = query.treatment in unit ? query.treatment :
        name_fn(query.treatment, query.t_treat)
    spec = _outcome_spec(outcome_specs, query.outcome)
    if spec.kind == hurdle
        hurdle_cols = _hurdle_panel_columns(spec, query, unit, name_fn)
        out_col = hurdle_cols.presence
    else
        out_col = query.outcome in unit ? query.outcome :
            name_fn(query.outcome, query.t_outcome)
    end
    return (treatment = treat_col, outcome = out_col)
end

"""
    EstimationPlan

Planner output linking temporal identification to a CausalTargeted engine and
wide-panel column names.
"""
struct EstimationPlan
    engine::Symbol
    treatment::Symbol
    outcome::Symbol
    presence_col::Union{Nothing, Symbol}
    intensity_col::Union{Nothing, Symbol}
    baseline::Vector{Symbol}
    query::TemporalEffectQuery
    identifiable::Bool
    strategy::Symbol
    adjustment_columns::Vector{Symbol}
    missing_columns::Vector{Symbol}
end

function EstimationPlan(
    engine::Symbol,
    treatment::Symbol,
    outcome::Symbol,
    baseline::Vector{Symbol},
    query::TemporalEffectQuery,
    identifiable::Bool,
    strategy::Symbol,
    adjustment_columns::Vector{Symbol},
    missing_columns::Vector{Symbol};
    presence_col::Union{Nothing, Symbol} = nothing,
    intensity_col::Union{Nothing, Symbol} = nothing,
)
    return EstimationPlan(
        engine, treatment, outcome, presence_col, intensity_col,
        baseline, query, identifiable, strategy,
        adjustment_columns, missing_columns,
    )
end

function Base.show(io::IO, plan::EstimationPlan)
    hurdle = plan.presence_col !== nothing ? ", hurdle" : ""
    print(io, "EstimationPlan(", plan.engine, ", ",
        plan.treatment, " → ", plan.outcome, hurdle,
        ", baseline=", length(plan.baseline), " cols",
        plan.identifiable ? "" : " [not identifiable]", ")")
end

"""
    _targeted_engine_for_query(query, discrete_treatment, outcome_spec) -> Symbol

Choose a default CausalTargeted runner symbol for a temporal query.
"""
function _targeted_engine_for_query(
    query::TemporalEffectQuery,
    discrete_treatment::Bool,
    outcome_spec::NodeOutcomeSpec = NodeOutcomeSpec(gaussian),
)
    if outcome_spec.kind == hurdle
        return :two_part_discrete_lmtp
    end
    if query.t_treat == query.t_outcome
        return discrete_treatment ? :discrete_lmtp : :lmtp_grid
    end
    if query.treatment == query.outcome && query.t_treat < query.t_outcome
        return :sequential_lmtp
    end
    return :lmtp_grid
end

"""
    plan_targeted_estimation(unrolling, query, column_names; ...)

Run temporal identification and return an [`EstimationPlan`](@ref) with engine
choice (`:discrete_lmtp`, `:two_part_discrete_lmtp`, `:lmtp_grid`,
`:sequential_lmtp`), treatment/outcome columns, and adjustment columns present in
`column_names`.

`discrete_treatment=true` (default) selects `:discrete_lmtp` for same-occasion
contrasts; set `false` for continuous shift LMTP.

`outcome_specs` maps DAG node symbols to [`NodeOutcomeSpec`](@ref); hurdle nodes
populate `presence_col` and `intensity_col` for two-part LMTP runners.
"""
function plan_targeted_estimation(
    unrolling::TemporalUnrolling,
    query::TemporalEffectQuery,
    column_names;
    missingness = nothing,
    unit_level::AbstractVector{Symbol} = Symbol[],
    skip::AbstractVector{Symbol} = [:sex],
    name_fn = panel_column_name,
    discrete_treatment::Bool = true,
    outcome_specs::Dict{Symbol, NodeOutcomeSpec} = Dict{Symbol, NodeOutcomeSpec}(),
)
    result = identify(unrolling, query; missingness = missingness)
    unit = Set(unit_level)
    outcome_spec = _outcome_spec(outcome_specs, query.outcome)
    qcols = query_panel_columns(
        query;
        unit_level = unit_level,
        name_fn = name_fn,
        outcome_specs = outcome_specs,
    )
    baseline = temporal_adjustment_columns(
        result, unrolling;
        unit_level = unit_level, skip = skip, name_fn = name_fn,
    )
    avail = Set(column_names)
    present = Symbol[c for c in baseline if c in avail]
    missing_cols = Symbol[c for c in baseline if !(c in avail)]
    presence_col = nothing
    intensity_col = nothing
    if outcome_spec.kind == hurdle
        hurdle_cols = _hurdle_panel_columns(outcome_spec, query, unit, name_fn)
        presence_col = hurdle_cols.presence
        intensity_col = hurdle_cols.intensity
    end
    engine = _targeted_engine_for_query(query, discrete_treatment, outcome_spec)
    return EstimationPlan(
        engine,
        qcols.treatment,
        qcols.outcome,
        present,
        query,
        result.identifiable,
        result.strategy,
        present,
        missing_cols;
        presence_col = presence_col,
        intensity_col = intensity_col,
    )
end

export OutcomeKind, NodeOutcomeSpec
export temporal_adjustment_columns, adjustment_columns, query_panel_columns
export EstimationPlan, plan_targeted_estimation

"""
    identification_support(data, columns; min_n=10) -> NamedTuple

Empirical support for an adjustment / analysis column set on a row-aligned
`NamedTuple` or `DataFrame`-like object (columns as vectors).

Returns `min_complete_n` (complete cases across `columns`) and `estimability`
(`:ok`, `:underpowered`, or `:empty` when no rows remain).
"""
function identification_support(
    data,
    columns::AbstractVector{Symbol};
    min_n::Int = 10,
)
    cols = collect(columns)
    isempty(cols) && return (min_complete_n = length(_column_vec(data, first(propertynames(data)))), estimability = :ok)
    n = length(_column_vec(data, cols[1]))
    complete = trues(n)
    for c in cols
        v = _column_vec(data, c)
        length(v) == n || throw(ArgumentError("column :$c length $(length(v)) ≠ $n"))
        for i in 1:n
            complete[i] = complete[i] && !_ismissing_or_nan(v[i])
        end
    end
    min_complete_n = Base.count(complete)
    estimability = if min_complete_n == 0
        :empty
    elseif min_complete_n < min_n
        :underpowered
    else
        :ok
    end
    return (min_complete_n = min_complete_n, estimability = estimability)
end

_ismissing_or_nan(x) = ismissing(x) || (x isa Real && !isfinite(x))

function _column_vec(data, col::Symbol)
    if data isa NamedTuple
        return getproperty(data, col)
    elseif hasproperty(data, col)
        return getproperty(data, col)
    else
        throw(ArgumentError("column :$col not found"))
    end
end

export identification_support
