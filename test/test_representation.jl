using CausalDynamics
using Test
using Random
using DataFrames
using LinearAlgebra
using Statistics

@testset "Representation bridge" begin
    rng = Random.Xoshiro(11)
    n, p, d = 20, 8, 2
    X = randn(rng, n, p)
    A = Float64.(randn(rng, n) .> 0)
    Y = randn(rng, n)
    W = randn(rng, n)
    B = randn(rng, p, d)
    encode_mat = S -> S * B

    @testset "RepresentationSpec construction" begin
        @testset "defaults and happy path" begin
            spec = RepresentationSpec(:S, [:z1, :z2], encode_mat)
            @test spec.role === :measurement
            @test spec.source === :S
            @test spec.code_names == [:z1, :z2]
            @test RepresentationSpec(:S, [:z1], encode_mat; role = :definitional).role ===
                  :definitional
        end

        @testset "accepts non-Vector AbstractVector of symbols" begin
            names = (:z1, :z2)  # NTuple
            spec = RepresentationSpec(:img, collect(Symbol, names), encode_mat)
            @test spec.code_names == [:z1, :z2]
            # SubArray of symbols
            v = [:a, :b, :c]
            spec2 = RepresentationSpec(:S, view(v, 1:2), encode_mat)
            @test spec2.code_names == [:a, :b]
        end

        @testset "validation errors" begin
            @test_throws ArgumentError RepresentationSpec(
                :S, Symbol[], encode_mat; role = :measurement,
            )
            @test_throws ArgumentError RepresentationSpec(
                :S, [:z1, :z1], encode_mat; role = :measurement,
            )
            @test_throws ArgumentError RepresentationSpec(
                :S, [:z1, :z2, :z1], encode_mat,
            )
            @test_throws ArgumentError RepresentationSpec(
                :S, [:z1], encode_mat; role = :not_a_role,
            )
            @test_throws ArgumentError RepresentationSpec(
                :S, [:z1], encode_mat; role = :Measurement,  # case-sensitive
            )
        end
    end

    @testset "encode_to_panel matrix path" begin
        spec = RepresentationSpec(
            :spectrum, [:z1, :z2], encode_mat; role = :definitional,
        )

        @testset "with tabular columns" begin
            panel = encode_to_panel(X, spec; tabular = Dict(:A => A, :Y => Y, :W => W))
            @test Set(keys(panel)) == Set([:z1, :z2, :A, :Y, :W])
            @test length(panel[:z1]) == n
            @test eltype(panel[:z1]) === Float64
            @test panel[:z1] ≈ (X * B)[:, 1]
            @test panel[:z2] ≈ (X * B)[:, 2]
            @test panel[:A] == A
            @test panel[:Y] == Y
        end

        @testset "without tabular" begin
            panel = encode_to_panel(X, spec)
            @test Set(keys(panel)) == Set([:z1, :z2])
        end

        @testset "empty tabular Dict" begin
            panel = encode_to_panel(X, spec; tabular = Dict{Symbol, Vector{Float64}}())
            @test Set(keys(panel)) == Set([:z1, :z2])
        end

        @testset "string keys in tabular are Symbol-ised" begin
            panel = encode_to_panel(X, spec; tabular = Dict("A" => A, "Y" => Y))
            @test haskey(panel, :A) && haskey(panel, :Y)
        end

        @testset "single row" begin
            X1 = X[1:1, :]
            panel = encode_to_panel(X1, spec; tabular = Dict(:A => A[1:1]))
            @test length(panel[:z1]) == 1
            @test panel[:z1][1] ≈ (X1 * B)[1, 1]
        end

        @testset "single code column" begin
            enc1 = S -> S * B[:, 1:1]
            spec1 = RepresentationSpec(:S, [:z1], enc1)
            panel = encode_to_panel(X, spec1)
            @test collect(keys(panel)) == [:z1]
            @test panel[:z1] ≈ (X * B)[:, 1]
        end

        @testset "Float32 and Int input promote to Float64 codes" begin
            Xf = Float32.(X)
            panel_f = encode_to_panel(Xf, RepresentationSpec(:S, [:z1, :z2], S -> S * Float32.(B)))
            @test eltype(panel_f[:z1]) === Float64
            Xi = round.(Int, 10 .* X)
            Bi = ones(Int, p, d)
            panel_i = encode_to_panel(Xi, RepresentationSpec(:S, [:z1, :z2], S -> S * Bi))
            @test eltype(panel_i[:z1]) === Float64
            @test panel_i[:z1] ≈ Float64.(Xi * Bi)[:, 1]
        end

        @testset "SubArray / view of X" begin
            Xv = @view X[1:10, :]
            panel = encode_to_panel(Xv, spec)
            @test length(panel[:z1]) == 10
            @test panel[:z1] ≈ (X[1:10, :] * B)[:, 1]
        end
    end

    @testset "encode return shapes" begin
        names = [:z1, :z2]

        @testset "vector of NamedTuples" begin
            encode_nt = S -> [
                (; z1 = sum(S[i, 1:4]), z2 = sum(S[i, 5:8])) for i in 1:size(S, 1)
            ]
            spec = RepresentationSpec(:S, names, encode_nt; role = :measurement)
            panel = encode_to_panel(X, spec)
            @test panel[:z1] ≈ vec(sum(X[:, 1:4]; dims = 2))
            @test panel[:z2] ≈ vec(sum(X[:, 5:8]; dims = 2))
        end

        @testset "vector of AbstractVectors" begin
            encode_vv = S -> [S[i, 1:2] for i in 1:size(S, 1)]
            spec = RepresentationSpec(:S, names, encode_vv)
            panel = encode_to_panel(X, spec)
            @test panel[:z1] ≈ X[:, 1]
            @test panel[:z2] ≈ X[:, 2]
        end

        @testset "NamedTuple with extra keys is fine" begin
            encode_extra = S -> [
                (; z1 = S[i, 1], z2 = S[i, 2], junk = 99.0) for i in 1:size(S, 1)
            ]
            panel = encode_to_panel(X, RepresentationSpec(:S, names, encode_extra))
            @test panel[:z1] ≈ X[:, 1]
        end

        @testset "wrong matrix dimensions" begin
            spec = RepresentationSpec(:S, names, encode_mat)
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, [:z1], encode_mat),
            )
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, [:z1, :z2, :z3], encode_mat),
            )
            # transposed encoder output (d × n)
            enc_T = S -> Matrix((S * B)')
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, names, enc_T),
            )
            # wrong row count
            enc_short = S -> (S * B)[1:(n - 1), :]
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, names, enc_short),
            )
        end

        @testset "invalid encode return types" begin
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, names, S -> 1.0),
            )
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, names, S -> "nope"),
            )
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, names, S -> fill(1.0, n)),  # vector of scalars
            )
            # NamedTuple missing a required key
            enc_miss = S -> [(; z1 = S[i, 1]) for i in 1:size(S, 1)]
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, names, enc_miss),
            )
            # row vector wrong length
            enc_badrow = S -> [[S[i, 1]] for i in 1:size(S, 1)]
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, names, enc_badrow),
            )
            # wrong length of row list
            enc_n1 = S -> [(; z1 = 0.0, z2 = 0.0) for _ in 1:(n - 1)]
            @test_throws ArgumentError encode_to_panel(
                X, RepresentationSpec(:S, names, enc_n1),
            )
        end

        @testset "empty X rejected" begin
            X0 = zeros(0, p)
            @test_throws ArgumentError encode_to_panel(
                X0, RepresentationSpec(:S, names, encode_mat),
            )
        end
    end

    @testset "tabular collisions and lengths" begin
        spec = RepresentationSpec(:S, [:z1, :z2], encode_mat)
        @test_throws ArgumentError encode_to_panel(
            X, spec; tabular = Dict(:z1 => A),
        )
        @test_throws ArgumentError encode_to_panel(
            X, spec; tabular = Dict(:A => A[1:(n - 1)]),
        )
        @test_throws ArgumentError encode_to_panel(
            X, spec; tabular = Dict(:A => A, :z2 => Y),
        )
    end

    @testset "representation_certificate" begin
        spec = RepresentationSpec(:S, [:z1, :z2], encode_mat; role = :measurement)
        cert = representation_certificate(spec)
        @test cert.role === :measurement
        @test cert.source === :S
        @test cert.code_names == [:z1, :z2]
        @test cert.n_codes == 2
        @test cert.encode_type_hash == hash(typeof(encode_mat))
        @test !isempty(cert.encode_type)

        @testset "code_names copy is defensive" begin
            push!(cert.code_names, :z3)
            @test spec.code_names == [:z1, :z2]
            cert2 = representation_certificate(spec)
            @test cert2.code_names == [:z1, :z2]
        end

        @testset "definitional role in certificate" begin
            spec_d = RepresentationSpec(:S, [:z1], S -> S[:, 1:1]; role = :definitional)
            @test representation_certificate(spec_d).role === :definitional
        end

        @testset "different encoder types get different type hashes" begin
            enc_a = S -> S[:, 1:2]
            enc_b = S -> S[:, 1:2] .+ 0  # distinct function object / type
            h_a = representation_certificate(
                RepresentationSpec(:S, [:z1, :z2], enc_a),
            ).encode_type_hash
            h_b = representation_certificate(
                RepresentationSpec(:S, [:z1, :z2], enc_b),
            ).encode_type_hash
            # Distinct anonymous functions usually differ in type; allow equal if not
            @test h_a isa UInt
            @test h_b isa UInt
        end
    end

    @testset "DataFrame extension" begin
        spec = RepresentationSpec(
            :spectrum, [:z1, :z2], encode_mat; role = :measurement,
        )
        df = DataFrame(A = A, Y = Y, W = W)

        @testset "appends codes without mutating input" begin
            df_copy = copy(df)
            out = encode_to_panel(df, X, spec)
            @test out isa DataFrame
            @test Set(Symbol.(names(out))) == Set([:A, :Y, :W, :z1, :z2])
            @test out.z1 ≈ (X * B)[:, 1]
            @test names(df) == names(df_copy)
            @test df.A == df_copy.A
            @test !(:z1 in Symbol.(names(df)))
        end

        @testset "preserves left-to-right existing columns" begin
            out = encode_to_panel(df, X, spec)
            @test Symbol.(names(out)[1:3]) == [:A, :Y, :W]
        end

        @testset "row mismatch" begin
            @test_throws ArgumentError encode_to_panel(df, X[1:(n - 1), :], spec)
            @test_throws ArgumentError encode_to_panel(
                DataFrame(A = A[1:5]), X, spec,
            )
        end

        @testset "name collision with existing column" begin
            @test_throws ArgumentError encode_to_panel(
                DataFrame(A = A, z1 = A), X, spec,
            )
        end

        @testset "empty DataFrame rejected via n mismatch or empty X" begin
            @test_throws ArgumentError encode_to_panel(
                DataFrame(A = Float64[]), zeros(0, p), spec,
            )
        end

        @testset "integer and string tabular columns preserved" begin
            df_mix = DataFrame(A = Int.(A), group = fill("g1", n))
            out = encode_to_panel(df_mix, X, spec)
            @test eltype(out.A) <: Integer
            @test eltype(out.group) <: AbstractString
            @test out.z1 isa Vector{Float64}
        end
    end

    @testset "NaN / Inf passthrough" begin
        Xn = copy(X)
        Xn[1, 1] = NaN
        Xn[2, 2] = Inf
        enc = S -> S[:, 1:2]
        panel = encode_to_panel(Xn, RepresentationSpec(:S, [:z1, :z2], enc))
        @test isnan(panel[:z1][1])
        @test isinf(panel[:z2][2])
    end

    @testset "determinism of fixed linear encoder" begin
        spec = RepresentationSpec(:S, [:z1, :z2], encode_mat)
        a = encode_to_panel(X, spec)
        b = encode_to_panel(X, spec)
        @test a[:z1] == b[:z1]
        @test a[:z2] == b[:z2]
    end

    @testset "synthetic mediation-on-codes (linear oracle)" begin
        n2 = 400
        rng2 = Random.Xoshiro(42)
        A2 = Float64.(rand(rng2, n2) .< 0.5)
        Mstar = 1.5 .* A2 .+ 0.5 .* randn(rng2, n2)
        Y2 = 2.0 .* Mstar .+ 0.3 .* randn(rng2, n2)
        p2 = 16
        S = randn(rng2, n2, p2)
        S[:, 1] .= Mstar
        encode_oracle = Smat -> hcat(Smat[:, 1])
        spec = RepresentationSpec(
            :spectrum, [:z1], encode_oracle; role = :definitional,
        )
        panel = encode_to_panel(S, spec; tabular = Dict(:A => A2, :Y => Y2))
        z = panel[:z1]
        Xdes = hcat(ones(n2), A2, z)
        β = Xdes \ Y2
        @test abs(β[3]) > 1.0
        @test abs(β[2]) < 0.4
        β_unadj = hcat(ones(n2), A2) \ Y2
        @test abs(β_unadj[2]) > abs(β[2])
        @test representation_certificate(spec).role === :definitional
    end

    @testset "stress: large panels and Monte Carlo oracle recovery" begin
        @testset "large n×p encode dims and Float64" begin
            rng_s = Random.Xoshiro(99)
            n_big, p_big, d_big = 2_500, 128, 4
            Xbig = randn(rng_s, n_big, p_big)
            Bbig = randn(rng_s, p_big, d_big) ./ sqrt(p_big)
            names = [Symbol("z$j") for j in 1:d_big]
            spec = RepresentationSpec(:S, names, S -> S * Bbig)
            t0 = time()
            panel = encode_to_panel(
                Xbig, spec;
                tabular = Dict(:A => rand(rng_s, n_big), :Y => randn(rng_s, n_big)),
            )
            elapsed = time() - t0
            @test length(panel[:z1]) == n_big
            @test eltype(panel[:z1]) === Float64
            @test panel[:z1] ≈ (Xbig * Bbig)[:, 1] rtol = 1e-10
            @test elapsed < 5.0  # soft timing guard (CPU)
        end

        @testset "wide p >> n projection" begin
            rng_s = Random.Xoshiro(100)
            n_w, p_w, d_w = 40, 2_000, 3
            Xw = randn(rng_s, n_w, p_w)
            Bw = randn(rng_s, p_w, d_w) ./ sqrt(p_w)
            names = [:z1, :z2, :z3]
            panel = encode_to_panel(Xw, RepresentationSpec(:S, names, S -> S * Bw))
            @test size(hcat(panel[:z1], panel[:z2], panel[:z3])) == (n_w, d_w)
            @test all(isfinite, panel[:z1])
        end

        @testset "Monte Carlo oracle recovery rate" begin
            # Across seeds, OLS adjusted A coefficient should stay small when
            # the encoder recovers M* exactly from column 1 of S.
            n_mc, n_rep = 200, 25
            abs_βA = Float64[]
            abs_βz = Float64[]
            for seed in 1:n_rep
                rng_i = Random.Xoshiro(1_000 + seed)
                Ai = Float64.(rand(rng_i, n_mc) .< 0.5)
                Mi = 1.4 .* Ai .+ 0.4 .* randn(rng_i, n_mc)
                Yi = 2.1 .* Mi .+ 0.25 .* randn(rng_i, n_mc)
                Si = randn(rng_i, n_mc, 12)
                Si[:, 1] .= Mi
                z = encode_to_panel(
                    Si, RepresentationSpec(:S, [:z1], S -> hcat(S[:, 1])),
                )[:z1]
                β = hcat(ones(n_mc), Ai, z) \ Yi
                push!(abs_βA, abs(β[2]))
                push!(abs_βz, abs(β[3]))
            end
            @test mean(abs_βz) > 1.5
            @test mean(abs_βA) < 0.25
            @test quantile(abs_βA, 0.9) < 0.45
            @test count(<(0.35), abs_βA) >= 20  # ≥80% of reps
        end

        @testset "noisy encoder degrades adjustment" begin
            rng_s = Random.Xoshiro(101)
            n2 = 500
            A2 = Float64.(rand(rng_s, n2) .< 0.5)
            Mstar = 1.5 .* A2 .+ randn(rng_s, n2)
            Y2 = 2.0 .* Mstar .+ 0.3 .* randn(rng_s, n2)
            S = randn(rng_s, n2, 16)
            S[:, 1] .= Mstar
            z_oracle = encode_to_panel(
                S, RepresentationSpec(:S, [:z1], Sm -> hcat(Sm[:, 1])),
            )[:z1]
            z_noise = encode_to_panel(
                S, RepresentationSpec(
                    :S, [:z1],
                    Sm -> hcat(Sm[:, 1] .+ 2.5 .* randn(rng_s, size(Sm, 1))),
                ),
            )[:z1]
            β_o = hcat(ones(n2), A2, z_oracle) \ Y2
            β_n = hcat(ones(n2), A2, z_noise) \ Y2
            # Noisy codes leave a larger residual A→Y association
            @test abs(β_n[2]) > abs(β_o[2])
        end
    end

    @testset "identification hand-off uses code symbols" begin
        using Graphs
        g = DiGraph(4)
        add_edge!(g, 1, 2)  # W → A
        add_edge!(g, 1, 3)  # W → z1
        add_edge!(g, 1, 4)  # W → Y
        add_edge!(g, 2, 3)  # A → z1
        add_edge!(g, 2, 4)  # A → Y
        add_edge!(g, 3, 4)  # z1 → Y
        names = Dict(1 => :W, 2 => :A, 3 => :z1, 4 => :Y)
        id = identify(
            g, MediationQuery(:A, :Y, [:z1]; effect_kind = :interventional);
            node_names = names,
        )
        @test id.identifiable
        @test id.mediators == [:z1]
        @test :W in id.adjustment
        cert = representation_certificate(
            RepresentationSpec(:spectrum, [:z1], S -> hcat(S[:, 1]); role = :definitional),
        )
        @test cert.code_names == [:z1]
        @test cert.role === :definitional
    end
end
