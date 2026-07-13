# API

```@meta
CollapsedDocStrings = true
```

The public surface of `IntonatoQICK`: the SoC abstraction and its two
implementations, the device-policy channel map, the pulse/readout translation
layer, the hardware backend, and the experiment factory. `IntonatoQICK`
re-exports `Intonato` (and, transitively, `Piccolo` and `NamedTrajectories`), so
`QuantumSystem`, `AbstractPulse`, `MeasurementModel`, `HardwareExperiment`,
`run_experiment`, and friends are available from a single `using IntonatoQICK`.
Those symbols are documented in the [Intonato](https://docs.harmoniqs.co/Intonato.jl)
and [Piccolo](https://docs.harmoniqs.co/Piccolo.jl) references; only the symbols
defined in `IntonatoQICK` are listed below.

```@autodocs
Modules = [IntonatoQICK]
Order = [:type, :function]
```
