using Documenter
using CausalDynamics
using Graphs

# Optional live figures when DAGMakie is available in the docs environment
const HAS_DAGMAKIE = try
    @eval using DAGMakie
    @eval using CairoMakie
    CairoMakie.activate!(type = "png")
    CairoMakie.enable_only_mime!("png")
    true
catch
    false
end

makedocs(
    sitename = "CausalDynamics.jl",
    authors = "Simon A. Babayan",
    modules = [CausalDynamics],
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", nothing) == "true",
        canonical = "https://simonab.github.io/CausalDynamics.jl",
        assets = String[],
        example_size_threshold = 0,
    ),
    pages = [
        "Home" => "index.md",
        "Scope" => "scope.md",
        "Comparison" => "comparison.md",
        "Getting Started" => "getting-started.md",
        "Integration" => [
            "Overview" => "integration.md",
            "SciML recipes" => "SCIML_INTEGRATION.md",
            "RxInfer / GraphPPL" => "RXINFER_INTEGRATION.md",
            "Associations.jl" => "ASSOCIATIONS_INTEGRATION.md",
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
        "References" => "references.md",
    ],
    checkdocs = :exports,
    # Cross-references are strict; `missing_docs` stays a warning while
    # unexported internals are progressively added to @docs blocks.
    warnonly = [:missing_docs],
)

if get(ENV, "CI", nothing) == "true"
    deploydocs(
        repo = "github.com/SimonAB/CausalDynamics.jl.git",
        devbranch = "main",
        push_preview = true,
    )
end
