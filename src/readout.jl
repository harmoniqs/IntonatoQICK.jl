# Readout conversion (pure functions): raw multiplexed IQ → Vector{Measurement}.
#
# `raw` is **channel-major**: `raw[ch][k]` is the IQ blob from readout channel
# `ch` (1:length(readout_chs)) at measurement knot `indices[k]` (into 1:N). A
# single readout channel reduces to `raw[1][k]` and reproduces the pre-multiplex
# behavior exactly. The caller-supplied `discriminator` maps one IQ blob → a data
# vector (e.g. level populations or Pauli expectations); it is the only
# device/calibration-specific step on the readout side, so it is supplied by the
# user, not owned here.
#
# Readout KIND lives behind the single `readout` verb (never a v2 concept in
# Julia): `:iq` is reduced Julia-side (raw IQ → discriminator); `:wigner` and
# `:tomography_1q` are reduced BOARD-side (`expt_service` / the qick program
# performs the Wigner / tomography physics — the discriminator is not owned here)
# and are tagged + passed through. A kind outside the recognized set is a typed
# error, never a crash (never-reject).

"""
Recognized readout kinds behind the single `readout` verb. `:iq` is reduced
Julia-side; `:tomography_1q` / `:wigner` are reduced board-side and passed
through. Extend (never shrink) as board-side readout plugins are added.
"""
const READOUT_KINDS = (:iq, :tomography_1q, :wigner)

"""
    iq_to_measurements(raw, discriminator, indices) → Vector{Measurement}

Reduce a multiplexed raw IQ acquisition to one `Measurement` per knot index.

`raw` is **channel-major** — `raw[ch][k]` is the IQ blob from readout channel `ch`
at knot `indices[k]`; every channel must supply exactly `length(indices)` blobs
(`length(raw) == length(readout_chs)` is guaranteed by `acquire`'s contract).
For each knot the per-channel `discriminator` outputs are concatenated into one
data vector tagged with the knot index, so the result has `length(indices)`
measurements regardless of channel count (one readout channel = pre-multiplex).
"""
function iq_to_measurements(raw::AbstractVector, discriminator, indices::Vector{Int})
    isempty(raw) &&
        error("iq_to_measurements: empty raw (no readout channels)")
    for (ch, blobs) in enumerate(raw)
        length(blobs) == length(indices) ||
            error("iq_to_measurements: readout channel $ch has $(length(blobs)) " *
                  "blobs vs $(length(indices)) knot indices")
    end
    return [Measurement(
                reduce(vcat, (collect(Float64, discriminator(raw[ch][k]))
                              for ch in eachindex(raw))),
                indices[k])
            for k in eachindex(indices)]
end

"""
    reduce_readout(kind, raw, discriminator, indices) → Vector{Measurement}

Dispatch a raw multiplexed acquisition (`raw[ch][k]`, see [`iq_to_measurements`])
on the readout `kind` behind the single `readout` verb:

- `:iq` — reduced Julia-side via `discriminator` (raw IQ → data), i.e.
  [`iq_to_measurements`].
- `:tomography_1q`, `:wigner` — the **board** performs the physics reduction
  (`expt_service` / the qick program); `raw` already holds the board-reduced
  values, which are tagged and passed through here (no Wigner / tomography math
  in the Julia package — boundary invariant, C7).
- anything else — a **typed error** (`readout(kind=…)` never crashes; §5.7).
"""
function reduce_readout(kind::Symbol, raw::AbstractVector, discriminator,
                        indices::Vector{Int})
    if kind === :iq
        return iq_to_measurements(raw, discriminator, indices)
    elseif kind === :tomography_1q || kind === :wigner
        # Board-reduced (C7): the physics reduction happened board-side; wrap the
        # already-reduced per-channel values as measurements. Shaping matches :iq
        # (a board-reduced blob is real-valued; the default discriminator `real`
        # is the identity on it).
        return iq_to_measurements(raw, discriminator, indices)
    else
        known = join(READOUT_KINDS, ", ")
        error("reduce_readout: unknown readout kind :$kind (recognized: $known). " *
              "A new readout is a board-side plugin, not a contract change.")
    end
end

@testitem "iq_to_measurements maps multiplexed blobs to measurements at indices" begin
    using IntonatoQICK
    # channel-major raw[ch][k]: one readout channel, two knots.
    raw = [[ComplexF64[0.7, 0.3], ComplexF64[0.2, 0.8]]]
    indices = [5, 11]
    ms = iq_to_measurements(raw, b -> real.(b), indices)
    @test length(ms) == 2
    @test ms[1].data ≈ [0.7, 0.3]
    @test ms[1].index == 5
    @test ms[2].index == 11
    # blob-count mismatch throws
    @test_throws ErrorException iq_to_measurements(raw, b -> real.(b), [1])
    # empty raw (no readout channels) throws
    @test_throws ErrorException iq_to_measurements(Vector{Vector{ComplexF64}}[], b -> real.(b), indices)
end

@testitem "iq_to_measurements concatenates multiplexed channels per knot" begin
    using IntonatoQICK
    # Two readout channels, two knots — channel-major raw[ch][k].
    raw = [
        [ComplexF64[0.7, 0.3], ComplexF64[0.2, 0.8]],   # channel 1 at knots 5, 11
        [ComplexF64[0.6, 0.4], ComplexF64[0.1, 0.9]],   # channel 2 at knots 5, 11
    ]
    indices = [5, 11]
    ms = iq_to_measurements(raw, b -> real.(b), indices)
    @test length(ms) == length(indices)                 # one measurement per knot
    @test ms[1].data ≈ [0.7, 0.3, 0.6, 0.4]             # ch1 ⧺ ch2 at knot 5
    @test ms[2].data ≈ [0.2, 0.8, 0.1, 0.9]             # ch1 ⧺ ch2 at knot 11
end

@testitem "reduce_readout kind dispatch + unknown-kind error" begin
    using IntonatoQICK
    # in-test symbols (fresh module): channel-major raw, 2 channels × 2 knots.
    indices = [5, 11]
    discriminator = b -> real.(b)
    raw = [
        [ComplexF64[0.7, 0.3], ComplexF64[0.2, 0.8]],
        [ComplexF64[0.6, 0.4], ComplexF64[0.1, 0.9]],
    ]
    # :iq reduces Julia-side; one Measurement per knot (channels concatenated).
    ms = IntonatoQICK.reduce_readout(:iq, raw, discriminator, indices)
    @test length(ms) == length(indices)
    @test ms[1].index == 5 && ms[2].index == 11
    @test ms[1].data ≈ [0.7, 0.3, 0.6, 0.4]
    # :wigner / :tomography_1q are board-reduced pass-throughs (valid shape).
    mw = IntonatoQICK.reduce_readout(:wigner, raw, discriminator, indices)
    @test length(mw) == length(indices)
    mt = IntonatoQICK.reduce_readout(:tomography_1q, raw, discriminator, indices)
    @test length(mt) == length(indices)
    # Unknown kind is a typed error, never a crash (§5.7).
    @test_throws ErrorException IntonatoQICK.reduce_readout(:nonexistent, raw, discriminator, indices)
    # A recognized kind on a malformed (wrong blob count) raw is still a typed error.
    bad = [[ComplexF64[0.7, 0.3]]]        # 1 blob vs 2 indices
    @test_throws ErrorException IntonatoQICK.reduce_readout(:iq, bad, discriminator, indices)
end
