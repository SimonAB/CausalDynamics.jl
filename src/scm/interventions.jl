"""
    DoIntervention

Represents a `do(·)` intervention.

# Fields
- `variable`: Variable to intervene on
- `value`: Value to set
"""
struct DoIntervention
    variable::Union{Int, Symbol}
    value::Any
end

"""
    apply_intervention(scm, intervention)

Apply a `do(·)` intervention to an SCM.

An intervention `do(X = x)` sets variable X to value x, removing its dependence
on its parents (modularity principle).

# Arguments
- `scm::AbstractSCM`: Structural Causal Model
- `intervention::DoIntervention`: Intervention to apply

# Returns
- `AbstractSCM`: Modified SCM with intervention applied

# Examples

```julia
using CausalDynamics

# Create intervention: do(X = 1.0)
intervention = DoIntervention(:x, 1.0)
scm_intervened = apply_intervention(scm, intervention)

# Or use convenience function
intervention2 = do_intervention(:x, 1.0)
scm_intervened2 = apply_intervention(scm, intervention2)
```

# Notes
- **Modularity**: Intervention only affects the intervened variable's equation
- Other equations remain unchanged
- Currently returns a new SCM (immutable operation)

# References
- Pearl, J. (2009). *Causality*, Chapter 1.3

# See Also
- `do_intervention`: Convenience function to create interventions
- `DoIntervention`: Type representing interventions
"""
function apply_intervention(scm::AbstractSCM, intervention::DoIntervention)
    # TODO: Implement intervention application
    error("Intervention application not yet implemented. For now, use graph-based methods (backdoor_adjustment_set, frontdoor_adjustment_set) for identification, or modify the SCM equations manually.")
end

"""
    do_intervention(variable, value)

Convenience function to create a `DoIntervention` object.

# Arguments
- `variable::Union{Int, Symbol}`: Variable to intervene on
- `value::Any`: Value to set the variable to

# Returns
- `DoIntervention`: Intervention object representing `do(variable = value)`

# Examples

```julia
using CausalDynamics

# Intervene on variable :x, setting it to 1.0
intervention = do_intervention(:x, 1.0)

# Intervene on node 2, setting it to 0
intervention2 = do_intervention(2, 0)

# Apply intervention
scm_intervened = apply_intervention(scm, intervention)
```

# See Also
- `DoIntervention`: Type representing interventions
- `apply_intervention`: Apply intervention to an SCM
"""
function do_intervention(variable, value)
    return DoIntervention(variable, value)
end

export DoIntervention, apply_intervention, do_intervention
