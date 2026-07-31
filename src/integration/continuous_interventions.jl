"""
    AbstractContinuousIntervention

Continuous-time interventions for [`solve_cdm`](@ref) (Peters-style continuous
CDM taxonomy: pin, IC, soft force, RHS replacement).
See also [`AbstractCausalIntervention`](@ref).
"""

# AbstractContinuousIntervention is defined in interventions/abstract.jl

"""
    DoPin

Hard pin: set the initial condition to `value` and hold the coordinate fixed
(`ẋᵏ := 0`). SciML applies this without mutating `u` inside the RHS; a
`DiscreteCallback` reasserts the value after accepted steps to control drift.
"""
struct DoPin <: AbstractContinuousIntervention
    variable::Symbol
    value::Float64
end

"""
    DoInitialCondition

Set only the initial value of `variable` to `value` (leave the RHS unchanged).

Corresponds to `do(x₀ᵏ := ξ)` in continuous-time CDMs [@peters2022causal].
"""
struct DoInitialCondition <: AbstractContinuousIntervention
    variable::Symbol
    value::Float64
end

"""
    DoForce

Add a soft restoring term `-κ (u - target)` to the RHS of `variable`.
"""
struct DoForce <: AbstractContinuousIntervention
    variable::Symbol
    target::Float64
    κ::Float64
end

"""
    DoRhs

Replace the RHS of `variable` with `du_fn(u, p, t) -> Real`.
"""
struct DoRhs{F} <: AbstractContinuousIntervention
    variable::Symbol
    du_fn::F
end

"""
    ContinuousInterventionSet

Ordered collection of continuous interventions applied left-to-right.
"""
struct ContinuousInterventionSet <: AbstractContinuousIntervention
    interventions::Vector{AbstractCausalIntervention}
end

"""
    do_pin(variable, value)

Hard pin for continuous CDMs (`DoPin`). Also accepted: static [`DoIntervention`](@ref)
as a pin for backwards compatibility.
"""
do_pin(variable::Symbol, value) = DoPin(variable, Float64(value))

"""
    do_ic(variable, value)

Initial-condition intervention `do(x₀ := value)`.
"""
do_ic(variable::Symbol, value) = DoInitialCondition(variable, Float64(value))

"""
    do_force(variable, target; κ = 1.0)

Soft force toward `target` with strength `κ`.
"""
do_force(variable::Symbol, target; κ::Real = 1.0) =
    DoForce(variable, Float64(target), Float64(κ))

"""
    do_rhs(variable, du_fn)

Replace the coordinate RHS of `variable` with `du_fn(u, p, t)`.
"""
do_rhs(variable::Symbol, du_fn) = DoRhs(variable, du_fn)

"""
    continuous_interventions(items...)

Bundle one or more causal interventions for [`solve_cdm`](@ref).
"""
function continuous_interventions(items::AbstractCausalIntervention...)
    return ContinuousInterventionSet(collect(AbstractCausalIntervention, items))
end

export DoPin,
    DoInitialCondition,
    DoForce,
    DoRhs,
    ContinuousInterventionSet,
    do_pin,
    do_ic,
    do_force,
    do_rhs,
    continuous_interventions
