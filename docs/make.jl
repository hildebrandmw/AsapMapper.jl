using Documenter, AsapMapper

makedocs(
    modules = [AsapMapper],
    sitename = "AsapMapper",
    format = Documenter.HTML(prettyurls = get(ENV, "CI", nothing) == "true"),
    authors = "Mark Hildebrand, Arthur Hlaing",
    pages = [
        "Home" => "index.md",
        "tutorial.md"
    ]
)

deploydocs(
    repo = "github.com/hildebrandmw/AsapMapper.jl.git",
    target = "build",
)
