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
        "Getting Started" => "getting-started.md",
        "Integration" => [
            "Overview" => "integration.md",
            "RxInfer / GraphPPL" => "RXINFER_INTEGRATION.md",
            "API" => "api/integration.md",
        ],
        "API Reference" => [
            "Graph Operations" => "api/graphs.md",
            "Identification" => "api/identification.md",
            "SCM Framework" => "api/scm.md",
            "Utilities" => "api/utils.md",
        ],
        "Examples" => "examples.md",
        "References" => "references.md",
    ],
    checkdocs = :exports,
    warnonly = [:cross_references, :missing_docs],
)

if get(ENV, "CI", nothing) == "true"
    deploydocs(
        repo = "github.com/SimonAB/CausalDynamics.jl.git",
        devbranch = "main",
        push_preview = true,
    )
end
