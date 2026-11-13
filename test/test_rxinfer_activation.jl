using Test

@testset "RxInfer extension activation guidance" begin
    code = """
    using CausalDynamics, RxInfer, GraphPPL
    @assert !CausalDynamics.has_rxinfer()
    message = try
        CausalDynamics.infer_linear_state_space([0.0])
        error("expected an unloaded-extension error")
    catch exception
        sprint(showerror, exception)
    end
    @assert occursin("DataFrames", message)
    using DataFrames
    @assert CausalDynamics.has_rxinfer()
    fit = CausalDynamics.infer_linear_state_space([0.0];
        transition=0.9, observation=1.0, process_covariance=0.1,
        observation_covariance=0.2, initial_mean=0.0, initial_covariance=1.0)
    @assert fit.certificate.exact
    """
    command = `$(Base.julia_cmd()) --project=$(dirname(Base.active_project())) --threads=auto -e $code`
    @test success(pipeline(command; stdout = devnull))
end
