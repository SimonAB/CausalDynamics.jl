using CausalDynamics
using Test
using Graphs
using Random

@testset "Mechanism library (core, no Lux required)" begin
    @testset "MechanismSpec construction" begin
        @testset "defaults and kinds" begin
            m = MechanismSpec(:x, [:z])
            @test m.kind === :ode_residual
            @test m.representation === nothing
            @test m.model === nothing
            @test m.parameters === nothing
            @test m.states === nothing
            @test m.output_dim == 1
            for k in (:static, :ode_residual, :generative)
                @test MechanismSpec(:y, [:x]; kind = k).kind === k
            end
        end

        @testset "parent AbstractVector and empty parents" begin
            v = [:a, :b, :c]
            m = MechanismSpec(:y, view(v, 1:2); kind = :static)
            @test m.parents == [:a, :b]
            m0 = MechanismSpec(:z, Symbol[]; kind = :static)
            @test m0.parents == Symbol[]
        end

        @testset "representation link" begin
            enc = S -> S[:, 1:1]
            rs = RepresentationSpec(:S, [:z1], enc)
            m = MechanismSpec(:z1, [:a]; kind = :generative, representation = rs)
            @test m.representation === rs
            @test m.representation.source === :S
        end

        @testset "output_dim" begin
            @test MechanismSpec(:y, [:x]; output_dim = 4).output_dim == 4
            @test_throws ArgumentError MechanismSpec(:y, [:x]; output_dim = 0)
            @test_throws ArgumentError MechanismSpec(:y, [:x]; output_dim = -1)
        end

        @testset "validation errors" begin
            @test_throws ArgumentError MechanismSpec(:x, [:z]; kind = :bogus)
            @test_throws ArgumentError MechanismSpec(:x, [:z]; kind = :ODE_residual)
            @test_throws ArgumentError MechanismSpec(:x, [:z, :z])
            @test_throws ArgumentError MechanismSpec(:x, [:a, :b, :a])
        end
    end

    @testset "MechanismLibrary" begin
        @testset "empty library and defaults" begin
            lib = MechanismLibrary()
            @test isempty(lib.mechanisms)
            @test isempty(lib.allowed_parents)
            @test lib.graph_hash == zero(UInt64)
            cert = mechanism_certificate(lib)
            @test cert.nodes == Symbol[]
            @test cert.n_mechanisms == 0
            @test cert.lux_available isa Bool
        end

        @testset "string keys Symbol-ised in allowed_parents" begin
            lib = MechanismLibrary(;
                allowed_parents = Dict("x" => ["z"], "z" => String[]),
                graph_hash = UInt64(42),
            )
            @test lib.allowed_parents[:x] == [:z]
            @test lib.graph_hash == UInt64(42)
            register_mechanism!(lib, MechanismSpec(:x, [:z]; kind = :static))
            @test haskey(lib.mechanisms, :x)
        end

        @testset "register overwrites same node" begin
            lib = MechanismLibrary(;
                allowed_parents = Dict(:x => [:z], :z => Symbol[]),
            )
            register_mechanism!(lib, MechanismSpec(:x, [:z]; kind = :static))
            register_mechanism!(lib, MechanismSpec(:x, [:z]; kind = :generative, output_dim = 2))
            @test lib.mechanisms[:x].kind === :generative
            @test lib.mechanisms[:x].output_dim == 2
            @test length(lib.mechanisms) == 1
        end

        @testset "parent subset edges" begin
            lib = MechanismLibrary(;
                allowed_parents = Dict(
                    :z => Symbol[],
                    :x => [:z],
                    :y => [:x, :z],
                ),
            )
            # empty parents allowed when node has empty allowed set
            register_mechanism!(lib, MechanismSpec(:z, Symbol[]; kind = :static))
            # proper subset of y's parents
            register_mechanism!(lib, MechanismSpec(:y, [:x]; kind = :ode_residual))
            @test lib.mechanisms[:y].parents == [:x]
            @test_throws ArgumentError register_mechanism!(
                lib, MechanismSpec(:y, [:x, :w]),
            )
            @test_throws ArgumentError register_mechanism!(
                lib, MechanismSpec(:missing, [:z]),
            )
            # full parent set
            register_mechanism!(lib, MechanismSpec(:y, [:x, :z]; kind = :static))
            @test Set(lib.mechanisms[:y].parents) == Set([:x, :z])
        end

        @testset "multi-node certificate" begin
            lib = MechanismLibrary(;
                allowed_parents = Dict(
                    :a => [:b],
                    :b => Symbol[],
                    :c => [:a, :b],
                ),
                graph_hash = UInt64(0xdeadbeef),
            )
            register_mechanism!(lib, MechanismSpec(:a, [:b]; kind = :static))
            register_mechanism!(lib, MechanismSpec(:c, [:a]; kind = :generative, output_dim = 3))
            cert = mechanism_certificate(lib)
            @test cert.nodes == [:a, :c]  # sorted
            @test cert.kinds[:a] === :static
            @test cert.kinds[:c] === :generative
            @test cert.parents[:c] == [:a]
            @test cert.attached[:a] === false
            @test cert.attached[:c] === false
            @test cert.output_dims[:c] == 3
            @test cert.output_dims[:a] == 1
            @test cert.graph_hash == UInt64(0xdeadbeef)
            @test cert.n_mechanisms == 2
            # certificate parents are copies
            push!(cert.parents[:c], :b)
            @test lib.mechanisms[:c].parents == [:a]
        end
    end

    @testset "mechanism_library_from_cdm" begin
        spec = ContinuousCDMSpec(
            [:z, :x, :y];
            parents = Dict(:z => Symbol[], :x => [:z], :y => [:x, :z]),
        )
        gh = graph_fingerprint(DiGraph(3))
        lib = mechanism_library_from_cdm(spec; graph_hash = gh)
        @test lib.allowed_parents[:y] == [:x, :z]
        @test lib.graph_hash == gh
        register_mechanism!(lib, MechanismSpec(:x, [:z]; kind = :ode_residual))
        @test mechanism_certificate(lib).nodes == [:x]
    end

    @testset "façades throw without Lux extension" begin
        if !lux_mechanisms_available()
            lib = MechanismLibrary(; allowed_parents = Dict(:x => [:z], :z => Symbol[]))
            m = MechanismSpec(:x, [:z]; kind = :generative)
            register_mechanism!(lib, m)
            @test_throws ErrorException attach_lux_mechanism!(lib, :x; parents = [:z])
            cdm = ContinuousCDMSpec([:z, :x]; parents = Dict(:z => Symbol[], :x => [:z]))
            @test_throws ErrorException build_ode_rhs((du, u, p, t) -> nothing, cdm, lib)
            @test_throws ErrorException train_mechanisms!(lib; loss = _ -> 0.0)
            @test_throws ErrorException abduce_noise(m, 1.0, [0.0])
            @test_throws ErrorException generate_from_noise(m, 0.0, [0.0])
            @test_throws ErrorException mechanism_counterfactual(m, 1.0, [0.0], [1.0])
            g = DiGraph(2)
            add_edge!(g, 1, 2)
            @test_throws ErrorException graphscm_with_mechanisms(
                g, Dict{Int, Function}(), Set{Int}(), lib;
                node_names = Dict(1 => :z, 2 => :x),
            )
        end
    end

    @testset "pack_parent_vector" begin
        spec = ContinuousCDMSpec([:z, :x, :y])
        u = [1.0, 2.0, 3.0]
        @test pack_parent_vector(u, spec, [:z, :x]) == [1.0, 2.0]
        @test pack_parent_vector(u, spec, [:y]) == [3.0]
        @test pack_parent_vector(u, spec, Symbol[]) == Float64[]
        @test pack_parent_vector(u, spec, [:y, :z, :x]) == [3.0, 1.0, 2.0]
        # SubArray state
        @test pack_parent_vector(@view(u[1:3]), spec, [:x]) == [2.0]
        @test_throws KeyError pack_parent_vector(u, spec, [:missing])
    end

    @testset "stress: many nodes in library" begin
        n = 80
        allowed = Dict{Symbol, Vector{Symbol}}(
            Symbol("v$i") => (i == 1 ? Symbol[] : [Symbol("v$(i-1)")]) for i in 1:n
        )
        lib = MechanismLibrary(; allowed_parents = allowed, graph_hash = UInt64(n))
        for i in 2:n
            register_mechanism!(
                lib,
                MechanismSpec(Symbol("v$i"), [Symbol("v$(i-1)")]; kind = :ode_residual),
            )
        end
        cert = mechanism_certificate(lib)
        @test cert.n_mechanisms == n - 1
        @test length(cert.nodes) == n - 1
        @test issorted(cert.nodes)
        @test all(!, values(cert.attached))
    end
end
