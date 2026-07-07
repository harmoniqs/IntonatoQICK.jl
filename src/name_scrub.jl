# Name-scrub guard (Spec B §2.3, §5.5). IntonatoQICK is a PUBLIC package. What it
# reveals is split deliberately (Aaron 2026-07-07):
#   - ALLOWED (funnel): the product NAME "Intonatissimo" + the capability phrase
#     "closed-loop calibration" — an intentional wink/nod advertising the premium
#     package at the point of need to drive licensing. NOT banned here.
#   - BANNED (private METHOD): the strategy type and the bare method acronym.
# Gating controls *who can run* the premium node (package-entitlement); this guard
# controls *what public source reveals of the METHOD* — a code-hygiene concern.
#
# The banned terms are assembled from fragments at runtime so THIS guard file
# never itself contains a literal banned term (which would trip its own check).
# Extend this list, never shrink it — but the product NAME stays OUT of it (funnel).

@testitem "public source is name-scrubbed of the private METHOD (not the product name)" begin
    using IntonatoQICK
    # Assemble the scrub list from fragments (kept split in source on purpose).
    # The product name "Intonatissimo" is INTENTIONALLY absent — it is the funnel.
    banned = [
        "ilc" * "strategy",     # the private strategy type
        "qi" * "lc",            # the bare private method acronym ("NO … public")
    ]
    srcdir = joinpath(pkgdir(IntonatoQICK), "src")
    offenders = String[]
    for (root, _, files) in walkdir(srcdir)
        for f in files
            endswith(f, ".jl") || continue
            text = lowercase(read(joinpath(root, f), String))
            for b in banned
                occursin(b, text) && push!(offenders, "$(f): contains a banned term")
            end
        end
    end
    @test isempty(offenders)
end
