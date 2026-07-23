module IntonatoQICK

# ── DEPRECATED ────────────────────────────────────────────────────────────────
# IntonatoQICK.jl has been renamed to Strumento.jl (https://github.com/harmoniqs/Strumento.jl),
# reframed as the Julia face of the Python `strumento` QICK framework. This package stays
# registered at v0.1.0 so existing references resolve, but receives no further releases.
function __init__()
    @warn "IntonatoQICK.jl is deprecated and renamed to Strumento.jl " *
          "(https://github.com/harmoniqs/Strumento.jl). No further releases will be made here; " *
          "migrate `using IntonatoQICK` -> `using Strumento` (QickBackend->StrumentoBackend, " *
          "MockQickSoc->MockSoc, PyQickSoc->StrumentoSoc)."
end
# ──────────────────────────────────────────────────────────────────────────────

using Reexport
@reexport using Intonato

# Intonato reexports Piccolo + NamedTrajectories, so AbstractPulse, sample,
# QuantumSystem, KetTrajectory, SimulatedExperiment, MeasurementModel,
# Measurement, run_experiment, AbstractHardwareBackend, HardwareExperiment, …
# are all in scope here.
using Intonato
# QickBackend implements the AbstractHardwareBackend interface. Intonato declares
# these as generic functions, so import them explicitly to EXTEND (add methods on
# QickBackend) rather than shadow them with a local same-named function.
import Intonato: upload_pulse!, trigger!, readout, sample_rate
using LinearAlgebra
using PythonCall
using TestItems

# ──── SoC abstraction ────────────────────────────────────────────────────────
include("soc.jl")
include("channel_map.jl")

# ──── Pulse / readout translation ────────────────────────────────────────────
include("translate.jl")
include("readout.jl")

# ──── Backends ───────────────────────────────────────────────────────────────
include("mock_soc.jl")
include("backend.jl")
include("py_soc.jl")

# ──── Experiment factory ─────────────────────────────────────────────────────
include("experiment.jl")

# ──── Integration tests (mock closed-loop calibration → QICK loop) ───────────
include("integration_test.jl")

# ──── Public name-scrub guard (§2.3, §5.5) ───────────────────────────────────
include("name_scrub.jl")

# ──── Exports ────────────────────────────────────────────────────────────────
export AbstractQickSoc, MockQickSoc, PyQickSoc
export load_envelope!, play_program!, acquire, dac_rate, adc_rate
export QickChannelMap, QickGenChannel
export pulse_to_envelopes, QickProgram
export iq_to_measurements
export QickBackend
export QickExperiment

end # module
