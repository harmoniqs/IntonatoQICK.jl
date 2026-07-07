# Integration tests for the mock calibration→QICK loop. These validate (1) the
# pulse→envelope→rollout translation is faithful (converges as the DAC rate
# rises) and (2) the QickExperiment composes with the Intonato
# `PulseTuningProblem` chassis end-to-end.
#
# NOTE: algorithmic *convergence* of the closed loop through the QICK seam needs a concrete
# tuning strategy, which ships in a separate private package. To keep
# IntonatoQICK public (Intonato-only dep), the chassis test here uses the public
# no-op `IdentityStrategy` and asserts the loop *runs* through the seam.
# Convergence-through-QICK belongs in a private/demo integration test.

@testitem "QICK translation is faithful: readout converges as DAC rate rises" tags=[:slow] begin
    using IntonatoQICK
    using LinearAlgebra
    σx = ComplexF64[0 1; 1 0]; σz = ComplexF64[1 0; 0 -1]
    sys = QuantumSystem(1.0 * σz, [σx], [1.0])
    N = 11
    pulse = LinearSplinePulse(0.2 .* randn(1, N), collect(range(0.0, 5.0, length=N)))
    map = QickChannelMap([QickGenChannel(0, 5e9; i_drive=1)]; n_drives=1)
    model = MeasurementModel(:ψ̃, [populations], [N])

    function readout_at(rate)
        soc = MockQickSoc(sys, ComplexF64[1, 0], ComplexF64[0, 1]; dac_rate=rate)
        qexp = QickExperiment(QickBackend(soc, map, [N]); measurement_model=model)
        run_experiment(qexp, pulse)[1].data
    end
    y_coarse = readout_at(40.0)
    y_fine   = readout_at(160.0)
    y_finer  = readout_at(320.0)
    # Successive refinements get closer — translation is not lossy.
    @test norm(y_finer - y_fine) < norm(y_fine - y_coarse)
    @test norm(y_finer - y_fine) < 1e-2
end

@testitem "QickExperiment composes with PulseTuningProblem (IdentityStrategy)" tags=[:slow] begin
    using IntonatoQICK
    using LinearAlgebra
    σx = ComplexF64[0 1; 1 0]; σz = ComplexF64[1 0; 0 -1]
    sys_nom  = QuantumSystem(1.0 * σz, [σx], [1.0])
    sys_true = QuantumSystem(1.1 * σz, [σx], [1.0])   # model mismatch the "hardware" has
    N = 11; T = 5.0
    times = collect(range(0.0, T, length=N))
    ψ0 = ComplexF64[1, 0]; ψg = ComplexF64[0, 1]

    # Nominal QCP on sys_nom (clears the min_nominal_fidelity gate).
    pulse_init = LinearSplinePulse(0.1 .* randn(1, N), times)
    qcp = SplinePulseProblem(KetTrajectory(sys_nom, pulse_init, ψ0, ψg), N; Q=100.0, R=1e-2)
    solve!(qcp; max_iter=200, verbose=false, print_level=0)

    model = MeasurementModel(:ψ̃, [populations], [N])
    # The QICK "hardware" runs the TRUE system.
    soc = MockQickSoc(sys_true, ψ0, ψg; dac_rate=80.0)
    map = QickChannelMap([QickGenChannel(0, 5e9; i_drive=1)]; n_drives=1)
    qexp = QickExperiment(QickBackend(soc, map, [N]); measurement_model=model)

    ptp = PulseTuningProblem(qcp, qexp, model; R_tr=(u=0.1,), Q_meas=10.0)  # IdentityStrategy
    solve!(ptp; max_iter=3, verbose=false,
           ipopt_options=(max_iter=200, verbose=false, print_level=0))

    @test length(ptp.result.history) ≥ 1                 # the loop ran through the QICK seam
    @test ptp.result.history[1].J_exp > 0                # mismatch produced nonzero error
end
