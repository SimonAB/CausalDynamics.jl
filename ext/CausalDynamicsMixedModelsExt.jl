"""Optional repeated-outcome g-computation with MixedModels.jl."""
module CausalDynamicsMixedModelsExt

using CausalDynamics
using DataFrames
using FastGaussQuadrature
using Graphs: AbstractGraph
using LinearAlgebra
using MixedModels
using NLopt
using Random
using SpecialFunctions

const SupportedMixedModel = Union{
    LinearMixedModel,
    GeneralizedLinearMixedModel,
    NB2RandomInterceptModel,
}

function _validate_columns(data::DataFrame, columns)
    available = Set(propertynames(data))
    for column in columns
        column in available || throw(ArgumentError(
            "column :$column is missing from data; available columns are " *
            "$(collect(propertynames(data)))",
        ))
    end
    return nothing
end

function _validate_values(values)
    applicable(length, values) || throw(ArgumentError(
        "values must contain exactly two static intervention values",
    ))
    length(values) == 2 || throw(ArgumentError(
        "values must contain exactly two static intervention values; got $(length(values))",
    ))
    isequal(values[1], values[2]) && throw(ArgumentError(
        "the two intervention values must be distinct; got $(repr(values[1])) twice",
    ))
    return (values[1], values[2])
end

function _validate_random_effects(random_effects)
    random_effects isa Symbol || throw(ArgumentError(
        "random_effects must be :zero or :marginal; got $(repr(random_effects))",
    ))
    random_effects in (:zero, :marginal) || throw(ArgumentError(
        "random_effects must be :zero or :marginal; got $(repr(random_effects))",
    ))
    return random_effects
end

function _family_link(model::GeneralizedLinearMixedModel)
    family = MixedModels.Distributions.Distribution(model)
    link = MixedModels.GLM.Link(model)
    return family, link
end

function _validate_glmm_family_link(model::GeneralizedLinearMixedModel)
    family, link = _family_link(model)
    family_name = string(family)
    link_name = string(typeof(link))
    family <: MixedModels.Distributions.NegativeBinomial || throw(ArgumentError(
        "unsupported GeneralizedLinearMixedModel family $family_name with link " *
        "$link_name; only fixed-shape NB2 NegativeBinomial with LogLink is supported",
    ))
    link isa LogLink || throw(ArgumentError(
        "unsupported GeneralizedLinearMixedModel family $family_name with link " *
        "$link_name; negative-binomial models require LogLink",
    ))
    return nothing
end

function _validate_complete_finite(data::DataFrame, columns)
    for column in columns
        values = data[!, column]
        any(ismissing, values) && throw(ArgumentError(
            "column :$column contains missing values required for prediction",
        ))
        for value in values
            if value isa Real && !isfinite(value)
                throw(ArgumentError(
                    "column :$column contains a non-finite value required for prediction",
                ))
            end
        end
    end
    return nothing
end


function _validate_static_treatment(data::DataFrame, treatment::Symbol, id::Symbol)
    observed = Dict{Any, Any}()
    for row in eachrow(data)
        unit = row[id]
        value = row[treatment]
        if haskey(observed, unit) && !isequal(observed[unit], value)
            throw(ArgumentError(
                "treatment :$treatment must be static within :$id; unit " *
                "$(repr(unit)) has both $(repr(observed[unit])) and $(repr(value))",
            ))
        end
        observed[unit] = value
    end
    return nothing
end

function _normalize_strata(strata)
    columns = if strata === nothing
        Symbol[]
    elseif strata isa Symbol
        [strata]
    elseif strata isa Tuple && all(x -> x isa Symbol, strata)
        collect(Symbol, strata)
    else
        throw(ArgumentError(
            "strata must be nothing, a column Symbol, or a tuple of column Symbols",
        ))
    end
    isempty(columns) && strata !== nothing && throw(ArgumentError(
        "strata must contain at least one column Symbol",
    ))
    length(unique(columns)) == length(columns) || throw(ArgumentError(
        "strata contains duplicate columns: $columns",
    ))
    return columns
end

