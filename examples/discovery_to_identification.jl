#!/usr/bin/env julia
# Discovery (Associations.jl) → identification (CausalDynamics.jl)
#
# From CDCS monorepo root (recommended):
#   julia --project=. packages/CausalDynamics.jl/examples/discovery_to_identification.jl
# From CausalDynamics.jl package directory:
#   julia --project=. examples/discovery_to_identification.jl

using CausalDynamics

if !CausalDynamics.has_associations()
    @info "Loading Associations + DataFrames for CausalDynamicsAssociationsExt..."
    try
        using Associations
        using DataFrames
    catch
        using Pkg
        Pkg.add(["Associations", "DataFrames"])
        using Associations
        using DataFrames
    end
end

@assert CausalDynamics.has_associations()

using DataFrames
using StableRNGs

# Shared DGPs: scripts/biological_showcases.jl (same parameters as Ch. 05b / book tests)
const _BOOK_ROOT = let
    root = @__DIR__
    while !isfile(joinpath(root, "Project.toml")) || !isfile(joinpath(root, "scripts", "biological_showcases.jl"))
        parent = dirname(root)
        parent == root && break
        root = parent
    end
    root
end
include(joinpath(_BOOK_ROOT, "scripts", "biological_showcases.jl"))

function pc_cohort_example()
    df = confounded_cohort_dgp(; n = DEFAULT_COHORT_N, rng = StableRNG(DEFAULT_COHORT_SEED))
    ĝ = infer_pc_graph(df, [:nutrition, :treatment, :worm_burden]; verbose = false)
    confounders, ok = prepare_from_discovery(ĝ, :treatment, :worm_burden; complete = true)
    @info "PC cohort" confounders ok
    return confounders, ok
end

function oce_immune_parasite_example()
    ts = immune_parasite_ts_dgp(; T = DEFAULT_TS_LENGTH, rng = StableRNG(DEFAULT_TS_SEED))
    spec = infer_oce_temporal_spec(ts.series, ts.variables; verbose = false)
    u = unroll_temporal_dag(spec, 5)
    adj = temporal_backdoor_adjustment_nodes(u, :immune, 1, :parasite_load, 2)
    @info "OCE immune–parasite" edges=length(spec.edges) adj
    return spec, adj
end

pc_cohort_example()
oce_immune_parasite_example()
