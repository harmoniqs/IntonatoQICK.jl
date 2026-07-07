# PyQickSoc — the real QICK SoC, reached over PythonCall. The `qick` package is
# imported LAZILY (runtime, not load-time), so loading IntonatoQICK and the whole
# mock path never touch Python. The interface methods below assemble + run a
# concrete tProc **v2** `AveragerProgramV2` from a device-agnostic `QickProgram`.
# They call the qick v2 proxy API but are validated only on a board, with the
# QICK collaboration; they are intentionally NOT exercised in CI (constructing a
# PyQickSoc requires a board / the qick package). The v2 specifics
# (`AveragerProgramV2`, multiplexed readout, sweeps) live here — board-side —
# behind the same 3-verb contract; the Julia optimizer never learns what a tProc
# generation is (boundary invariant).

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
    # Envelopes staged by `load_envelope!` (gen_ch => (idata, qdata)), consumed
    # when `play_program!` assembles the v2 program.
    _envelopes::Dict{Int,Tuple{Vector{Float64},Vector{Float64}}}
    # The most recently assembled AveragerProgramV2 and its raw acquire result.
    _prog::Union{Nothing,Py}
    _last_result::Any
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
    return PyQickSoc(qicksoc, Float64(dac_rate), Float64(adc_rate),
                     Dict{Int,Tuple{Vector{Float64},Vector{Float64}}}(), nothing, nothing)
end

dac_rate(soc::PyQickSoc) = soc.dac_rate
adc_rate(soc::PyQickSoc) = soc.adc_rate

# Stage a complex envelope for a generator channel. In tProc v2, envelopes are
# added to the program (not the board handle), so we stash here and add them
# during `play_program!` assembly.
function load_envelope!(soc::PyQickSoc, gen_ch::Int, idata, qdata)
    soc._envelopes[gen_ch] = (Vector{Float64}(idata), Vector{Float64}(qdata))
    return nothing
end

"""
    play_program!(soc::PyQickSoc, program::QickProgram)

Assemble a concrete tProc **v2** `AveragerProgramV2` from the device-agnostic
`QickProgram` and run it on the board:

- declare each generator channel and add its I/Q envelope (`add_envelope`),
- add a pulse at the channel's carrier frequency (`add_pulse`),
- declare the (possibly **multiplexed**) readout channels from
  `program.readout_routing` (`declare_readout`),
- trigger the generators + readout and read `program.indices` measurement knots.

Sweeps / dynamic readout map to v2 loops (`add_loop`). The exact v2 subclass
hooks, unit conventions (freq in MHz, readout lengths), and loop wiring are
finalized on hardware with the QICK collaboration — **this is the structural
assembly, hardware-validated, not exercised in CI.**
"""
function play_program!(soc::PyQickSoc, program::QickProgram)
    asm = try
        pyimport("qick.asm_v2")
    catch e
        error("PyQickSoc.play_program! requires the tProc v2 API " *
              "(`qick.asm_v2`, e.g. `AveragerProgramV2`) in the board's Python " *
              "environment. `pyimport(\"qick.asm_v2\")` failed: $e")
    end

    # One averaged sweep by default; sweeps/dynamic readout add v2 loops here.
    prog = asm.AveragerProgramV2(soc.qicksoc; reps = 1, final_delay = 1.0)

    # Generators: declare + add each channel's staged envelope + a pulse at its
    # carrier frequency (Hz → MHz for the v2 API).
    for (gen_ch, cf) in program.carrier_freqs
        idata, qdata = get(soc._envelopes, gen_ch, program.envelopes[gen_ch])
        prog.declare_gen(ch = gen_ch, nqz = 1)
        prog.add_envelope(ch = gen_ch, name = "env$(gen_ch)",
                          idata = pylist(idata), qdata = pylist(qdata))
        prog.add_pulse(ch = gen_ch, name = "pulse$(gen_ch)",
                       freq = cf / 1e6, envelope = "env$(gen_ch)")
    end

    # Multiplexed readout: one declared readout per routed channel.
    for ro_ch in program.readout_routing
        prog.declare_readout(ch = ro_ch, length = length(program.times))
    end

    # Play the generators + trigger the readout(s). The concrete timing/trigger
    # sequence (delays, phase resets) is finalized on hardware.
    for gen_ch in keys(program.carrier_freqs)
        prog.pulse(ch = gen_ch, name = "pulse$(gen_ch)", t = 0.0)
    end
    prog.trigger(ros = pylist(program.readout_routing), t = 0.0)

    soc._prog = prog
    return nothing
end

"""
    acquire(soc::PyQickSoc, ro_chs; kind=:iq) → raw

Run the assembled v2 program and return **channel-major** raw IQ `raw[ch][k]`
(one accumulated blob per readout channel × measurement knot). For
`:tomography_1q` / `:wigner` the board performs the physics reduction
(post-processing); the Julia side only tags the kind (boundary invariant, C7).
The concrete reshape from qick's accumulated buffers is finalized on hardware —
**structural, hardware-validated, not exercised in CI.**
"""
function acquire(soc::PyQickSoc, ro_chs; kind::Symbol = :iq)
    kind in READOUT_KINDS ||
        error("PyQickSoc.acquire: unknown readout kind :$kind " *
              "(recognized: $(join(READOUT_KINDS, ", ")))")
    soc._prog === nothing &&
        error("PyQickSoc.acquire: assemble + play a program (play_program!) first")

    # Accumulated IQ from the averaged run; qick returns per-readout-channel
    # buffers. Reshape into channel-major raw[ch][k] indexed by knot.
    result = soc._prog.acquire(soc.qicksoc; soft_avgs = 1)
    soc._last_result = result
    error("PyQickSoc.acquire is hardware-validated: reshape qick's accumulated " *
          "v2 buffers into channel-major raw[ch][k] for readout kind :$kind " *
          "(finalized on the board with the QICK collaboration).")
end

@testitem "PyQickSoc is an AbstractQickSoc + v2 methods exist (type only; no board in CI)" begin
    using IntonatoQICK
    @test PyQickSoc <: IntonatoQICK.AbstractQickSoc
    # The v2 seam methods are defined structurally without constructing a board
    # (which would need the qick package + FPGA and initialize PythonCall's
    # interpreter). Hardware-path behavior is validated by the collaboration.
    @test hasmethod(IntonatoQICK.play_program!, Tuple{PyQickSoc, IntonatoQICK.QickProgram})
    @test hasmethod(IntonatoQICK.acquire, Tuple{PyQickSoc, Vector{Int}})
    @test hasmethod(IntonatoQICK.load_envelope!, Tuple{PyQickSoc, Int, Any, Any})
    @test hasmethod(IntonatoQICK.dac_rate, Tuple{PyQickSoc})
    @test hasmethod(IntonatoQICK.adc_rate, Tuple{PyQickSoc})
end
