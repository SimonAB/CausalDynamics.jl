"""
    AbstractCausalIntervention

Root type for all `do(·)` interventions in CausalDynamics: static SCM assignments,
discrete-time CDM sequences/policies, and continuous-time CDM interventions.

Dispatch on the concrete subtype and the model (SCM / DiscreteTimeCDM /
`ContinuousCDMSpec`) determines how the intervention is applied.
"""
abstract type AbstractCausalIntervention end

"""
    AbstractIntervention

Discrete-time interventions for [`simulate`](@ref) / [`counterfactual`](@ref):
[`DoSequence`](@ref) and [`Policy`](@ref).
"""
abstract type AbstractIntervention <: AbstractCausalIntervention end

"""
    AbstractContinuousIntervention

Continuous-time interventions for [`solve_cdm`](@ref) / SciML: pins, initial
conditions, soft forces, and RHS replacements (continuous-CDM taxonomy).
"""
abstract type AbstractContinuousIntervention <: AbstractCausalIntervention end

export AbstractCausalIntervention, AbstractIntervention, AbstractContinuousIntervention
