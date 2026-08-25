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
        "Scope" => "scope.md",
        "Comparison" => "comparison.md",
        "Getting Started" => "getting-started.md",
        "Hierarchical / nested units" => "hierarchy.md",
        "Missingness" => "missingness.md",
        "Integration" => [
            "Overview" => "integration.md",
            "SciML recipes" => "SCIML_INTEGRATION.md",
            "RxInfer / GraphPPL" => "RXINFER_INTEGRATION.md",
            "Associations.jl" => "ASSOCIATIONS_INTEGRATION.md",
            "Methods adoption" => "METHODS_ADOPTION.md",
            "API" => "api/integration.md",
        ],
        "API Reference" => [
            "Graph Operations" => "api/graphs.md",
            "Time-indexed graphs" => "api/time_graphs.md",
            "Identification" => "api/identification.md",
            "SCM Framework" => "api/scm.md",
            "Discrete-time CDMs" => "api/cdm.md",
            "Utilities" => "api/utils.md",
        ],
        "Examples" => "examples.md",
        "Deep SCM stress" => "stress_deep_scm.md",
        "Hierarchical nesting stress" => "stress_hierarchy.md",
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
