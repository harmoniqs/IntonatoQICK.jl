# IntonatoQICK.jl

A [QICK](https://github.com/openquantumhardware/qick) hardware backend for
[Intonato](https://github.com/harmoniqs/Intonato.jl)'s closed-loop quantum
optimal control (QILC). Bridges a Intonato `PulseTuningProblem` to a QICK RFSoC
board via [PythonCall](https://github.com/JuliaPy/PythonCall.jl).

## What it provides

- **`QickBackend <: AbstractHardwareBackend`** — implements the Intonato
  hardware interface (`upload_pulse!` / `trigger!` / `readout` / `sample_rate`)
  over an abstract `AbstractQickSoc`.
- **`MockQickSoc`** — a pure-Julia "board" that simulates execution by rolling
  the played pulse through a known `QuantumSystem` and emitting synthetic IQ. The
  whole QILC→QICK loop runs and is tested with **no Python and no hardware**.
- **`PyQickSoc`** — the real board, reached over PythonCall with a **lazy `qick`
  import** (only on a board; never touched off-board or in CI). Some methods are
  hardware stubs, finalized with the QICK collaboration.
- **`QickChannelMap`** (device policy: drive → gen-channel/carrier/IQ) and a
  caller-supplied **discriminator** (IQ → state). The package owns the
  mechanism; the device-specific config is yours.
- **`QickExperiment(backend; measurement_model)`** → a Intonato
  `HardwareExperiment` you drop straight into `PulseTuningProblem`.

## Usage (mock)

```julia
using IntonatoQICK

# True device dynamics the "board" has (here with a model mismatch):
sys_true = QuantumSystem(1.1 * σz, [σx], [1.0])
soc = MockQickSoc(sys_true, ψ_init, ψ_goal; dac_rate = 80.0)

map   = QickChannelMap([QickGenChannel(0, 5e9; i_drive = 1)]; n_drives = 1)
model = MeasurementModel(:ψ̃, [populations], [N])
qexp  = QickExperiment(QickBackend(soc, map, [N]); measurement_model = model)

# Plug into Intonato's QILC chassis (a concrete tuning strategy is supplied separately):
ptp = PulseTuningProblem(qcp, qexp, model; R_tr = (u = 0.1,), Q_meas = 10.0)
solve!(ptp; max_iter = 10)
```

Swap `MockQickSoc` for `PyQickSoc(; dac_rate, adc_rate)` on a real QICK board.

## Data-provenance note

Intonato's `ExperimentRecord` logging is **not** triggered inside the QILC
chassis loop today (the chassis calls `run_experiment` with no logger, and the
record's `raw` field is hardcoded `nothing`). So `QickBackend` stashes the most
recent raw IQ in `backend.last_raw`, and a *manual*
`run_experiment(qexp, pulse; logger=…)` logs measurement-level records. Full
raw-IQ-into-record provenance during closed-loop runs is a planned Intonato
enhancement (thread a `logger` through `solve!`; surface raw from the `run`
closure), tracked separately.

## Status

Interface-complete with a tested mock loop. Real-board validation, calibration
routines, and multi-board orchestration are out of scope for v0 (with the QICK
collaboration). Registered in the General registry (v0.1.0).
