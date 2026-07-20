using Documenter
using CausalDynamics

makedocs(
    sitename = "CausalDynamics.jl",
    authors = "CDCS Book Contributors",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://simonab.github.io/CausalDynamics.jl",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Terminology" => "terminology.md",
        "Getting Started" => "getting-started.md",
        "Integration" => [
            "Overview" => "integration.md",
            "RxInfer / GraphPPL" => "RXINFER_INTEGRATION.md",
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
    modules = [CausalDynamics],
    checkdocs = :exports,
    warnonly = [:cross_references],
)

deploydocs(
    repo = "github.com/SimonAB/CausalDynamics.jl.git",
    devbranch = "main",
)
