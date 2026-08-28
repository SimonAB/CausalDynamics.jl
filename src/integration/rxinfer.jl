"""
    RxInfer / GraphPPL integration (optional)

Load `RxInfer` (and `GraphPPL`) to activate the `CausalDynamicsRxInfer` package extension.
Core identification remains in `prepare_for_rxinfer`; inference runs in the extension.
"""

"""
    has_rxinfer() -> Bool

Return `true` when the `CausalDynamicsRxInfer` extension is loaded (`using RxInfer`).
"""
function has_rxinfer()
    return !isnothing(Base.get_extension(@__MODULE__, :CausalDynamicsRxInfer))
end

function _require_rxinfer!(f::Symbol)
    ext = Base.get_extension(@__MODULE__, :CausalDynamicsRxInfer)
    ext === nothing && error(
        "RxInfer.jl extension is not loaded. Run: using RxInfer\n" *
        "Then call CausalDynamics.$f(...). See docs/RXINFER_INTEGRATION.md.",
    )
    return ext
end

"""
    infer_backdoor_effect(g, data, X, Y; kwargs...) -> BackdoorInferenceResult

Backdoor-adjusted variational inference for treatment effect `τ` (GraphPPL + RxInfer).

Requires `using RxInfer` before calling. See extension docstring for arguments.
"""
function infer_backdoor_effect(args...; kwargs...)
    ext = _require_rxinfer!(:infer_backdoor_effect)
    return ext.infer_backdoor_effect(args...; kwargs...)
end

"""
    backdoor_graphppl_model(; n_conf=0)

GraphPPL `@model` generator for the Gaussian backdoor head. Requires `using RxInfer`.
"""
function backdoor_graphppl_model(; kwargs...)
    ext = _require_rxinfer!(:backdoor_graphppl_model)
    return ext.backdoor_graphppl_model(; kwargs...)
end

"""
    ppl_data_from_spec(spec; kwargs...) -> NamedTuple

Convert `prepare_for_rxinfer` output to RxInfer data (outcome, treatment, confounder matrix).
Requires `using RxInfer`.
"""
function ppl_data_from_spec(args...; kwargs...)
    ext = _require_rxinfer!(:ppl_data_from_spec)
    return ext.ppl_data_from_spec(args...; kwargs...)
end

"""
    posterior_mean_τ(τ_posterior) -> Float64

Posterior mean of `τ` from RxInfer marginals. Requires `using RxInfer`.
"""
function posterior_mean_τ(args...)
    ext = _require_rxinfer!(:posterior_mean_τ)
    return ext.posterior_mean_τ(args...)
end

function residualise_backdoor(args...; kwargs...)
    ext = _require_rxinfer!(:residualise_backdoor)
    return ext.residualise_backdoor(args...; kwargs...)
end

export has_rxinfer,
    infer_backdoor_effect,
    backdoor_graphppl_model,
    ppl_data_from_spec,
    posterior_mean_τ,
    residualise_backdoor
