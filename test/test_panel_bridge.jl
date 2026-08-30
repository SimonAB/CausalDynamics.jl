using CausalDynamics
using CausalDynamics: hurdle, NodeOutcomeSpec, binary, count_outcome, check_occasion_resolution, MissingnessSpec
using DataFrames
using Test

@testset "panel bridge (identification → wide columns)" begin
    spec = TemporalDAGSpec(
        [:grid_type, :fec, :weight],
        [
            (:grid_type, :fec, 0),
            (:weight, :fec, 0),
            (:fec, :fec, 1),
        ],
    )
    T = 4
    u = unroll_temporal_dag(spec, T)
    query = TemporalEffectQuery(:grid_type, :fec, 2, 2)
    result = identify(u, query)

    cols = temporal_adjustment_columns(
        result, u;
        unit_level = [:grid_type],
    )
    @test cols == Symbol[] || cols ⊆ [:weight2, :fec1] # depends on backdoor set

    qcols = query_panel_columns(query; unit_level = [:grid_type])
    @test qcols.treatment === :grid_type
    @test qcols.outcome === :fec2

    wide_cols = [
        :mouse_id, :grid_type,
        :fec1, :fec2, :fec3, :fec4,
        :weight1, :weight2, :weight3, :weight4,
    ]
    plan = plan_targeted_estimation(u, query, wide_cols; unit_level = [:grid_type])
    @test plan.engine === :discrete_lmtp
    @test plan.treatment === :grid_type
    @test plan.outcome === :fec2
    @test plan.query == query
    @test plan.identifiable == result.identifiable
    @test all(c -> c in wide_cols, plan.baseline)

    adj = adjustment_columns(u, query; unit_level = [:grid_type])
    @test adj == temporal_adjustment_columns(result, u; unit_level = [:grid_type])

    lag_query = TemporalEffectQuery(:fec, :fec, 1, 2)
    lag_plan = plan_targeted_estimation(
        u, lag_query, wide_cols;
        unit_level = [:grid_type],
        discrete_treatment = false,
    )
    @test lag_plan.engine === :sequential_lmtp
    @test lag_plan.outcome === :fec2
end

@testset "Apodemus-style discrete LMTP planner" begin
    spec = TemporalDAGSpec(
        [:grid_type, :fec],
        [(:grid_type, :fec, 0)],
    )
    u = unroll_temporal_dag(spec, 4)
    query = TemporalEffectQuery(:grid_type, :fec, 2, 2)
    wide_cols = [:mouse_id, :grid_type, :fec1, :fec2, :fec3, :fec4]
    plan = plan_targeted_estimation(u, query, wide_cols; unit_level = [:grid_type])
    @test plan.engine === :discrete_lmtp
    @test plan.treatment === :grid_type
    @test plan.outcome === :fec2
    @test isempty(plan.baseline)
    @test isempty(plan.missing_columns)
end

@testset "hurdle outcome planner (#22)" begin
    spec = TemporalDAGSpec(
        [:grid_type, :fec],
        [(:grid_type, :fec, 0)],
    )
    u = unroll_temporal_dag(spec, 4)
    query = TemporalEffectQuery(:grid_type, :fec, 2, 2)
    outcome_specs = Dict(
        :fec => NodeOutcomeSpec(hurdle, :fec_bin, :fec_intensity),
    )
    wide_cols = [
        :mouse_id, :grid_type,
        :fec_bin1, :fec_bin2, :fec_bin3, :fec_bin4,
        :fec_intensity1, :fec_intensity2, :fec_intensity3, :fec_intensity4,
        :weight1, :weight2,
    ]
    plan = plan_targeted_estimation(
        u, query, wide_cols;
        unit_level = [:grid_type],
        outcome_specs = outcome_specs,
    )
    @test plan.engine === :two_part_discrete_lmtp
    @test plan.treatment === :grid_type
    @test plan.outcome === :fec_bin2
    @test plan.presence_col === :fec_bin2
    @test plan.intensity_col === :fec_intensity2
    @test plan.query == query

    qcols = query_panel_columns(
        query;
        unit_level = [:grid_type],
        outcome_specs = outcome_specs,
    )
    @test qcols.outcome === :fec_bin2

    gaussian_plan = plan_targeted_estimation(
        u, query, wide_cols;
        unit_level = [:grid_type],
    )
    @test gaussian_plan.engine === :discrete_lmtp
    @test gaussian_plan.outcome === :fec2
    @test gaussian_plan.presence_col === nothing
    @test gaussian_plan.intensity_col === nothing
    @test gaussian_plan.family_outcome === nothing
end

