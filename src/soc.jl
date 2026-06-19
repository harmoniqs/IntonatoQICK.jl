# AbstractQickSoc — the abstraction over a QICK board controller. The mock
# (`MockQickSoc`, pure Julia) and the real proxy (`PyQickSoc`, lazy qick) both
# implement it, so `QickBackend` is written once against this interface.

"""
    AbstractQickSoc

Abstraction over a QICK SoC (board controller). Concrete subtypes implement:

- `load_envelope!(soc, gen_ch, idata, qdata)` — load a complex envelope onto a
  generator channel's waveform memory.
- `play_program!(soc, program::QickProgram)` — arm/run the program (envelopes +
  carrier frequencies + timing + measurement indices).
- `acquire(soc, ro_chs) → raw` — read out; returns raw per-measurement data.
- `dac_rate(soc) → Float64`, `adc_rate(soc) → Float64` — sample rates (Hz).
"""
abstract type AbstractQickSoc end

# Generic fallbacks give an actionable error if a subtype forgets a method.
load_envelope!(soc::AbstractQickSoc, args...) =
    error("load_envelope! not implemented for $(typeof(soc))")
play_program!(soc::AbstractQickSoc, args...) =
    error("play_program! not implemented for $(typeof(soc))")
acquire(soc::AbstractQickSoc, args...) =
    error("acquire not implemented for $(typeof(soc))")
dac_rate(soc::AbstractQickSoc) =
    error("dac_rate not implemented for $(typeof(soc))")
adc_rate(soc::AbstractQickSoc) =
    error("adc_rate not implemented for $(typeof(soc))")

@testitem "AbstractQickSoc interface fallbacks error" begin
    using IntonatoQICK
    struct _BareSoc <: IntonatoQICK.AbstractQickSoc end
    s = _BareSoc()
    @test_throws ErrorException load_envelope!(s, 0, [1.0], [0.0])
    @test_throws ErrorException acquire(s, [0])
    @test_throws ErrorException dac_rate(s)
end
