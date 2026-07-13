using IntonatoQICK
using PiccoloDocsTemplate

pages = ["Home" => "index.md", "Library" => "lib.md"]

generate_docs(
    @__DIR__,
    "IntonatoQICK",
    [IntonatoQICK],
    pages;
    # index.md is hand-authored (committed) rather than regenerated from the
    # README, so leave make_index at false to avoid clobbering it at build time.
    make_index = false,
    make_literate = false,
    make_assets = false,
    format_kwargs = (canonical = "https://docs.harmoniqs.co/IntonatoQICK.jl",),
    versions = ["dev" => "dev", "stable" => "v^", "v#.#"],
)
