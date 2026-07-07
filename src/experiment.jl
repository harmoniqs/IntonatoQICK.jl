# QickExperiment — wraps a QickBackend as an Intonato `HardwareExperiment`, the
# seam the QILC `PulseTuningProblem` chassis consumes. The `run` closure chains
# translate→upload→trigger→readout→discriminate into a `Vector{Measurement}`.

"""
    QickExperiment(backend; measurement_model, kind=:iq) → HardwareExperiment

Build a `HardwareExperiment` whose `run(pulse)` uploads/plays `pulse` on
`backend`'s SoC and reduces the readout into measurements. The `measurement_model`
annotates logged `ExperimentRecord`s with true provenance (rather than the
identity placeholder); its indices must match `backend.indices`.

`kind` selects the readout behind the single `readout` verb (`:iq` | `:wigner` |
`:tomography_1q`, [`reduce_readout`](@ref)). It is forwarded to the board so it
performs the right measurement, and used to reduce the raw acquisition. `:iq`
reduces Julia-side via `backend.discriminator`; `:wigner` / `:tomography_1q` are
reduced board-side and passed through (boundary invariant, C7). An unrecognized
kind is a typed error, never a crash (§5.7).

Plug the result into `PulseTuningProblem(qcp, qick_exp, model; …)`.
"""
function QickExperiment(backend::QickBackend; measurement_model::MeasurementModel,
                        kind::Symbol = :iq)
    if !(kind in READOUT_KINDS)
        known = join(READOUT_KINDS, ", ")
        error("QickExperiment: unknown readout kind :$kind (recognized: $known)")
    end
    run = pulse -> begin
        upload_pulse!(backend, pulse)
        trigger!(backend)
        raw = readout(backend; kind = kind)     # raw IQ; the board measures per-kind
        reduce_readout(kind, raw, backend.discriminator, backend.indices)
    end
    return HardwareExperiment(run, measurement_model)
end

@testitem "QickExperiment produces valid, deterministic measurements" begin
    using IntonatoQICK
    using LinearAlgebra
    σx = ComplexF64[0 1; 1 0]; σz = ComplexF64[1 0; 0 -1]
    sys = QuantumSystem(1.0 * σz, [σx], [1.0])
    N = 11
    pulse = LinearSplinePulse(0.1 .* randn(1, N), collect(range(0.0, 5.0, length=N)))
    map = QickChannelMap([QickGenChannel(0, 5e9; i_drive=1)]; n_drives=1)
    model = MeasurementModel(:ψ̃, [populations], [N])

    soc = MockQickSoc(sys, ComplexF64[1, 0], ComplexF64[0, 1]; dac_rate=50.0)
    backend = QickBackend(soc, map, [N])
    qexp = QickExperiment(backend; measurement_model=model)

    y1 = run_experiment(qexp, pulse)
    y2 = run_experiment(qexp, pulse)
    @test y1 isa Vector{<:Measurement}
    @test length(y1) == 1 && y1[1].index == N
    @test sum(y1[1].data) ≈ 1.0 atol=1e-6
    @test y1[1].data ≈ y2[1].data            # deterministic
end
