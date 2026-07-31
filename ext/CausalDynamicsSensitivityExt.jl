"""
    CausalDynamicsSensitivityExt

Forward local sensitivity for continuous CDMs via SciMLSensitivity.
"""
module CausalDynamicsSensitivityExt

using CausalDynamics: CausalDynamics,
    ContinuousCDMSpec,
    ode_problem_cdm
using OrdinaryDiffEq: solve
using SciMLSensitivity: ForwardDiffSensitivity

export forward_sensitivity_cdm

"""
    forward_sensitivity_cdm(spec, rhs!, u0, tspan, p; intervention=nothing, kwargs...)

Solve the continuous CDM with forward-mode local sensitivity
(`sensealg = ForwardDiffSensitivity()`). Returns the SciML solution.
"""
function forward_sensitivity_cdm(
    spec::ContinuousCDMSpec,
    rhs!,
    u0,
    tspan,
    p;
    intervention = nothing,
    kwargs...,
)
    prob = ode_problem_cdm(spec, rhs!, u0, tspan, p; intervention = intervention)
    return solve(prob; sensealg = ForwardDiffSensitivity(), kwargs...)
end

end # module
