# IntonatoQICK.jl

A [QICK](https://github.com/openquantumhardware/qick) hardware backend for
[Intonato](https://github.com/harmoniqs/Intonato.jl)'s closed-loop quantum
optimal control (QILC). It bridges an Intonato `PulseTuningProblem` to a QICK
RFSoC board over [PythonCall](https://github.com/JuliaPy/PythonCall.jl), so a
pulse designed against a nominal model can be played on real hardware and its
readout fed straight back into the tuning loop.

The package owns the *mechanism* — how a drive maps onto generator channels, how
a pulse is sampled into waveform envelopes, how raw IQ becomes measurements. The
device-specific *policy* (channel routing, carrier frequencies, the IQ→state
discriminator) is yours to supply.

## What it provides

- **[`QickBackend`](@ref)** `<: AbstractHardwareBackend` — implements the
  Intonato hardware interface (`upload_pulse!` / `trigger!` / `readout` /
  `sample_rate`) over an abstract [`AbstractQickSoc`](@ref).
- **[`MockQickSoc`](@ref)** — a pure-Julia "board" that simulates execution by
  rolling the played pulse through a known `QuantumSystem` and emitting synthetic
  IQ. The whole QILC→QICK loop runs and is tested with **no Python and no
  hardware**.
- **[`PyQickSoc`](@ref)** — the real board, reached over PythonCall with a
  **lazy `qick` import** (only touched on a board; never off-board or in CI).
  Some methods are hardware stubs, finalized with the QICK collaboration.
- **[`QickChannelMap`](@ref)** and [`QickGenChannel`](@ref) (device policy: drive
  → gen-channel / carrier / IQ) plus a caller-supplied **discriminator**
  (IQ → state).
- **[`QickExperiment`](@ref)`(backend; measurement_model)`** → an Intonato
  `HardwareExperiment` you drop straight into `PulseTuningProblem`.

## The three-verb hardware boundary

`QickBackend` reduces a board to three coarse verbs, played once per experiment
evaluation by the [`QickExperiment`](@ref) `run` closure (the tuning chassis
never calls them directly):

1. **`upload_pulse!(backend, pulse)`** — sample the pulse onto each generator
   channel's DAC grid ([`pulse_to_envelopes`](@ref)) and load the resulting
   complex `(idata, qdata)` envelopes into waveform memory.
2. **`trigger!(backend)`** — arm and run the loaded program on the board.
3. **`readout(backend)`** — acquire raw per-measurement IQ, then map it through
   the discriminator into a `Vector{Measurement}` ([`iq_to_measurements`](@ref)).

Any concrete board only has to implement the [`AbstractQickSoc`](@ref) interface
(`load_envelope!`, `play_program!`, `acquire`, `dac_rate`, `adc_rate`);
`QickBackend` is written once against that abstraction.

## Usage (mock)

The mock SoC runs the full loop end-to-end without Python or hardware. It takes
the "true" device dynamics (optionally mismatched from the nominal model the
pulse was designed against), rolls the played pulse through them, and returns
synthetic IQ that the trivial `real` discriminator inverts exactly.

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

## Swapping to real hardware

Swap [`MockQickSoc`](@ref) for [`PyQickSoc`](@ref) on a real QICK board — nothing
else in the setup changes, because both implement [`AbstractQickSoc`](@ref):

```julia
soc = PyQickSoc(; dac_rate = 6.144e9, adc_rate = 2.4576e9)
```

`PyQickSoc` imports the `qick` Python package lazily inside its constructor, so
loading `IntonatoQICK` (and the entire mock path) never touches Python. The
`qick` package must be present in the board's Python environment; an actionable
error is raised if it or its board is unavailable. `play_program!` / `acquire`
are hardware stubs, refined against the collaboration's concrete board config and
validated on hardware.

## The tuning strategy is separate

`IntonatoQICK` and `Intonato` together provide the public **chassis** and the
**hardware seam** — the `PulseTuningProblem` loop, the `AbstractTuningStrategy`
interface, and this QICK backend. The default `IdentityStrategy` runs the loop
as a no-op (it leaves the pulse unchanged), which is exactly what you want for
wiring up and validating a device integration.

A concrete tuning strategy — the policy that actually improves the pulse from
measured data — is supplied separately, in an entitlement-gated package. This
repository documents and ships the mechanism, not that convergence method.

## Data-provenance note

Intonato's `ExperimentRecord` logging is **not** triggered inside the tuning
chassis loop today (the loop invokes the experiment with no logger, and the
record's `raw` field is hardcoded `nothing`). So [`QickBackend`](@ref) stashes
the most recent raw IQ in `backend.last_raw`, and a *manual*
`run_experiment(qexp, pulse; logger = …)` logs measurement-level records. Full
raw-IQ-into-record provenance during closed-loop runs is a planned Intonato
enhancement, tracked separately.

Note that under a line search the chassis evaluates the experiment several times
per outer iteration, so `last_raw` reflects the *last probe*, not necessarily the
accepted iterate.

## Status

Interface-complete with a tested mock loop. Real-board validation, calibration
routines, and multi-board orchestration are out of scope for v0 (pursued with the
QICK collaboration).

## Reference

See the [Library](@ref API) page for the full reference.
