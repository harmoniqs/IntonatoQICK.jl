# QickBackend — the AbstractHardwareBackend over an AbstractQickSoc. Implements
# the documented hardware interface (upload_pulse! / trigger! / readout /
# sample_rate). The QILC chassis never calls these directly; the QickExperiment
# `run` closure (experiment.jl) does, once per experiment evaluation.

"""
    QickBackend(soc, channel_map, indices; discriminator = b -> real.(b))

Hardware backend bridging a pulse to a QICK SoC. `indices` are the measurement
knot indices (into `1:N`) the readout produces; `discriminator` maps one IQ blob
to a data vector (default: real part, matching `MockQickSoc`'s populations
forward model). `last_raw` holds the most recent raw readout.

Note: under line search the QILC chassis evaluates the experiment several times
per outer iteration, so `last_raw` reflects the *last probe*, not necessarily the
accepted iterate.
"""
mutable struct QickBackend{S<:AbstractQickSoc} <: AbstractHardwareBackend
    soc::S
    channel_map::QickChannelMap
    indices::Vector{Int}
    discriminator::Function
    _program::Union{Nothing,QickProgram}
    last_raw::Any
end

QickBackend(soc::AbstractQickSoc, channel_map::QickChannelMap, indices::Vector{Int};
            discriminator::Function = b -> real.(b)) =
    QickBackend(soc, channel_map, indices, discriminator, nothing, nothing)

function upload_pulse!(b::QickBackend, pulse::AbstractPulse)
    prog = pulse_to_envelopes(pulse, b.channel_map, dac_rate(b.soc), b.indices)
    for (gen_ch, (idata, qdata)) in prog.envelopes
        load_envelope!(b.soc, gen_ch, idata, qdata)
    end
    b._program = prog
    return nothing
end

function trigger!(b::QickBackend)
    b._program === nothing && error("QickBackend.trigger!: upload a pulse first")
    play_program!(b.soc, b._program)
    return nothing
end

# Returns RAW multiplexed IQ (channel-major `raw[ch][k]`) and stashes it in
# `last_raw`; the reduction to measurements is done by the QickExperiment closure
# via `reduce_readout` (readout stays raw — the boundary invariant). `kind` is
# forwarded to the board so it performs the right measurement (`:iq` / `:wigner`
# / `:tomography_1q`); the mock ignores it.
function readout(b::QickBackend; kind::Symbol = :iq)
    raw = acquire(b.soc, b.channel_map.readout_chs; kind = kind)
    b.last_raw = raw
    return raw
end

sample_rate(b::QickBackend) = dac_rate(b.soc)

@testitem "QickBackend upload/trigger/readout against MockQickSoc" begin
    using IntonatoQICK
    using LinearAlgebra
    σx = ComplexF64[0 1; 1 0]; σz = ComplexF64[1 0; 0 -1]
    sys = QuantumSystem(1.0 * σz, [σx], [1.0])
    N = 11
    pulse = LinearSplinePulse(0.1 .* randn(1, N), collect(range(0.0, 5.0, length=N)))
    map = QickChannelMap([QickGenChannel(0, 5e9; i_drive=1)]; n_drives=1)
    soc = MockQickSoc(sys, ComplexF64[1, 0], ComplexF64[0, 1]; dac_rate=20.0)
    b = QickBackend(soc, map, [N])

    @test b.last_raw === nothing
    IntonatoQICK.upload_pulse!(b, pulse)
    IntonatoQICK.trigger!(b)
    raw = IntonatoQICK.readout(b)
    @test b.last_raw === raw
    # channel-major raw[ch][k]: one readout channel, one knot (final).
    @test length(raw) == 1
    @test sum(real.(raw[1][1])) ≈ 1.0 atol=1e-6
    @test IntonatoQICK.sample_rate(b) == 20.0
end