function _fresh_group_level(values)
    present = Set(values)
    nonmissing = collect(skipmissing(values))
    isempty(nonmissing) && throw(ArgumentError("ID column must contain at least one value"))
    sample = first(nonmissing)

    if sample isa Integer && !(sample isa Bool)
        candidate = BigInt(maximum(nonmissing)) + 1
        converted = try
            convert(typeof(sample), candidate)
        catch
            nothing
        end
        converted !== nothing && !(converted in present) && return converted
    elseif sample isa AbstractFloat
        candidate = nextfloat(maximum(nonmissing))
        isfinite(candidate) && !(candidate in present) && return candidate
    elseif sample isa AbstractString
        prefix = "__causaldynamics_population__"
        candidate = prefix
        suffix = 0
        while candidate in present
            suffix += 1
            candidate = string(prefix, suffix)
        end
        return candidate
    elseif sample isa Symbol
        prefix = "__causaldynamics_population__"
        candidate = Symbol(prefix)
        suffix = 0
        while candidate in present
            suffix += 1
            candidate = Symbol(prefix, suffix)
        end
        return candidate
    end

    candidate = "__causaldynamics_population__"
    candidate in present && (candidate *= "1")
    return candidate
end

function _formula_variables(model)
    return Set(Symbol.(MixedModels.StatsModels.termvars(formula(model))))
end

function _validate_model(
    model::SupportedMixedModel,
    data::DataFrame,
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    adjustment,
    strata,
)
    response = Symbol(responsename(model))
    response == outcome || throw(ArgumentError(
        "outcome :$outcome does not match the fitted model response :$response",
    ))

    grouping = unique(fnames(model))
    grouping == [id] || grouping == (id,) || throw(ArgumentError(
        "population standardization currently requires :$id to be the model's only " *
        "grouping factor; fitted grouping factors are $(collect(grouping))",
    ))

    variables = _formula_variables(model)
    required = unique([
        outcome, treatment, time, id, Symbol.(adjustment)..., Symbol.(strata)...,
    ])
    omitted = setdiff(required, variables)
    isempty(omitted) || throw(ArgumentError(
        "the fitted MixedModels formula omits required variables $(collect(omitted)); " *
        "graph-derived adjustment variables must be included explicitly",
    ))
    _validate_columns(data, required)
    _validate_columns(data, variables)
    _validate_complete_finite(data, variables)
    return nothing
end

function _intervention_data(
    data::DataFrame,
    treatment::Symbol,
    id::Symbol,
    value,
    population_level,
)
    intervened = copy(data)
    try
        intervened[!, treatment] .= value
    catch error
        throw(ArgumentError(
            "intervention value $(repr(value)) is incompatible with treatment " *
            "column :$treatment: $error",
        ))
    end
    intervened[!, id] = fill(population_level, nrow(intervened))
    return intervened
end

function _fixed_effect_design(model::SupportedMixedModel, prediction_data::DataFrame)
    model_names = String.(coefnames(model))
    rhs = formula(model).rhs
    terms = rhs isa Tuple ? rhs : (rhs,)
    matches = Tuple{Any, Vector{String}}[]
    encountered = Vector{String}[]

    for term in terms
        names = try
            raw_names = MixedModels.StatsModels.coefnames(term)
            raw_names isa AbstractString ? [String(raw_names)] : String.(raw_names)
        catch
            continue
        end
        push!(encountered, names)
        names == model_names && push!(matches, (term, names))
    end

    length(matches) == 1 || throw(ArgumentError(
        "could not uniquely align fitted coefficient names $model_names with the " *
        "fixed-effect formula terms $(encountered); refusing covariance calculation",
    ))
    fixed_term = only(matches)[1]
    design = try
        Matrix{Float64}(MixedModels.StatsModels.modelcols(fixed_term, prediction_data))
    catch error
        throw(ArgumentError("could not construct the fixed-effect prediction matrix: $error"))
    end

    size(design) == (nrow(prediction_data), length(model_names)) || throw(ArgumentError(
        "fixed-effect design has size $(size(design)), but prediction data and fitted " *
        "coefficients require ($(nrow(prediction_data)), $(length(model_names)))",
    ))
    all(isfinite, design) || throw(ArgumentError(
        "fixed-effect prediction matrix contains non-finite values",
    ))
    return design
end

