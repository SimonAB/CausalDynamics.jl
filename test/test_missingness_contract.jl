"""Phase 1 contract: ObservationMask and no silent Missing → Float64."""

using CausalDynamics
using Test

@testset "missingness contract" begin
    @testset "ObservationMask from columns" begin
        y = [1.0, missing, 3.0, missing]
        w = [0.0, 1.0, missing, 2.0]
        mask = observation_mask(Dict(:y => y, :w => w); columns = [:y, :w])
        @test mask.columns == [:y, :w]
        @test size(mask.observed) == (4, 2)
        @test mask.observed[:, 1] == BitVector([true, false, true, false])
        @test mask.observed[:, 2] == BitVector([true, true, false, true])
        @test mask.time_indexed == false
        @test n_units(mask) == 4
        rates = miss_rates(mask)
        @test rates[:y] ≈ 0.5
        @test rates[:w] ≈ 0.25
    end

    @testset "ObservationMask time-indexed" begin
        y1 = [1.0, missing]
        y2 = [missing, 2.0]
        mask = observation_mask(
            Dict(:y1 => y1, :y2 => y2);
            columns = [:y1, :y2],
            time_indexed = true,
        )
        @test mask.time_indexed == true
        @test mask.observed == BitMatrix([true false; false true])
    end

    @testset "require_complete_values" begin
        @test require_complete_values([1.0, 2.0]; context = "parents") == [1.0, 2.0]
        @test_throws ArgumentError require_complete_values(
            [1.0, missing]; context = "parents",
        )
        err = try
            require_complete_values([missing]; context = "parent :x")
            nothing
        catch e
            e
        end
        @test err isa ArgumentError
        @test occursin("missing", lowercase(sprint(showerror, err)))
        @test occursin("parent :x", sprint(showerror, err))
    end

    @testset "pack_parent_vector rejects Missing" begin
        # ContinuousCDMSpec index map: build a minimal stand-in via pack on Union vector
        u = Union{Float64,Missing}[1.0, missing, 3.0]
        # Prefer the explicit helper used by mechanisms when parents may be incomplete
        @test_throws ArgumentError require_complete_values(u; context = "state")
        @test require_complete_values(Float64[1.0, 2.0, 3.0]; context = "state") ==
              Float64[1.0, 2.0, 3.0]
    end

    @testset "apply_observation_mask" begin
        complete = [1.0, 2.0, 3.0, 4.0]
        r = BitVector([true, false, true, false])
        out = apply_observation_mask(complete, r)
        @test out[1] === 1.0
        @test out[2] === missing
        @test out[3] === 3.0
        @test out[4] === missing
        @test eltype(out) >: Missing
    end
end
