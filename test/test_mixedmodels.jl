using CategoricalArrays
using DataFrames
using LinearAlgebra
using MixedModels
using StableRNGs
using Statistics

@testset "MixedModels integration" begin
    rng = StableRNG(20260825)
    n_units = 120
    observation_times = [0.0, 1.0, 2.0, 3.0]
    β_a = 1.1
    β_at = 0.65

    rows = NamedTuple[]
    for unit in 1:n_units
        W = randn(rng)
        A = Float64(W + 0.8randn(rng) > 0)
        random_intercept = 1.2randn(rng)
        for time in observation_times
            # Informatively unbalanced follow-up makes conditional BLUP averaging
            # detectably different from fixed-effect population prediction.
            time == 3.0 && random_intercept < 0 && continue
            Y = 2.0 + β_a * A + 0.4time + β_at * A * time +
                0.9W + random_intercept + 0.35randn(rng)
            push!(rows, (; id = unit, A, time, W, Y))
        end
    end
    data = DataFrame(rows)
    model = fit(
        MixedModel,
        @formula(Y ~ 1 + A * time + W + (1 | id)),
        data;
        progress = false,
    )

    @testset "known trajectory and population predictions" begin
        result = mixed_g_computation(
            model,
            data;
            treatment = :A,
            outcome = :Y,
            time = :time,
            id = :id,
        )

        @test result.times == observation_times
        @test result.values == (0, 1)
        known_effect = β_a .+ β_at .* observation_times
        @test maximum(abs.(result.effect .- known_effect)) < 0.4
        @test result.mean_comparison - result.mean_reference == result.effect
        coefficient_names = coefnames(model)
        G = zeros(length(observation_times), length(coefficient_names))
        treatment_index = only(findall(==("A"), coefficient_names))
        interaction_index = only(findall(==("A & time"), coefficient_names))
        G[:, treatment_index] .= 1.0
        G[:, interaction_index] .= observation_times
        expected_vcov = G * vcov(model) * transpose(G)
        @test result.vcov ≈ expected_vcov rtol = 1.0e-12 atol = 1.0e-12
        @test result.se ≈ sqrt.(diag(expected_vcov)) rtol = 1.0e-12 atol = 1.0e-12
        @test size(result.vcov) == (length(result.times), length(result.times))
        @test result.vcov ≈ transpose(result.vcov) rtol = 0 atol = 1.0e-14
        @test all(isfinite, result.vcov)
        @test all(diag(result.vcov) .>= -1.0e-14)
        @test minimum(eigvals(Symmetric(result.vcov))) >= -1.0e-12
        @test occursin("do(A=1) - do(A=0)", sprint(show, result))

        coefficients = coef(model)
        coefficient(name) = coefficients[only(findall(==(name), coefficient_names))]
        mean_w = [mean(data.W[data.time .== time]) for time in observation_times]
        expected_reference = coefficient("(Intercept)") .+
            coefficient("time") .* observation_times .+ coefficient("W") .* mean_w
        @test result.mean_reference ≈ expected_reference atol = 1.0e-10

        conditional_data = copy(data)
        conditional_data.A .= 0.0
        full_rank_data = vcat(conditional_data, data)
        conditional_predictions = view(
            MixedModels.predict(model, full_rank_data; new_re_levels = :population),
            1:nrow(data),
        )
        conditional_means = [
            mean(conditional_predictions[data.time .== time]) for time in observation_times
        ]
        @test maximum(abs.(conditional_means .- result.mean_reference)) > 1.0e-5

        extrapolated = mixed_g_computation(
            model,
            data;
            treatment = :A,
            outcome = :Y,
            time = :time,
            id = :id,
            values = (1.0, 2.0),
        )
        @test extrapolated.values == (1.0, 2.0)
        @test extrapolated.effect ≈ result.effect atol = 1.0e-10
        @test length(unique(round.(result.effect; digits = 5))) > 1
    end

    @testset "categorical time storage" begin
        categorical_data = copy(data)
        categorical_data.time_category = categorical(
            string.(categorical_data.time);
            levels = string.(observation_times),
            ordered = true,
        )
        categorical_model = fit(
            MixedModel,
            @formula(Y ~ 1 + A * time_category + W + (1 | id)),
            categorical_data;
            progress = false,
        )
        categorical_result = mixed_g_computation(
            categorical_model,
            categorical_data;
            treatment = :A,
            outcome = :Y,
            time = :time_category,
            id = :id,
        )
        @test categorical_result.times isa Vector
        @test string.(categorical_result.times) == string.(observation_times)
    end

    @testset "cohort-stratified trajectories" begin
        stratified_rng = StableRNG(20260826)
        stratified_rows = NamedTuple[]
        stratified_times = [0.0, 1.0, 2.0]
        for subject in 1:160
            cohort = isodd(subject) ? "group_a" : "group_b"
            treatment = Float64((subject % 4) >= 2)
            marker = Float64((subject % 3) == 0)
            random_intercept = 0.7randn(stratified_rng)
            for time_value in stratified_times
                cohort_b = cohort == "group_b"
                treatment_effect = 0.8 + 0.4time_value +
                    cohort_b * (1.2 + 0.5time_value)
                response = 1.5 + 0.6cohort_b + treatment_effect * treatment +
                    0.3time_value + 0.25marker + 0.15marker * time_value +
                    random_intercept + 0.25randn(stratified_rng)
                push!(
                    stratified_rows,
                    (;
                        Subject = subject,
                        Cohort = cohort,
                        Treatment = treatment,
                        Time = time_value,
                        Marker = marker,
                        Y = response,
                    ),
                )
            end
        end
        stratified_data = DataFrame(stratified_rows)
        stratified_model = fit(
            MixedModel,
            @formula(
                Y ~ 1 + Cohort * Treatment * Time + Marker * Time + (1 | Subject)
            ),
            stratified_data;
            progress = false,
        )
        common = (;
            treatment = :Treatment,
            outcome = :Y,
            time = :Time,
            id = :Subject,
        )

        stratified = @test_nowarn mixed_g_computation(
            stratified_model,
            stratified_data;
            common...,
            strata = :Cohort,
        )
        @test stratified isa StratifiedMixedGComputationResult
        @test stratified.strata == [:Cohort]
        @test stratified.levels == ["group_a", "group_b"]
        @test length(stratified) == 2
        @test stratified[(Cohort = "group_a",)] === stratified["group_a"]
        @test_throws KeyError stratified["unknown_group"]
        @test all(result -> result.times == stratified_times, stratified)
        @test all(
            result -> result.mean_comparison - result.mean_reference == result.effect,
            stratified,
        )

        reference_data = copy(stratified_data)
        comparison_data = copy(stratified_data)
        reference_data.Treatment .= 0.0
        comparison_data.Treatment .= 1.0
        combined_data = vcat(reference_data, comparison_data)
        fixed_term = only(filter(formula(stratified_model).rhs) do term
            names = try
                MixedModels.StatsModels.coefnames(term)
            catch
                String[]
            end
            names == coefnames(stratified_model)
        end)
        combined_design = Matrix(
            MixedModels.StatsModels.modelcols(fixed_term, combined_data),
        )
        fixed_predictions = combined_design * coef(stratified_model)
        n_stratified = nrow(stratified_data)
        for cohort in stratified.levels
            cohort_result = stratified[cohort]
            reference_expected = Float64[]
            comparison_expected = Float64[]
            for time_value in stratified_times
                indices = findall(
                    (stratified_data.Cohort .== cohort) .&
                    (stratified_data.Time .== time_value),
                )
                push!(reference_expected, mean(fixed_predictions[indices]))
                push!(
                    comparison_expected,
                    mean(fixed_predictions[n_stratified .+ indices]),
                )
            end
            @test cohort_result.mean_reference ≈ reference_expected atol = 1.0e-12
            @test cohort_result.mean_comparison ≈ comparison_expected atol = 1.0e-12
            @test cohort_result.effect ≈ comparison_expected - reference_expected atol = 1.0e-12
        end

        true_group_a = 0.8 .+ 0.4 .* stratified_times
        true_group_b = 2.0 .+ 0.9 .* stratified_times
        @test maximum(abs.(stratified["group_a"].effect .- true_group_a)) < 0.35
        @test maximum(abs.(stratified["group_b"].effect .- true_group_b)) < 0.35
        @test maximum(abs.(stratified["group_b"].effect .- stratified["group_a"].effect)) > 1.0

        unstratified = mixed_g_computation(
            stratified_model,
            stratified_data;
            common...,
            strata = nothing,
        )
        default_result = mixed_g_computation(
            stratified_model,
            stratified_data;
            common...,
        )
        @test unstratified isa MixedGComputationResult
        @test unstratified.effect == default_result.effect
        @test unstratified.vcov == default_result.vcov

        two_way = mixed_g_computation(
            stratified_model,
            stratified_data;
            common...,
            strata = (:Cohort, :Marker),
        )
        @test two_way.strata == [:Cohort, :Marker]
        @test two_way.levels == [
            (Cohort = "group_a", Marker = 0.0),
            (Cohort = "group_a", Marker = 1.0),
            (Cohort = "group_b", Marker = 0.0),
            (Cohort = "group_b", Marker = 1.0),
        ]
        @test two_way[(Cohort = "group_a", Marker = 1.0)].times == stratified_times

        graph = DiGraph(3)
        add_edge!(graph, 1, 2) # Cohort → Treatment
        add_edge!(graph, 1, 3) # Cohort → Y
        add_edge!(graph, 2, 3) # Treatment → Y
        graph_result = mixed_g_computation(
            graph,
            stratified_model,
            stratified_data;
            common...,
            strata = :Cohort,
            node_names = Dict(1 => :Cohort, 2 => :Treatment, 3 => :Y),
        )
        @test graph_result isa StratifiedMixedGComputationResult
        @test all(result -> result.adjustment == [:Cohort], graph_result)

        causal_graph = CausalGraph(graph)
        for (node, name) in Dict(1 => :Cohort, 2 => :Treatment, 3 => :Y)
            set_node_prop!(causal_graph, node, :name, name)
        end
        automatic_graph_result = mixed_g_computation(
            causal_graph,
            stratified_model,
            stratified_data;
            common...,
            strata = :Cohort,
        )
        @test automatic_graph_result.levels == stratified.levels
        @test all(result -> result.adjustment == [:Cohort], automatic_graph_result)

        @test_throws ArgumentError mixed_g_computation(
            stratified_model, select(stratified_data, Not(:Cohort)); common..., strata = :Cohort,
        )
        @test_throws ArgumentError mixed_g_computation(
            stratified_model, stratified_data; common..., strata = :Subject,
        )
        @test_throws ArgumentError mixed_g_computation(
            stratified_model, stratified_data; common..., strata = "Cohort",
        )
        @test_throws ArgumentError mixed_g_computation(
            stratified_model, stratified_data; common..., strata = (:Cohort, :Cohort),
        )
        with_unused = DataFrames.transform(
            stratified_data, :Cohort => ByRow(_ -> "all") => :Unused,
        )
        @test_throws ArgumentError mixed_g_computation(
            stratified_model, with_unused; common..., strata = :Unused,
        )
    end

    @testset "graph-derived adjustment" begin
        graph = DiGraph(3)
        add_edge!(graph, 1, 2) # W → A
        add_edge!(graph, 1, 3) # W → Y
        add_edge!(graph, 2, 3) # A → Y
        names = Dict(1 => :W, 2 => :A, 3 => :Y)

        result = mixed_g_computation(
            graph,
            model,
            data;
            treatment = :A,
            outcome = :Y,
            time = :time,
            id = :id,
            node_names = names,
        )
        @test result.adjustment == [:W]

        causal_graph = CausalGraph(graph)
        for (node, name) in names
            set_node_prop!(causal_graph, node, :name, name)
        end
        automatic = mixed_g_computation(
            causal_graph,
            model,
            data;
            treatment = :A,
            outcome = :Y,
            time = :time,
            id = :id,
        )
        @test automatic.adjustment == [:W]

        unadjusted_model = fit(
            MixedModel,
            @formula(Y ~ 1 + A * time + (1 | id)),
            data;
            progress = false,
        )
        @test_throws ArgumentError mixed_g_computation(
            graph,
            unadjusted_model,
            data;
            treatment = :A,
            outcome = :Y,
            time = :time,
            id = :id,
            node_names = names,
        )
    end

    @testset "negative-binomial log-link g-computation" begin
        nb_rng = StableRNG(20260827)
        nb_rows = NamedTuple[]
        nb_times = [0.0, 1.0, 2.0]
        nb_shape = 3.0
        for subject in 1:72
            cohort = isodd(subject) ? "group_a" : "group_b"
            treatment = Float64((subject % 4) >= 2)
            marker = Float64((subject % 3) == 0)
            random_intercept = 0.7randn(nb_rng)
            for time_value in nb_times
                cohort_b = cohort == "group_b"
                eta = 1.0 + 0.25cohort_b + 0.35treatment + 0.18time_value +
                    0.32treatment * time_value +
                    0.20cohort_b * treatment +
                    0.12cohort_b * treatment * time_value +
                    0.15marker + 0.08marker * time_value + random_intercept
                mu = exp(eta)
                response = rand(
                    nb_rng,
                    MixedModels.Distributions.NegativeBinomial(
                        nb_shape, nb_shape / (nb_shape + mu),
                    ),
                )
                push!(
                    nb_rows,
                    (;
                        Subject = subject,
                        Cohort = cohort,
                        Treatment = treatment,
                        Time = time_value,
                        Marker = marker,
                        Count = response,
                    ),
                )
            end
        end
        nb_data = DataFrame(nb_rows)
        nb_model = @test_logs (:warn, r"Results for families with a dispersion parameter") fit(
            MixedModel,
            @formula(
                Count ~ Cohort * Treatment * Time + Marker * Time + (1 | Subject)
            ),
            nb_data,
            MixedModels.Distributions.NegativeBinomial(nb_shape),
            LogLink();
            progress = false,
        )
        nb_common = (;
            treatment = :Treatment,
            outcome = :Count,
            time = :Time,
            id = :Subject,
        )

        zero_result = @test_nowarn mixed_g_computation(
            nb_model,
            nb_data;
            nb_common...,
            strata = :Cohort,
            random_effects = :zero,
        )
        @test zero_result isa StratifiedMixedGComputationResult
        @test zero_result.levels == ["group_a", "group_b"]
        @test all(r -> r.random_effects == :zero, zero_result)
        @test occursin("random_effects=:zero", sprint(show, zero_result["group_a"]))

        reference_data = copy(nb_data)
        comparison_data = copy(nb_data)
        reference_data.Treatment .= 0.0
        comparison_data.Treatment .= 1.0
        combined_data = vcat(reference_data, comparison_data)
        fixed_term = only(filter(formula(nb_model).rhs) do term
            names = try
                MixedModels.StatsModels.coefnames(term)
            catch
                String[]
            end
            names == coefnames(nb_model)
        end)
        design = Matrix{Float64}(
            MixedModels.StatsModels.modelcols(fixed_term, combined_data),
        )
        eta = design * coef(nb_model)
        expected = exp.(eta)
        n_nb = nrow(nb_data)
        population_data = copy(combined_data)
        population_data.Subject .= 0 # a fresh level, so b=0
        @test MixedModels.predict(
            nb_model,
            population_data;
            new_re_levels = :population,
            type = :linpred,
        ) ≈ eta rtol = 1.0e-13 atol = 1.0e-13
        @test MixedModels.predict(
            nb_model,
            population_data;
            new_re_levels = :population,
            type = :response,
        ) ≈ expected rtol = 1.0e-13 atol = 1.0e-13

        for cohort in zero_result.levels
            result = zero_result[cohort]
            expected_reference = Float64[]
            expected_comparison = Float64[]
            gradient = zeros(length(nb_times), size(design, 2))
            for (j, time_value) in pairs(nb_times)
                indices = findall(
                    (nb_data.Cohort .== cohort) .& (nb_data.Time .== time_value),
                )
                mu0 = expected[indices]
                mu1 = expected[n_nb .+ indices]
                x0 = view(design, indices, :)
                x1 = view(design, n_nb .+ indices, :)
                push!(expected_reference, mean(mu0))
                push!(expected_comparison, mean(mu1))
                gradient[j, :] .= vec(mean(mu1 .* x1; dims = 1)) .-
                    vec(mean(mu0 .* x0; dims = 1))
            end
            expected_vcov = gradient * vcov(nb_model) * transpose(gradient)
            @test result.times == nb_times
            @test result.mean_reference ≈ expected_reference rtol = 1.0e-13 atol = 1.0e-13
            @test result.mean_comparison ≈ expected_comparison rtol = 1.0e-13 atol = 1.0e-13
            @test result.effect ≈ expected_comparison - expected_reference atol = 1.0e-13
            @test result.mean_comparison - result.mean_reference == result.effect
            @test result.vcov ≈ expected_vcov rtol = 1.0e-12 atol = 1.0e-12
            @test result.se ≈ sqrt.(diag(expected_vcov)) rtol = 1.0e-12 atol = 1.0e-12
            @test size(result.vcov) == (length(nb_times), length(nb_times))
            @test result.vcov ≈ transpose(result.vcov) atol = 1.0e-12
            @test all(isfinite, result.vcov)
            @test all(diag(result.vcov) .>= 0)
            @test length(unique(round.(result.effect; digits = 6))) > 1
        end

        marginal_result = mixed_g_computation(
            nb_model,
            nb_data;
            nb_common...,
            strata = :Cohort,
            random_effects = :marginal,
        )
        random_sd = only(values(only(values(VarCorr(nb_model).σρ)).σ))
        correction = exp(0.5random_sd^2)
        @test all(r -> r.random_effects == :marginal, marginal_result)
        for cohort in zero_result.levels
            @test marginal_result[cohort].mean_reference ≈
                zero_result[cohort].mean_reference .* correction rtol = 1.0e-13
            @test marginal_result[cohort].mean_comparison ≈
                zero_result[cohort].mean_comparison .* correction rtol = 1.0e-13
            @test marginal_result[cohort].effect ≈
                zero_result[cohort].effect .* correction rtol = 1.0e-13
            @test marginal_result[cohort].vcov ≈
                zero_result[cohort].vcov .* correction^2 rtol = 1.0e-12 atol = 1.0e-12
        end
        @test maximum(abs.(
            marginal_result["group_a"].mean_reference .-
            zero_result["group_a"].mean_reference
        )) > 1.0e-6

        two_way = mixed_g_computation(
            nb_model,
            nb_data;
            nb_common...,
            strata = (:Cohort, :Marker),
            random_effects = :zero,
        )
        @test two_way.strata == [:Cohort, :Marker]
        @test length(two_way) == 4
        @test all(r -> size(r.vcov) == (3, 3), two_way)

        graph = DiGraph(3)
        add_edge!(graph, 1, 2)
        add_edge!(graph, 1, 3)
        add_edge!(graph, 2, 3)
        graph_result = mixed_g_computation(
            graph,
            nb_model,
            nb_data;
            nb_common...,
            strata = :Cohort,
            random_effects = :zero,
            node_names = Dict(1 => :Cohort, 2 => :Treatment, 3 => :Count),
        )
        @test all(r -> r.adjustment == [:Cohort], graph_result)

        poisson_model = GeneralizedLinearMixedModel(
            @formula(Count ~ Treatment * Time + (1 | Subject)),
            nb_data,
            Poisson(),
            LogLink(),
        )
        poisson_error = try
            mixed_g_computation(poisson_model, nb_data; nb_common...)
            nothing
        catch error
            error
        end
        @test poisson_error isa ArgumentError
        @test occursin("Poisson", sprint(showerror, poisson_error))
        @test occursin("LogLink", sprint(showerror, poisson_error))

        nonlog_model = @test_logs (:warn, r"Results for families with a dispersion parameter") GeneralizedLinearMixedModel(
            @formula(Count ~ Treatment * Time + (1 | Subject)),
            nb_data,
            MixedModels.Distributions.NegativeBinomial(nb_shape),
            MixedModels.GLM.NegativeBinomialLink(nb_shape),
        )
        nonlog_error = try
            mixed_g_computation(nonlog_model, nb_data; nb_common...)
            nothing
        catch error
            error
        end
        @test nonlog_error isa ArgumentError
        @test occursin("NegativeBinomial", sprint(showerror, nonlog_error))
        @test occursin("NegativeBinomialLink", sprint(showerror, nonlog_error))

        random_slope_model = @test_logs (:warn, r"Results for families with a dispersion parameter") GeneralizedLinearMixedModel(
            @formula(Count ~ Treatment * Time + (1 + Time | Subject)),
            nb_data,
            MixedModels.Distributions.NegativeBinomial(nb_shape),
            LogLink(),
        )
        slope_error = try
            mixed_g_computation(
                random_slope_model,
                nb_data;
                nb_common...,
                random_effects = :marginal,
            )
            nothing
        catch error
            error
        end
        @test slope_error isa ArgumentError
        @test occursin("single random intercept", sprint(showerror, slope_error))

        @test_throws ArgumentError mixed_g_computation(
            nb_model, nb_data; nb_common..., random_effects = :conditional,
        )
    end

    @testset "invalid inputs and unsupported models" begin
        common = (; treatment = :A, outcome = :Y, time = :time, id = :id)
        @test_throws ArgumentError mixed_g_computation(
            model, select(data, Not(:A)); common...,
        )
        @test_throws ArgumentError mixed_g_computation(
            model, select(data, Not(:Y)); common...,
        )
        @test_throws ArgumentError mixed_g_computation(
            model, select(data, Not(:time)); common...,
        )
        @test_throws ArgumentError mixed_g_computation(
            model, select(data, Not(:id)); common...,
        )
        @test_throws ArgumentError mixed_g_computation(
            model, data; common..., values = (0,),
        )
        @test_throws ArgumentError mixed_g_computation(
            model, data; common..., values = (1, 1),
        )

        varying = copy(data)
        varying[1, :A] = 1.0 - varying[1, :A]
        @test_throws ArgumentError mixed_g_computation(model, varying; common...)

        nonfinite = copy(data)
        nonfinite[1, :Y] = Inf
        @test_throws ArgumentError mixed_g_computation(model, nonfinite; common...)

        with_site = DataFrames.transform(
            data, :id => ByRow(x -> isodd(x) ? "a" : "b") => :site,
        )
        crossed_model = fit(
            MixedModel,
            @formula(Y ~ 1 + A * time + W + (1 | id) + (1 | site)),
            with_site;
            progress = false,
        )
        @test_throws ArgumentError mixed_g_computation(crossed_model, with_site; common...)

        binary = DataFrames.transform(data, :Y => ByRow(>(median(data.Y))) => :binary)
        glmm = fit(
            MixedModel,
            @formula(binary ~ 1 + A * time + W + (1 | id)),
            binary,
            Bernoulli();
            progress = false,
        )
        @test_throws ArgumentError mixed_g_computation(glmm, binary; common...)
        try
            mixed_g_computation(glmm, binary; common...)
        catch error
            message = sprint(showerror, error)
            @test occursin("Bernoulli", message)
            @test occursin("LogitLink", message)
        end
    end
end
