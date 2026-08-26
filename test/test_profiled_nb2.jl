using DataFrames
using LinearAlgebra
using Logging
using MixedModels
using QuadGK
using StableRNGs
using Statistics

@testset "Estimated-shape NB2 random-intercept backend" begin
    extension_module = Base.get_extension(CausalDynamics, :CausalDynamicsMixedModelsExt)
    @test extension_module !== nothing

    @testset "likelihood primitives and quadrature" begin
        for y in (0, 1, 17, 1_000), eta in (-8.0, 0.2, 9.0), shape in (0.5, 1.5, 5.0)
            mean_value = exp(eta)
            distribution = MixedModels.Distributions.NegativeBinomial(
                shape, shape / (shape + mean_value),
            )
            @test extension_module._nb2_logpmf(y, eta, shape) ≈
                MixedModels.Distributions.logpdf(distribution, y) atol = 1.0e-9
        end
        @test extension_module._stable_logsumexp([1_000.0, 999.0]) ≈
            1_000 + log1p(exp(-1)) atol = 1.0e-13

        y = [0.0, 3.0, 12.0, 2.0]
        X = [ones(4) collect(0.0:3.0)]
        beta = [0.3, 0.12]
        sigma = 0.8
        shape = 1.5
        parameters = vcat(beta, log(sigma), log(shape))
        direct_integrand(b) = exp(
            sum(
                extension_module._nb2_logpmf(y[index], dot(X[index, :], beta) + b, shape)
                for index in eachindex(y)
            ) - 0.5(b / sigma)^2,
        ) / (sqrt(2pi) * sigma)
        direct_likelihood, direct_error = QuadGK.quadgk(
            direct_integrand, -Inf, Inf; rtol = 1.0e-11,
        )
        @test direct_error < 1.0e-9
        quadrature_loglikelihoods = Float64[]
        for points in (15, 25, 41)
            nodes, weights = extension_module.gausshermite(points)
            fitdata = extension_module._NB2FitData(
                y,
                X,
                [collect(eachindex(y))],
                nodes,
                log.(weights),
                extension_module.loggamma.(y .+ 1),
                :adaptive_gauss_hermite,
            )
            value, score = extension_module._nb2_likelihood(fitdata, parameters)
            push!(quadrature_loglikelihoods, value)
            @test value ≈ log(direct_likelihood) atol = 2.0e-9
            finite_difference = similar(score)
            for index in eachindex(parameters)
                step = 1.0e-6 * max(1.0, abs(parameters[index]))
                upper = copy(parameters)
                lower = copy(parameters)
                upper[index] += step
                lower[index] -= step
                upper_value = first(extension_module._nb2_likelihood(
                    fitdata, upper; gradient = false,
                ))
                lower_value = first(extension_module._nb2_likelihood(
                    fitdata, lower; gradient = false,
                ))
                finite_difference[index] = (upper_value - lower_value) / (2step)
            end
            @test score ≈ finite_difference rtol = 2.0e-6 atol = 2.0e-7
        end
        @test maximum(abs.(diff(quadrature_loglikelihoods))) < 2.0e-9
    end

    function simulate_nb2_panel(
        rng;
        n_subjects = 80,
        shape = 1.5,
        random_variance = 0.5,
    )
        rows = NamedTuple[]
        times = ["D0", "D1", "D2"]
        for subject in 1:n_subjects
            cohort = isodd(subject) ? "group_a" : "group_b"
            treatment = Float64((subject % 4) >= 2)
            marker = Float64((subject % 3) == 0)
            b = sqrt(random_variance) * randn(rng)
            for (time_index, time_value) in pairs(times)
                time_number = time_index - 1
                cohort_b = cohort == "group_b"
                eta = 0.7 + 0.2cohort_b + 0.35treatment + 0.16time_number +
                    0.28treatment * time_number + 0.15cohort_b * treatment +
                    0.11cohort_b * treatment * time_number + 0.12marker +
                    0.06marker * time_number + b
                mean_value = exp(eta)
                response = rand(
                    rng,
                    MixedModels.Distributions.NegativeBinomial(
                        shape, shape / (shape + mean_value),
                    ),
                )
                push!(rows, (;
                    Subject = subject,
                    Cohort = cohort,
                    Treatment = treatment,
                    Time = time_value,
                    Marker = marker,
                    Count = response,
                ))
            end
        end
        return DataFrame(rows)
    end

    rng = StableRNG(20260828)
    data = simulate_nb2_panel(rng)
    formula_term = @formula(
        Count ~ Cohort * Treatment * Time + Marker * Time + (1 | Subject)
    )
    model = fit_profiled_nb2(
        formula_term,
        data;
        id = :Subject,
        treatment = :Treatment,
        quadrature_points = 15,
        multiple_starts = 2,
        profile = true,
        progress = false,
    )

    @testset "fit API, optimization, and profile" begin
        @test model isa NB2RandomInterceptModel
        @test model isa ProfiledNB2MixedModel
        @test converged(model)
        @test theta(model) == model.theta
        @test random_intercept_variance(model) == model.random_intercept_variance
        @test coef(model) == fixef(model)
        @test vcov(model) == model.beta_vcov
        @test formula(model) == model.formula
        @test loglikelihood(model) == model.loglikelihood
        @test deviance(model) == -2loglikelihood(model)
        @test nobs(model) == nrow(data)
        @test isfinite(theta(model)) && theta(model) > 0
        @test isfinite(model.random_intercept_variance) &&
            model.random_intercept_variance > 0
        @test !issingular(model)
        @test size(vcov(model)) == (length(coef(model)), length(coef(model)))
        @test vcov(model) ≈ transpose(vcov(model)) atol = 1.0e-12
        @test all(isfinite, vcov(model))
        @test fitdiagnostics(model).backend == :dedicated_subject_integrated_likelihood
        @test fitdiagnostics(model).starts_agree
        @test fitdiagnostics(model).theta_interior
        @test fitdiagnostics(model).profile_identified
        @test fitdiagnostics(model).gradient_norm <= 1.0e-3
        @test nrow(model.theta_profile) == 5
        @test all(model.theta_profile.converged)
        @test all(model.theta_profile.objective[[1, 2, 4, 5]] .>
            model.theta_profile.objective[3])
        @test occursin("estimated theta", sprint(show, model))
        @test occursin("adaptive_gauss_hermite", sprint(show, model))

        stability = quadrature_diagnostics(model; points = (15, 25, 41))
        @test stability.quadrature_points == [15, 25, 41]
        @test all(stability.converged)
        @test maximum(abs.(stability.theta .- stability.theta[end])) < 2.0e-3
        @test maximum(abs.(stability.random_intercept_variance .-
            stability.random_intercept_variance[end])) < 2.0e-3
        @test maximum(stability.coefficient_maximum_difference) < 2.0e-3
    end

    @testset "g-computation and uncertainty" begin
        common = (;
            treatment = :Treatment,
            outcome = :Count,
            time = :Time,
            id = :Subject,
        )
        zero_result = @test_nowarn mixed_g_computation(
            model, data; common..., strata = :Cohort, random_effects = :zero,
        )
        marginal_result = @test_nowarn mixed_g_computation(
            model, data; common..., strata = :Cohort, random_effects = :marginal,
        )
        @test zero_result isa StratifiedMixedGComputationResult
        @test zero_result.levels == ["group_a", "group_b"]
        @test all(result -> result.uncertainty == :delta_fixed, zero_result)
        @test all(result -> result.random_effects == :zero, zero_result)

        reference_data = copy(data)
        comparison_data = copy(data)
        reference_data.Treatment .= 0.0
        comparison_data.Treatment .= 1.0
        combined = vcat(reference_data, comparison_data)
        design = Matrix{Float64}(MixedModels.StatsModels.modelcols(
            model.fixed_formula_term, combined,
        ))
        expected = exp.(design * coef(model))
        n = nrow(data)
        for cohort in zero_result.levels
            result = zero_result[cohort]
            expected_reference = Float64[]
            expected_comparison = Float64[]
            gradient = zeros(length(result.times), length(coef(model)))
            for (time_index, time_value) in pairs(result.times)
                indices = findall(
                    (data.Cohort .== cohort) .& (data.Time .== time_value),
                )
                mu0 = expected[indices]
                mu1 = expected[n .+ indices]
                x0 = view(design, indices, :)
                x1 = view(design, n .+ indices, :)
                push!(expected_reference, mean(mu0))
                push!(expected_comparison, mean(mu1))
                gradient[time_index, :] .= vec(mean(mu1 .* x1; dims = 1)) .-
                    vec(mean(mu0 .* x0; dims = 1))
            end
            expected_covariance = gradient * vcov(model) * transpose(gradient)
            @test result.mean_reference ≈ expected_reference atol = 2.0e-13
            @test result.mean_comparison ≈ expected_comparison atol = 2.0e-13
            @test result.effect == result.mean_comparison - result.mean_reference
            @test result.effect ≈ expected_comparison - expected_reference atol = 2.0e-13
            @test result.vcov ≈ expected_covariance rtol = 2.0e-12 atol = 2.0e-12
            @test result.se ≈ sqrt.(diag(expected_covariance)) rtol = 2.0e-12
            @test length(unique(round.(result.effect; digits = 6))) > 1
        end

        correction = exp(0.5model.random_intercept_variance)
        for cohort in zero_result.levels
            @test marginal_result[cohort].mean_reference ≈
                zero_result[cohort].mean_reference .* correction rtol = 2.0e-13
            @test marginal_result[cohort].mean_comparison ≈
                zero_result[cohort].mean_comparison .* correction rtol = 2.0e-13
            @test marginal_result[cohort].effect ≈
                zero_result[cohort].effect .* correction rtol = 2.0e-13
            @test marginal_result[cohort].vcov ≈
                zero_result[cohort].vcov .* correction^2 rtol = 2.0e-12
        end

        two_way = mixed_g_computation(
            model,
            data;
            common...,
            strata = (:Cohort, :Marker),
        )
        @test two_way.strata == [:Cohort, :Marker]
        @test length(two_way) == 4

        graph = DiGraph(3)
        add_edge!(graph, 1, 2)
        add_edge!(graph, 1, 3)
        add_edge!(graph, 2, 3)
        graph_result = mixed_g_computation(
            graph,
            model,
            data;
            common...,
            node_names = Dict(1 => :Cohort, 2 => :Treatment, 3 => :Count),
            strata = :Cohort,
        )
        @test all(result -> result.adjustment == [:Cohort], graph_result)

        bootstrap = mixed_g_computation(
            model,
            data;
            common...,
            strata = :Cohort,
            uncertainty = :parametric_bootstrap,
            n_boot = 3,
            seed = 81,
            min_success_rate = 2 / 3,
        )
        for result in bootstrap
            @test result.uncertainty == :parametric_bootstrap
            @test size(result.vcov) == (3, 3)
            @test result.vcov ≈ transpose(result.vcov) atol = 1.0e-12
            @test result.se ≈ sqrt.(diag(result.vcov)) atol = 1.0e-12
            @test result.uncertainty_diagnostics.n_boot == 3
            @test result.uncertainty_diagnostics.n_successful >= 2
            @test result.uncertainty_diagnostics.n_failed ==
                3 - result.uncertainty_diagnostics.n_successful
            @test result.uncertainty_diagnostics.seed == 81
        end
    end

    @testset "validation and fixed-shape likelihood gate" begin
        bad_counts = copy(data)
        bad_counts.Count[1] = -1
        @test_throws ArgumentError fit_profiled_nb2(
            formula_term, bad_counts; id = :Subject, progress = false,
        )
        noninteger = copy(data)
        noninteger.Count = Float64.(noninteger.Count)
        noninteger.Count[1] += 0.25
        @test_throws ArgumentError fit_profiled_nb2(
            formula_term, noninteger; id = :Subject, progress = false,
        )
        varying = copy(data)
        varying.Treatment[1] = 1 - varying.Treatment[1]
        @test_throws ArgumentError fit_profiled_nb2(
            formula_term,
            varying;
            id = :Subject,
            treatment = :Treatment,
            progress = false,
        )
        @test_throws ArgumentError fit_profiled_nb2(
            @formula(Count ~ Cohort + Treatment + (1 + Treatment | Subject)),
            data;
            id = :Subject,
            progress = false,
        )
        @test_throws ArgumentError fit_profiled_nb2(
            formula_term,
            data;
            id = :Subject,
            link = LogitLink(),
            progress = false,
        )
        @test_throws ArgumentError fit_profiled_nb2(
            formula_term,
            data;
            id = :Subject,
            family = :poisson,
            progress = false,
        )
        @test_throws ArgumentError fit_profiled_nb2(
            formula_term,
            data;
            id = :Subject,
            weights = ones(nrow(data)),
            progress = false,
        )
        rank_deficient = copy(data)
        rank_deficient.Duplicate = rank_deficient.Marker
        with_logger(NullLogger()) do
            @test_throws ArgumentError fit_profiled_nb2(
                @formula(Count ~ Marker + Duplicate + (1 | Subject)),
                rank_deficient;
                id = :Subject,
                progress = false,
            )
        end

        audit_data = simulate_nb2_panel(StableRNG(44); n_subjects = 24)
        audit = with_logger(NullLogger()) do
            validate_fixed_theta_nb2_likelihood(
                @formula(Count ~ Cohort + Treatment * Time + (1 | Subject)),
                audit_data;
                id = :Subject,
                theta_grid = (1.0, 1.5),
                quadrature_points = 15,
                tolerance = 1.0e-4,
            )
        end
        @test !audit.validated
        @test nrow(audit.comparisons) == 2
        @test all(.!audit.comparisons.agrees)
        @test all(audit.comparisons.absolute_difference .> audit.tolerance)
        @test all(isfinite, audit.comparisons.independent_gradient_norm)
    end

    @testset "broad parameter recovery" begin
        scenarios = ((0.5, 0.1), (1.5, 0.5), (5.0, 1.0))
        small_sample_error = 0.0
        larger_sample_error = 0.0
        for (shape, variance) in scenarios
            scenario_data = simulate_nb2_panel(
                StableRNG(round(Int, 100shape + 10variance));
                n_subjects = 100,
                shape,
                random_variance = variance,
            )
            scenario_model = fit_profiled_nb2(
                @formula(Count ~ Cohort + Treatment * Time + Marker + (1 | Subject)),
                scenario_data;
                id = :Subject,
                treatment = :Treatment,
                quadrature_points = 11,
                multiple_starts = 1,
                profile = false,
                progress = false,
            )
            @test converged(scenario_model)
            @test 0.2shape < theta(scenario_model) < 5shape
            @test scenario_model.random_intercept_variance > 1.0e-6
            @test !fitdiagnostics(scenario_model).random_effect_boundary
            small_data = filter(:Subject => <=(30), scenario_data)
            small_model = fit_profiled_nb2(
                @formula(Count ~ Cohort + Treatment * Time + Marker + (1 | Subject)),
                small_data;
                id = :Subject,
                treatment = :Treatment,
                quadrature_points = 11,
                multiple_starts = 1,
                profile = false,
                progress = false,
            )
            @test converged(small_model)
            small_sample_error += abs(log(theta(small_model) / shape)) +
                abs(log(small_model.random_intercept_variance / variance))
            larger_sample_error += abs(log(theta(scenario_model) / shape)) +
                abs(log(scenario_model.random_intercept_variance / variance))
        end
        @test larger_sample_error < small_sample_error
    end
end
