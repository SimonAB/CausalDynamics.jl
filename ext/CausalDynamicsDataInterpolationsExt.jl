"""
    CausalDynamicsDataInterpolationsExt

Cubic-spline differentiation for ODE parent discovery via
[DataInterpolations.jl](https://docs.sciml.ai/DataInterpolations/stable/).
"""
module CausalDynamicsDataInterpolationsExt

using CausalDynamics: CausalDynamics
using DataInterpolations: CubicSpline, derivative

export spline_derivative

"""
    spline_derivative(t, y) -> Vector{Float64}

Evaluate the first derivative of a `CubicSpline` through `(t, y)`.
"""
function spline_derivative(t::AbstractVector{<:Real}, y::AbstractVector{<:Real})
    length(t) == length(y) || throw(ArgumentError("t and y length mismatch"))
    length(t) < 2 && throw(ArgumentError("need at least 2 time points"))
    A = CubicSpline(Vector{Float64}(y), Vector{Float64}(t))
    return Float64[derivative(A, ti) for ti in t]
end

end # module
