using CausalDynamics
using DataFrames
using Graphs
using StableRNGs
using Test

@testset "Associations extension" begin
    @test !has_associations()

    @test_throws ErrorException infer_pc_graph(
        DataFrame(x = [1.0, 2.0]),
        [:x],
    )

# Load weakdep extension (Associations + DataFrames are both required).
    using Associations
    using DataFrames

    if !has_associations()
        @warn "CausalDynamicsAssociationsExt not loaded; skipping Associations tests"
    else
        @test has_associations()

        @testset "infer_pc_digraph" begin
            rng = StableRNG(1)
            n = 500
            x = randn(rng, n)
            y = x .+ 0.2 * randn(rng, n)
            g = infer_pc_digraph([x, y]; verbose = false)
            @test g isa SimpleDiGraph
            @test nv(g) == 2
            @test ne(g) >= 1
        end

        @testset "PC fork discovery (biological cohort parameters)" begin
            # Coefficients match scripts/biological_showcases.jl `confounded_cohort_dgp`
            rng = StableRNG(42)
            n = 2500
            nutrition = randn(rng, n)
            treatment = 0.8 * nutrition .+ 0.3 * randn(rng, n)
            worm_burden = 0.7 * treatment .+ 0.5 * nutrition .+ 0.3 * randn(rng, n)
            df = DataFrame(
                nutrition = nutrition,
                treatment = treatment,
                worm_burden = worm_burden,
            )
            g = infer_pc_graph(df, [:nutrition, :treatment, :worm_burden]; verbose = false)
            @test g isa CausalGraph
            @test nv(g.graph) == 3
            confounders, ok = prepare_from_discovery(g, :treatment, :worm_burden; complete = true)
            @test ok
            @test :nutrition in confounders

            conf2, ok2, meta = discover_and_prepare(
                df, :treatment, :worm_burden;
                method = :pc,
                names = [:nutrition, :treatment, :worm_burden],
                metadata = true,
                verbose = false,
                complete = true,
            )
            @test ok2
            @test :nutrition in conf2
            @test meta isa DiscoveryGraphMetadata
            @test meta.method == :pc
            @test meta.n == n
            @test meta.variables == [:nutrition, :treatment, :worm_burden]
        end

        @testset "PC fork discovery (legacy z,x,y labels)" begin
            rng = StableRNG(42)
            n = 2500
            z = randn(rng, n)
            x = 0.8 * z .+ 0.3 * randn(rng, n)
            y = 0.7 * x .+ 0.5 * z .+ 0.3 * randn(rng, n)
            df = DataFrame(z = z, x = x, y = y)
            g = infer_pc_graph(df, [:z, :x, :y]; verbose = false)
            @test g isa CausalGraph
            @test nv(g.graph) == 3
            @test has_edge(g.graph, 1, 2)
            @test has_edge(g.graph, 1, 3)
            @test has_edge(g.graph, 2, 3)

            confounders, ok = prepare_from_discovery(g, :x, :y; complete = true)
            @test ok
            @test :z in confounders

            conf2, ok2, meta = discover_and_prepare(
                df, :x, :y;
                method = :pc,
                names = [:z, :x, :y],
                metadata = true,
                verbose = false,
                complete = true,
            )
            @test ok2
            @test :z in conf2
            @test meta isa DiscoveryGraphMetadata
            @test meta.method == :pc
            @test meta.n == n
            @test meta.variables == [:z, :x, :y]
        end

        @testset "discover_and_prepare errors" begin
            df = DataFrame(x = randn(10), y = randn(10))
            @test_throws ArgumentError discover_and_prepare(
                df, :x, :y;
                method = :invalid,
                names = [:x, :y],
            )
            @test_throws ArgumentError discover_and_prepare(
                [randn(10), randn(10)], :x1, :x2;
                method = :oce,
                names = [:x1, :x2],
            )
        end

        @testset "OCE immune–parasite smoke (biological parameters)" begin
            # Structure matches scripts/biological_showcases.jl `immune_parasite_ts_dgp`
            rng = StableRNG(11)
            T = 800
            immune = zeros(T)
            parasite_load = zeros(T)
            immune[1] = randn(rng)
            parasite_load[1] = randn(rng)
            for t in 2:T
                immune[t] = 0.4 * immune[t - 1] + 0.45 * parasite_load[t - 1] + 0.1 * randn(rng)
                parasite_load[t] = 0.5 * immune[t - 1] + 0.35 * parasite_load[t - 1] + 0.1 * randn(rng)
            end
            ts = [immune, parasite_load]
            parents = infer_oce_parents(ts; verbose = false)
            @test length(parents) == 2
            spec = infer_oce_temporal_spec(ts, [:immune, :parasite_load]; verbose = false)
            @test spec isa TemporalDAGSpec
            u = unroll_temporal_dag(spec, 5)
            @test is_dag(u.graph)
        end

        @testset "OCE VAR smoke (legacy labels)" begin
            rng = StableRNG(7)
            T = 800
            x1 = zeros(T)
            x2 = zeros(T)
            x1[1] = randn(rng)
            x2[1] = randn(rng)
            for t in 2:T
                x1[t] = 0.6 * x1[t - 1] + 0.1 * randn(rng)
                x2[t] = 0.5 * x1[t - 1] + 0.4 * x2[t - 1] + 0.1 * randn(rng)
            end
            ts = [x1, x2]
            parents = infer_oce_parents(ts; verbose = false)
            @test length(parents) == 2
            spec = infer_oce_temporal_spec(ts, [:x1, :x2]; verbose = false)
            @test spec isa TemporalDAGSpec
            u = unroll_temporal_dag(spec, 5)
            @test is_dag(u.graph)
        end
    end
end