@testset "count_outcome planner (#24)" begin
    spec = TemporalDAGSpec(
        [:grid_type, :fec],
        [(:grid_type, :fec, 0)],
    )
    u = unroll_temporal_dag(spec, 4)
    query = TemporalEffectQuery(:grid_type, :fec, 2, 2)
    wide_cols = [:mouse_id, :grid_type, :fec1, :fec2, :fec3, :fec4]
    outcome_specs = Dict(:fec => NodeOutcomeSpec(count_outcome))
    plan = plan_targeted_estimation(
        u, query, wide_cols;
        unit_level = [:grid_type],
        outcome_specs = outcome_specs,
    )
    @test plan.engine === :discrete_lmtp
    @test plan.outcome === :fec2
    @test plan.family_outcome === :negbin

    plan_pois = plan_targeted_estimation(
        u, query, wide_cols;
        unit_level = [:grid_type],
        outcome_specs = outcome_specs,
        count_family = :poisson,
    )
    @test plan_pois.family_outcome === :poisson
end

@testset "binary outcome planner (#44)" begin
    spec = TemporalDAGSpec(
        [:grid_type, :infected],
        [(:grid_type, :infected, 0)],
    )
    u = unroll_temporal_dag(spec, 4)
    query = TemporalEffectQuery(:grid_type, :infected, 2, 2)
    wide_cols = [:mouse_id, :grid_type, :infected1, :infected2]
    outcome_specs = Dict(:infected => NodeOutcomeSpec(binary))
    plan = plan_targeted_estimation(
        u, query, wide_cols;
        unit_level = [:grid_type],
        outcome_specs = outcome_specs,
    )
    @test plan.engine === :discrete_lmtp
    @test plan.outcome === :infected2
    @test plan.family_outcome === :binomial
end

@testset "identification_support" begin
    data = (
        a = [1.0, 2.0, missing, 4.0],
        b = [1.0, missing, 3.0, 4.0],
    )
    sup = identification_support(data, [:a, :b]; min_n = 3)
    @test sup.min_complete_n == 2
    @test sup.estimability == :underpowered
    empty_adj = identification_support(data, Symbol[]; min_n = 1)
    @test empty_adj.min_complete_n == 4
end

@testset "plan_targeted_estimation empirical support (#18)" begin
    spec = TemporalDAGSpec([:grid_type, :fec], [(:grid_type, :fec, 0)])
    u = unroll_temporal_dag(spec, 4)
    query = TemporalEffectQuery(:grid_type, :fec, 2, 2)
    df = DataFrame(
        grid_type = fill("R", 5),
        fec2 = rand(5),
    )
    plan = plan_targeted_estimation(
        u, query, propertynames(df);
        unit_level = [:grid_type],
        data = df,
        min_n = 10,
    )
    @test plan.estimability === :underpowered
    @test plan.min_complete_n == 5
end

@testset "occasion resolution (#17)" begin
    query = TemporalEffectQuery(:grid_type, :fec, 3, 3)
    issues = check_occasion_resolution(
        query, Dict(:fec => 1); warn = false,
    )
    @test length(issues) == 1
    @test issues[1].variable === :fec
end

@testset "session slice and plan (#25)" begin
    spec = TemporalDAGSpec([:grid_type, :fec], [(:grid_type, :fec, 0)])
    u = unroll_temporal_dag(spec, 4)
    query = TemporalEffectQuery(:grid_type, :fec, 2, 2)
    df_long = DataFrame(
        id = vcat(fill(1, 2), fill(2, 2)),
        session = [1, 2, 1, 2],
        grid_type = fill("R", 4),
        fec_2 = [1.0, 3.0, 2.0, 4.0],
        weight_2 = [0.1, 0.2, 0.3, 0.4],
    )
    slice = session_slice(df_long, 2; session_col = :session)
    @test nrow(slice) == 2

    wide_cols = [:id, :grid_type, :fec2, :weight2]
    plan = plan_session_estimation(
        u, query, 2, wide_cols;
        unit_level = [:grid_type],
    )
    @test plan.engine === :discrete_lmtp
    @test plan.outcome === :fec2
end

@testset "missingness planner (#26)" begin
    spec = TemporalDAGSpec([:grid_type, :fec], [(:grid_type, :fec, 0)])
    u = unroll_temporal_dag(spec, 4)
    query = TemporalEffectQuery(:grid_type, :fec, 2, 4)
    wide_cols = [:mouse_id, :grid_type, :fec1, :fec2, :fec3]
    miss = MissingnessSpec(:fec; regime = :mnar, time_indexed = true)
    plan = plan_targeted_estimation(
        u, query, wide_cols;
        unit_level = [:grid_type],
        missingness = miss,
    )
    @test plan.estimability === :structural_skip
    @test !isempty(plan.missingness_note)

    query_ok = TemporalEffectQuery(:grid_type, :fec, 2, 2)
    plan_ok = plan_targeted_estimation(
        u, query_ok, wide_cols;
        unit_level = [:grid_type],
        missingness = miss,
    )
    @test plan_ok.estimability !== :structural_skip
    @test plan_ok.outcome === :fec2
end