function _validate_design_predictions(model, design, predictions; scale_name="prediction")
    all(x -> x isa Real && isfinite(x), predictions) || throw(ArgumentError(
        "MixedModels returned missing or non-finite $scale_name values",
    ))
    coefficients = Float64.(coef(model))
    length(coefficients) == size(design, 2) || throw(ArgumentError(
        "fixed-effect coefficient and design-matrix dimensions do not align",
    ))
    all(isfinite, coefficients) || throw(ArgumentError(
        "fitted fixed-effect coefficients contain non-finite values",
    ))
    design_predictions = design * coefficients
    scale = max(1.0, maximum(abs, predictions), maximum(abs, design_predictions))
    tolerance = 512eps(Float64) * scale
    all(abs.(design_predictions .- predictions) .<= tolerance) || throw(ArgumentError(
        "fixed-effect design columns do not reproduce MixedModels $scale_name values; " *
        "refusing covariance calculation because coefficient alignment is uncertain",
    ))
    return nothing
end


function _prediction_components(
    model::LinearMixedModel,
    prediction_data::DataFrame,
    design::Matrix{Float64},
    random_effects::Symbol,
)
    predictions = predict(model, prediction_data; new_re_levels = :population)
    _validate_design_predictions(
        model, design, predictions; scale_name = "population predictions",
    )
    return Float64.(predictions), false
end

function _random_intercept_variance(model::GeneralizedLinearMixedModel)
    variance_components = VarCorr(model).σρ
    length(variance_components) == 1 || throw(ArgumentError(
        "random_effects=:marginal currently requires exactly one random-intercept " *
        "grouping factor",
    ))
    component = only(values(variance_components))
    standard_deviations = component.σ
    names = propertynames(standard_deviations)
    names == (Symbol("(Intercept)"),) || throw(ArgumentError(
        "random_effects=:marginal currently supports a single random intercept only; " *
        "fitted random-effect columns are $(collect(names))",
    ))
    standard_deviation = Float64(only(values(standard_deviations)))
    isfinite(standard_deviation) && standard_deviation >= 0 || throw(ArgumentError(
        "fitted random-intercept standard deviation is invalid: $standard_deviation",
    ))
    return standard_deviation^2
end

function _prediction_components(
    model::GeneralizedLinearMixedModel,
    prediction_data::DataFrame,
    design::Matrix{Float64},
    random_effects::Symbol,
)
    eta = predict(
        model,
        prediction_data;
        new_re_levels = :population,
        type = :linpred,
    )
    _validate_design_predictions(model, design, eta; scale_name = "link-scale predictions")

    response = predict(
        model,
        prediction_data;
        new_re_levels = :population,
        type = :response,
    )
    all(x -> x isa Real && isfinite(x), response) || throw(ArgumentError(
        "MixedModels returned missing or non-finite response-scale predictions",
    ))
    expected_response = exp.(Float64.(eta))
    scale = max(1.0, maximum(abs, response), maximum(abs, expected_response))
    tolerance = 512eps(Float64) * scale
    all(abs.(response .- expected_response) .<= tolerance) || throw(ArgumentError(
        "MixedModels response-scale predictions do not equal exp(link-scale prediction) " *
        "for the validated LogLink model",
    ))

    predictions = Float64.(response)
    if random_effects == :marginal
        variance = _random_intercept_variance(model)
        predictions .*= exp(0.5variance)
    end
    return predictions, true
end

function _sorted_unique(values, column::Symbol)
    result = unique(values)
    try
        sort!(result)
    catch error
        throw(ArgumentError(
            "observed values in :$column must have a stable sort order: $error",
        ))
    end
    return result
end

function _stratum_identifier(row, strata)
    length(strata) == 1 && return row[only(strata)]
    names = Tuple(strata)
    return NamedTuple{names}(Tuple(row[column] for column in strata))
end

function _stratum_groups(data::DataFrame, strata)
    isempty(strata) && return (Any[nothing], [collect(1:nrow(data))])
    identifiers = [_stratum_identifier(row, strata) for row in eachrow(data)]
    levels = unique(identifiers)
    try
        sort!(levels; by = x -> x isa NamedTuple ? Tuple(x) : x)
    catch error
        throw(ArgumentError("stratum levels must have a stable sort order: $error"))
    end
    groups = [findall(x -> isequal(x, level), identifiers) for level in levels]
    return levels, groups
