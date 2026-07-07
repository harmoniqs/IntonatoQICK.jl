# Name-scrub guard (Spec B §2.3, §5.5). IntonatoQICK is a PUBLIC package: its
# source must reveal no private-package identifiers — the private calibration
# package name, its strategy type, and the bare private acronym. Gating controls
# *who can run* the premium calibration node (package-entitlement: the private
# package resolving in the runner's Julia env); this guard controls *what public
# source reveals* — a separate, code-hygiene concern.
#
# The banned terms are assembled from fragments at runtime so THIS guard file
# never itself contains a literal banned term (which would trip its own check).
# Extend this list, never shrink it.

@testitem "public source is name-scrubbed of private-package identifiers" begin
    using IntonatoQICK
    # Assemble the scrub list from fragments (kept split in source on purpose).
    banned = [
        "intona" * "tissimo",   # the private calibration package name
        "ilc" * "strategy",     # its private strategy type
        "qi" * "lc",            # the bare private acronym ("NO … public")
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
