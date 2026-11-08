using Documenter
using Barcodes

# The examples in the docstrings can use `Barcodes` without loading it.
DocMeta.setdocmeta!(Barcodes, :DocTestSetup, :(using Barcodes); recursive = true)

makedocs(;
    modules = [Barcodes],
    authors = "Ricardo Rosa <rmsrosa@gmail.com>",
    sitename = "Barcodes.jl",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://rmsrosa.github.io/barcodes.jl",
        edit_link = "main",
    ),
    pages = [
        "Home" => "index.md",
        "Manual" => "manual.md",
        "API" => "api.md",
    ],
    doctest = true,
)

deploydocs(; repo = "github.com/rmsrosa/barcodes.jl", devbranch = "main")