end

function _standardize_by_time(
    predictions,
    design,
    observed_times,
    times,
    indices;
    response_gradient::Bool,
)
    all(x -> x isa Real && isfinite(x), predictions) || throw(ArgumentError(
        "MixedModels returned missing or non-finite population predictions",
    ))
    means = Vector{Float64}(undef, length(times))
    rows = Matrix{Float64}(undef, length(times), size(design, 2))
    for (j, t) in pairs(times)
        selected = [i for i in indices if isequal(observed_times[i], t)]
        isempty(selected) && throw(ArgumentError(
            "every requested stratum must contain at least one target-population row " *
            "at time $(repr(t))",
        ))
        means[j] = sum(predictions[i] for i in selected) / length(selected)
        for column in axes(design, 2)
            rows[j, column] = if response_gradient
                sum(predictions[i] * design[i, column] for i in selected) /
                    length(selected)
            else
                sum(design[i, column] for i in selected) / length(selected)
            end
        end
    end
    return means, rows
end

function _effect_uncertainty(model::SupportedMixedModel, contrast::Matrix{Float64})
    beta_vcov = Matrix{Float64}(vcov(model))
    p = size(contrast, 2)
    size(beta_vcov) == (p, p) || throw(ArgumentError(
        "fixed-effect vcov has size $(size(beta_vcov)); expected ($p, $p)",
    ))
    all(isfinite, beta_vcov) || throw(ArgumentError(
        "fixed-effect vcov contains non-finite values (the fitted model may be rank deficient)",
    ))

    covariance = contrast * beta_vcov * transpose(contrast)
    all(isfinite, covariance) || throw(ArgumentError(
        "effect covariance contains non-finite values",
    ))
    scale = max(1.0, maximum(abs, covariance))
    tolerance = 8192eps(Float64) * scale
    asymmetry = maximum(abs, covariance .- transpose(covariance))
    asymmetry <= tolerance || throw(ArgumentError(
        "effect covariance is not symmetric within numerical tolerance; " *
        "maximum asymmetry is $asymmetry",
    ))
    covariance = Matrix{Float64}((covariance .+ transpose(covariance)) ./ 2)

    diagonal = [covariance[i, i] for i in axes(covariance, 1)]
    all(isfinite, diagonal) || throw(ArgumentError(
        "effect covariance has a non-finite diagonal value",
    ))
    minimum(diagonal) >= -tolerance || throw(ArgumentError(
        "effect covariance has a negative diagonal value beyond numerical tolerance: " *
        "$(minimum(diagonal))",
    ))
    for i in eachindex(diagonal)
        if diagonal[i] < 0
            diagonal[i] = 0.0
            covariance[i, i] = 0.0
        end
    end
    return covariance, sqrt.(diagonal)
end

