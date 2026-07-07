# MockQickSoc — a pure-Julia "board" that simulates QICK execution by rolling the
# played pulse through a known `QuantumSystem` (Intonato's own `rollout`, via a
# `SimulatedExperiment`) and emitting synthetic IQ. The forward model is explicit:
#   state → IQ blob = measurement_fn(state) packed as a real-valued complex vector,
# which the trivial discriminator `real` inverts EXACTLY. So a QILC loop run
# through `QickBackend{MockQickSoc}` reproduces the same measurements a direct
# `SimulatedExperiment` would — the loop is validated without a board.
#
# The user passes the "true" (optionally mismatched) system as the mock's system;
# the nominal QCP is solved against the nominal system separately.

"""
    MockQickSoc(system, ψ_init, ψ_goal; measurement_fn=populations, dac_rate=1.0, adc_rate=1.0)

A simulated QICK SoC backed by `system`. `play_program!`/`acquire` reconstruct the
played pulse from the loaded envelopes and roll it out via a `SimulatedExperiment`,
returning IQ blobs `measurement_fn(state)` (packed as complex; invert with `real`).
"""
mutable struct MockQickSoc <: AbstractQickSoc
    system::QuantumSystem
    ψ_init::Vector{ComplexF64}
    ψ_goal::Vector{ComplexF64}
    measurement_fn::Function
    dac_rate::Float64
    adc_rate::Float64
    _env::Dict{Int,Tuple{Vector{Float64},Vector{Float64}}}
    _program::Union{Nothing,QickProgram}
end

function MockQickSoc(system::QuantumSystem,
                     ψ_init::AbstractVector, ψ_goal::AbstractVector;
                     measurement_fn::Function = populations,
                     dac_rate::Real = 1.0, adc_rate::Real = 1.0)
    return MockQickSoc(system, ComplexF64.(ψ_init), ComplexF64.(ψ_goal),
                       measurement_fn, Float64(dac_rate), Float64(adc_rate),
                       Dict{Int,Tuple{Vector{Float64},Vector{Float64}}}(), nothing)
end

dac_rate(soc::MockQickSoc) = soc.dac_rate
adc_rate(soc::MockQickSoc) = soc.adc_rate

load_envelope!(soc::MockQickSoc, gen_ch::Int, idata, qdata) =
    (soc._env[gen_ch] = (Vector{Float64}(idata), Vector{Float64}(qdata)); nothing)

play_program!(soc::MockQickSoc, program::QickProgram) = (soc._program = program; nothing)

function acquire(soc::MockQickSoc, ro_chs; kind::Symbol = :iq)
    prog = soc._program
    prog === nothing && error("MockQickSoc.acquire: no program played")
    # Reconstruct the drive controls from the loaded per-channel envelopes.
    nsamp = length(prog.times)
    ctrls = zeros(Float64, prog.n_drives, nsamp)
    for (gen_ch, i_drive, q_drive) in prog.routing
        idata, qdata = soc._env[gen_ch]
        ctrls[i_drive, :] .= idata
        q_drive === nothing || (ctrls[q_drive, :] .= qdata)
    end
    recon = LinearSplinePulse(ctrls, prog.times)
    # Single simulation path: roll out via a SimulatedExperiment over the system.
    model = MeasurementModel(:ψ̃, [soc.measurement_fn for _ in prog.indices], prog.indices)
    exp = SimulatedExperiment(KetTrajectory(soc.system, recon, soc.ψ_init, soc.ψ_goal), model)
    ms = run_experiment(exp, recon)
    # Forward model state→IQ: pack each measurement's data as a complex blob,
    # one blob per knot index.
    per_knot = [ComplexF64.(m.data) for m in ms]
    # Multiplexed, channel-major shape raw[ch][k]: one per-knot blob list per
    # requested readout channel (`length(raw) == length(ro_chs)`). The mock's
    # forward model is state-based, so every channel sees the same synthetic
    # readout — enough to exercise the multiplexed IQ *shape* without a board.
    # `kind` is accepted for interface parity (the board picks the measurement);
    # the mock's synthetic IQ is kind-agnostic — real Wigner / tomography physics
    # is board-side (expt_service), an accepted mock/real divergence.
    return [copy(per_knot) for _ in ro_chs]
end

@testitem "MockQickSoc round-trips a pulse to valid multiplexed populations IQ" begin
    using IntonatoQICK
    using LinearAlgebra
    σx = ComplexF64[0 1; 1 0]; σz = ComplexF64[1 0; 0 -1]
    sys = QuantumSystem(1.0 * σz, [σx], [1.0])
    N = 11; T = 5.0
    times = collect(range(0.0, T, length=N))
    pulse = LinearSplinePulse(0.1 .* randn(1, N), times)
    # Two multiplexed readout channels.
    map = QickChannelMap([QickGenChannel(0, 5e9; i_drive=1)]; readout_chs=[0, 1], n_drives=1)

    soc = MockQickSoc(sys, ComplexF64[1, 0], ComplexF64[0, 1]; dac_rate=20.0)
    prog = pulse_to_envelopes(pulse, map, dac_rate(soc), [N])
    for (gen_ch, (idata, qdata)) in prog.envelopes
        load_envelope!(soc, gen_ch, idata, qdata)
    end
    play_program!(soc, prog)
    raw = acquire(soc, prog.readout_routing)

    # Channel-major raw[ch][k]: one entry per readout channel.
    @test length(raw) == 2
    @test all(length(raw[ch]) == 1 for ch in 1:2)   # one knot (final) each
    pops = real.(raw[1][1])
    @test length(pops) == 2                          # dim-2 populations
    @test sum(pops) ≈ 1.0 atol=1e-6                  # valid probability vector
    @test all(pops .≥ -1e-9)
    @test real.(raw[2][1]) ≈ pops                    # mock replicates across channels

    # Single-channel round-trip still reduces to one blob list.
    raw1 = acquire(soc, [0])
    @test length(raw1) == 1 && length(raw1[1]) == 1
end
