using Documenter
using CausalDynamics
using Graphs
using DAGMakie
using CairoMakie

# Prefer PNG MIME so Documenter writes figure files instead of huge inline HTML
# (same convention as DAGMakie.jl docs).
CairoMakie.activate!(type = "png")
CairoMakie.enable_only_mime!("png")

makedocs(
    sitename = "CausalDynamics.jl",
    authors = "Simon A. Babayan",
    modules = [CausalDynamics],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://simonab.github.io/CausalDynamics.jl",
        assets = String[],
        example_size_threshold = 0,  # always write @example figures to files
    ),
    pages = [
        "Home" => "index.md",
        "Choosing an approach" => "orientation.md",
        "Getting Started" => "getting-started.md",
        "Guides" => [
            "Worked examples" => "examples.md",
            "Hierarchical & nested units" => "hierarchy.md",
            "Missingness" => "missingness.md",
        ],
        "Integrations" => [
            "Overview & estimation bridges" => "integration.md",
            "SciML & ODE discovery" => "SCIML_INTEGRATION.md",
            "RxInfer & state-space" => "RXINFER_INTEGRATION.md",
            "Exact linear Gaussian states" => "linear_bayesian_states.md",
            "Known-noise nonlinear states" => "nonlinear_states.md",
            "Associations.jl & IEE" => "ASSOCIATIONS_INTEGRATION.md",
        ],
        "API Reference" => [
            "Graph operations" => "api/graphs.md",
            "Time-indexed graphs" => "api/time_graphs.md",
            "Identification" => "api/identification.md",
            "Structural causal models" => "api/scm.md",
            "Discrete-time CDMs" => "api/cdm.md",
            "Panels, observation & masks" => "api/panels.md",
            "Hierarchy & relational grounding" => "api/hierarchy.md",
            "Mechanisms, representations & contracts" => "api/mechanisms_contracts.md",
            "Integrations API" => "api/integration.md",
            "Utilities & plotting" => "api/utils.md",
        ],
        "Architecture & Validation" => [
            "Scope & design boundaries" => "scope.md",
            "Terminology" => "terminology.md",
            "Ecosystem comparison" => "comparison.md",
            "Stress validation" => "stress.md",
        ],
        "References" => "references.md",
    ],
    checkdocs = :exports,
    # Fail on broken `@ref` / missing `@docs` coverage for documented exports.
    warnonly = false,
)

if get(ENV, "CI", nothing) == "true"
    deploydocs(
        repo = "github.com/SimonAB/CausalDynamics.jl.git",
        devbranch = "main",
        push_preview = true,
    )
end