function _mixed_g_computation(
    model::SupportedMixedModel,
    data::DataFrame;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values = (0, 1),
    adjustment = Symbol[],
    strata = nothing,
    random_effects = :zero,
    compute_uncertainty::Bool = true,
)
    nrow(data) > 0 || throw(ArgumentError("data must contain at least one row"))
    intervention_values = _validate_values(values)
    random_effects_mode = _validate_random_effects(random_effects)
    model isa GeneralizedLinearMixedModel && _validate_glmm_family_link(model)
    strata_columns = _normalize_strata(strata)
    reserved = Set((treatment, outcome, time, id))
    invalid_strata = [column for column in strata_columns if column in reserved]
    isempty(invalid_strata) || throw(ArgumentError(
        "stratification columns must differ from treatment, outcome, time, and id; " *
        "invalid columns are $invalid_strata",
    ))
    _validate_columns(data, (treatment, outcome, time, id))
    _validate_columns(data, strata_columns)
    _validate_complete_finite(data, (treatment, outcome, time, id))
    _validate_complete_finite(data, strata_columns)
    _validate_static_treatment(data, treatment, id)
    _validate_model(
        model, data, treatment, outcome, time, id, adjustment, strata_columns,
    )
    if model isa GeneralizedLinearMixedModel && random_effects_mode == :marginal
        _random_intercept_variance(model)
    end

    population_level = _fresh_group_level(data[!, id])
    reference_data = _intervention_data(
        data, treatment, id, intervention_values[1], population_level,
    )
    comparison_data = _intervention_data(
        data, treatment, id, intervention_values[2], population_level,
    )
    # Predict both regimes together. A separate all-A=a table can make a fitted
    # treatment/intercept or treatment×time design rank deficient at prediction time.
    prediction_data = vcat(reference_data, comparison_data)
    design = _fixed_effect_design(model, prediction_data)
    predictions, response_gradient = _prediction_components(
        model, prediction_data, design, random_effects_mode,
    )
    n = nrow(data)
    reference_predictions = view(predictions, 1:n)
    comparison_predictions = view(predictions, (n + 1):(2n))
    reference_design = view(design, 1:n, :)
    comparison_design = view(design, (n + 1):(2n), :)

    times = _sorted_unique(data[!, time], time)
    levels, groups = _stratum_groups(data, strata_columns)
    results = map(groups) do indices
        reference, reference_rows = _standardize_by_time(
            reference_predictions,
            reference_design,
            data[!, time],
            times,
            indices;
            response_gradient,
        )
        comparison, comparison_rows = _standardize_by_time(
            comparison_predictions,
            comparison_design,
            data[!, time],
            times,
            indices;
            response_gradient,
        )
        effect_vcov, effect_se = compute_uncertainty ?
            _effect_uncertainty(model, comparison_rows .- reference_rows) :
            (nothing, nothing)
        MixedGComputationResult(;
            treatment,
            outcome,
            time,
            id,
            times,
            values = intervention_values,
            mean_reference = reference,
            mean_comparison = comparison,
            adjustment,
            vcov = effect_vcov,
            se = effect_se,
            random_effects = random_effects_mode,
        )
    end

    isempty(strata_columns) && return only(results)
    return StratifiedMixedGComputationResult(strata_columns, levels, results)
end

function CausalDynamics.mixed_g_computation(
    model::SupportedMixedModel,
    data::DataFrame;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values = (0, 1),
    strata = nothing,
    random_effects = :zero,
)
    return _mixed_g_computation(
        model,
        data;
        treatment,
        outcome,
        time,
        id,
        values,
        strata,
        random_effects,
    )
end

function _identified_adjustment(g, treatment, outcome, node_names)
    result = identify(g, TotalEffectQuery(treatment, outcome); node_names)
    result.identifiable || throw(ArgumentError(
        "the effect of :$treatment on :$outcome is not backdoor-identifiable in the graph",
    ))
    all(x -> x isa Symbol, result.adjustment) || throw(ArgumentError(
        "graph adjustment variables must resolve to data-column symbols; provide node_names",
    ))
    return Symbol.(result.adjustment)
end

function CausalDynamics.mixed_g_computation(
    g::AbstractGraph,
    model::SupportedMixedModel,
    data::DataFrame;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values = (0, 1),
    strata = nothing,
    random_effects = :zero,
    node_names = nothing,
)
    node_names === nothing && throw(ArgumentError(
        "node_names is required when graph nodes are addressed by data-column symbols",
    ))
    adjustment = _identified_adjustment(g, treatment, outcome, node_names)
    return _mixed_g_computation(
        model,
        data;
        treatment,
        outcome,
        time,
        id,
        values,
        adjustment,
        strata,
        random_effects,
    )
end

function CausalDynamics.mixed_g_computation(
    g::CausalGraph,
    model::SupportedMixedModel,
    data::DataFrame;
    treatment::Symbol,
    outcome::Symbol,
    time::Symbol,
    id::Symbol,
    values = (0, 1),
    strata = nothing,
    random_effects = :zero,
    node_names = nothing,
)
    names = node_names === nothing ? get_node_names(g) : node_names
    isempty(names) && throw(ArgumentError(
        "CausalGraph has no node names; set node :name properties or pass node_names",
    ))
    adjustment = _identified_adjustment(g, treatment, outcome, names)
    return _mixed_g_computation(
        model,
        data;
        treatment,
        outcome,
        time,
        id,
        values,
        adjustment,
        strata,
        random_effects,
    )
end

include("mixedmodels_nb2.jl")

end
