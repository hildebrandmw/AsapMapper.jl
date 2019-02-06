using Documenter, AsapMapper

makedocs(
    modules = [AsapMapper],
    sitename = "AsapMapper",
    format = Documenter.HTML(),
    html_prettyurls = get(ENV, "CI", nothing) == "true",
    authors = "Mark Hildebrand, Arthur Hlaing",
    pages = [
        "Home" => "index.md",
        "tutorial.md"
    ]
)

deploydocs(
    repo = "github.com/hildebrandmw/AsapMapper.jl.git",
    osname = "linux",
    target = "build",
    deps = nothing,
    make = nothing,
)
