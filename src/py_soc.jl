# PyQickSoc — the real QICK SoC, reached over PythonCall. The `qick` package is
# imported LAZILY inside the constructor (runtime, not load-time), so loading
# IntonatoQICK and the whole mock path never touch Python. The interface methods
# below are structural — they call the qick proxy API but are validated only on a
# board, with the QICK collaboration. They are intentionally NOT exercised in CI
# (constructing a PyQickSoc requires a board / the qick package).

"""
    PyQickSoc(; bitfile=nothing, dac_rate, adc_rate)

Real QICK SoC backed by the `qick` Python package via PythonCall. `qick` is
imported lazily here; an actionable error is raised if it (or its board) is
unavailable. Hardware-only — not run in CI.
"""
mutable struct PyQickSoc <: AbstractQickSoc
    qicksoc::Py
    dac_rate::Float64
    adc_rate::Float64
end

function PyQickSoc(; bitfile = nothing, dac_rate::Real, adc_rate::Real)
    qick = try
        pyimport("qick")
    catch e
        error("PyQickSoc requires the `qick` Python package in the board's " *
              "Python environment (FPGA-side software; see " *
              "openquantumhardware/qick). `pyimport(\"qick\")` failed: $e")
    end
    qicksoc = bitfile === nothing ? qick.QickSoc() : qick.QickSoc(bitfile)
    return PyQickSoc(qicksoc, Float64(dac_rate), Float64(adc_rate))
end

dac_rate(soc::PyQickSoc) = soc.dac_rate
adc_rate(soc::PyQickSoc) = soc.adc_rate

# Structural mappings onto qick's gen-channel envelope + program API. Refined
# against the collaboration's concrete board config; validated on hardware.
function load_envelope!(soc::PyQickSoc, gen_ch::Int, idata, qdata)
    soc.qicksoc.add_envelope(ch = gen_ch, name = "env$(gen_ch)",
                             idata = pylist(idata), qdata = pylist(qdata))
    return nothing
end

function play_program!(soc::PyQickSoc, program::QickProgram)
    # A concrete QickProgram/AveragerProgram is assembled from `program` (envelopes
    # already loaded, carrier_freqs, timing) and run. Board-specific; deferred.
    error("PyQickSoc.play_program! is a hardware stub — assemble + run the qick " *
          "program on the board (deferred to the QICK collaboration).")
end

function acquire(soc::PyQickSoc, ro_chs)
    error("PyQickSoc.acquire is a hardware stub — call the qick program's " *
          "`acquire` and return per-measurement IQ (deferred to the collaboration).")
end

@testitem "PyQickSoc is an AbstractQickSoc (type only; no board in CI)" begin
    using IntonatoQICK
    @test PyQickSoc <: IntonatoQICK.AbstractQickSoc
    # Not constructed here: that needs the qick package + a board, and would
    # initialize PythonCall's interpreter. Hardware-path behavior is validated
    # by the collaboration.
end
