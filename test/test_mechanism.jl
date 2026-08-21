using CausalDynamics
using Test
using Graphs
using Random

@testset "Mechanism library (core, no Lux required)" begin
    @testset "MechanismSpec validation" begin
        m = MechanismSpec(:x, [:z]; kind = :ode_residual)
        @test m.node === :x
        @test m.parents == [:z]
        @test m.model === nothing
        @test m.output_dim == 1
        g = MechanismSpec(:y, [:x]; kind = :generative, output_dim = 3)
        @test g.kind === :generative
        @test g.output_dim == 3
        @test_throws ArgumentError MechanismSpec(:x, [:z]; kind = :bogus)
        @test_throws ArgumentError MechanismSpec(:x, [:z, :z])
    end

    @testset "register_mechanism! parent checks" begin
        lib = MechanismLibrary(;
            allowed_parents = Dict(
                :z => Symbol[],
                :x => [:z],
                :y => [:x, :z],
            ),
            graph_hash = UInt64(0xabc),
        )
        register_mechanism!(lib, MechanismSpec(:x, [:z]))
        @test haskey(lib.mechanisms, :x)
        @test_throws ArgumentError register_mechanism!(
            lib, MechanismSpec(:y, [:x, :w]),  # :w not allowed
        )
        @test_throws ArgumentError register_mechanism!(
            lib, MechanismSpec(:missing, [:z]),
        )
    end

    @testset "mechanism_library_from_cdm" begin
        spec = ContinuousCDMSpec(
            [:z, :x, :y];
            parents = Dict(:z => Symbol[], :x => [:z], :y => [:x, :z]),
        )
        lib = mechanism_library_from_cdm(spec; graph_hash = graph_fingerprint(DiGraph(3)))
        @test lib.allowed_parents[:y] == [:x, :z]
        register_mechanism!(lib, MechanismSpec(:x, [:z]; kind = :ode_residual))
        cert = mechanism_certificate(lib)
        @test cert.nodes == [:x]
        @test cert.kinds[:x] === :ode_residual
        @test cert.attached[:x] === false
        @test cert.n_mechanisms == 1
        @test cert.lux_available isa Bool
    end

    @testset "façades throw without Lux extension" begin
        # Ensure extension is not loaded in this isolated check when Lux not imported
        if !lux_mechanisms_available()
            lib = MechanismLibrary(; allowed_parents = Dict(:x => [:z], :z => Symbol[]))
            @test_throws ErrorException attach_lux_mechanism!(
                lib, :x; parents = [:z],
            )
            spec = ContinuousCDMSpec([:z, :x]; parents = Dict(:z => Symbol[], :x => [:z]))
            @test_throws ErrorException build_ode_rhs((du, u, p, t) -> nothing, spec, lib)
            @test_throws ErrorException train_mechanisms!(lib; loss = _ -> 0.0)
        end
    end

    @testset "pack_parent_vector" begin
        spec = ContinuousCDMSpec([:z, :x, :y])
        u = [1.0, 2.0, 3.0]
        @test pack_parent_vector(u, spec, [:z, :x]) == [1.0, 2.0]
        @test pack_parent_vector(u, spec, [:y]) == [3.0]
    end
end
