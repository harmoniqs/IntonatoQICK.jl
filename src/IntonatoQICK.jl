module IntonatoQICK

using Reexport
@reexport using Intonato

# Intonato reexports Piccolo + NamedTrajectories, so AbstractPulse, sample,
# QuantumSystem, KetTrajectory, SimulatedExperiment, MeasurementModel,
# Measurement, run_experiment, AbstractHardwareBackend, HardwareExperiment, …
# are all in scope here.
using Intonato
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

# ──── Integration tests (mock calibration→QICK loop) ─────────────────────────
include("integration_test.jl")

# ──── Exports ────────────────────────────────────────────────────────────────
export AbstractQickSoc, MockQickSoc, PyQickSoc
export load_envelope!, play_program!, acquire, dac_rate, adc_rate
export QickChannelMap, QickGenChannel
export pulse_to_envelopes, QickProgram
export iq_to_measurements
export QickBackend
export QickExperiment

end # module
