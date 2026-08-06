module CausalDynamicsDataFramesExt

using CausalDynamics
using DataFrames

"""
    DataFrame(panel::CDMPanel)

Wide `DataFrame` in [`CDMPanel`](@ref) column order.
"""
function DataFrames.DataFrame(panel::CDMPanel; kwargs...)
    return DataFrame(NamedTuple(panel); kwargs...)
end

end
