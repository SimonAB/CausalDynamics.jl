using Documenter
using CausalDynamics

makedocs(
    sitename = "CausalDynamics.jl",
    authors = "CDCS Book Contributors",
    format = Documenter.HTML(
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://yourusername.github.io/CausalDynamics.jl",
        assets = String[],
    ),
    pages = [
        "Home" => "index.md",
        "Getting Started" => "getting-started.md",
        "Integration" => "integration.md",
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
    repo = "github.com/yourusername/CausalDynamics.jl.git",
    devbranch = "main",
)
