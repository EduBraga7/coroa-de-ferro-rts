"""
Estúdio procedural de síntese física e foley para os efeitos sonoros (SFX)
de 'Coroa de Ferro: Crônicas da Fronteira'.

Gera 51 arquivos WAV PCM 16-bit Estéreo a 44100 Hz em assets/audio/sfx/,
usando modelagem modal de metais, síntese Karplus-Strong para cordas/madeira,
ressonadores de formantes para trompas/metais medievais e reverb estéreo de ambiente.
"""

import math
import os
import wave
import numpy as np


SR = 44100
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
OUT_DIR = os.path.join(PROJECT_DIR, "assets", "audio", "sfx")
os.makedirs(OUT_DIR, exist_ok=True)


# ==============================================================================
# UTILITÁRIOS DE DSP E FILTRAGEM ESPECTRAL (NUMPY)
# ==============================================================================

def _to_stereo(x):
    arr = np.asarray(x, dtype=np.float64)
    if arr.ndim == 1:
        return np.stack([arr, arr], axis=1)
    return arr


def _pad_to(arr, n_samples):
    st = _to_stereo(arr)
    if st.shape[0] >= n_samples:
        return st[:n_samples]
    out = np.zeros((n_samples, 2), dtype=np.float64)
    out[:st.shape[0]] = st
    return out


def mix_at(canvas, clip, offset_s=0.0, gain=1.0, pan=0.0):
    """Mixa clip estéreo ou mono no canvas em offset_s com panorâmica (-1..+1)."""
    st = _to_stereo(clip)
    start = max(0, int(round(offset_s * SR)))
    if start >= canvas.shape[0] or st.shape[0] == 0:
        return canvas
    avail = min(st.shape[0], canvas.shape[0] - start)
    pan_clamped = max(-1.0, min(1.0, pan))
    gl = gain * math.cos((pan_clamped + 1.0) * math.pi * 0.25) * math.sqrt(2.0)
    gr = gain * math.sin((pan_clamped + 1.0) * math.pi * 0.25) * math.sqrt(2.0)
    canvas[start:start + avail, 0] += st[:avail, 0] * gl
    canvas[start:start + avail, 1] += st[:avail, 1] * gr
    return canvas


def exp_env(n_samples, attack_s=0.003, decay_s=0.15):
    t = np.arange(n_samples, dtype=np.float64) / SR
    att = np.clip(t / max(1e-4, attack_s), 0.0, 1.0)
    dec = np.exp(-t / max(1e-4, decay_s))
    return att * dec


def adsr_env(n_samples, attack_s=0.02, decay_s=0.10, sustain=0.75, release_s=0.15):
    env = np.zeros(n_samples, dtype=np.float64)
    a_n = max(1, min(n_samples, int(attack_s * SR)))
    d_n = max(0, min(n_samples - a_n, int(decay_s * SR)))
    r_n = max(1, min(n_samples, int(release_s * SR)))
    s_end = max(a_n + d_n, n_samples - r_n)

    env[:a_n] = np.linspace(0.0, 1.0, a_n, endpoint=False)
    if d_n > 0:
        env[a_n:a_n + d_n] = np.linspace(1.0, sustain, d_n, endpoint=False)
    if s_end > a_n + d_n:
        env[a_n + d_n:s_end] = sustain
    rem = n_samples - s_end
    if rem > 0:
        start_val = env[s_end - 1] if s_end > 0 else sustain
        env[s_end:] = np.linspace(start_val, 0.0, rem) ** 1.4
    return env


def noise_stereo(n_samples, seed=1, stereo_decorr=True):
    rng = np.random.default_rng(seed)
    n0 = rng.standard_normal(n_samples)
    if stereo_decorr:
        n1 = rng.standard_normal(n_samples)
    else:
        n1 = n0.copy()
    return np.stack([n0, n1], axis=1)


def _apply_freq_mask(sig, mask_fn):
    st = _to_stereo(sig)
    n = st.shape[0]
    n_fft = 1 << (n - 1).bit_length()
    if n_fft < 256:
        n_fft = 256
    freqs = np.fft.rfftfreq(n_fft, 1.0 / SR)
    mask = mask_fn(freqs)
    out = np.zeros_like(st)
    for ch in range(2):
        spec = np.fft.rfft(st[:, ch], n=n_fft)
        filt = np.fft.irfft(spec * mask, n=n_fft)
        out[:, ch] = filt[:n]
    return out


def lowpass_fft(sig, cutoff_hz, order=2):
    c = max(20.0, float(cutoff_hz))
    return _apply_freq_mask(sig, lambda f: 1.0 / np.sqrt(1.0 + (f / c) ** (2 * order)))


def highpass_fft(sig, cutoff_hz, order=2):
    c = max(10.0, float(cutoff_hz))
    return _apply_freq_mask(sig, lambda f: 1.0 / np.sqrt(1.0 + (c / np.maximum(f, 1.0)) ** (2 * order)) * (f > 5.0))


def bandpass_fft(sig, low_hz, high_hz, order=2):
    lo = max(15.0, float(low_hz))
    hi = max(lo + 20.0, float(high_hz))
    def mask(f):
        hp = 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1.0)) ** (2 * order))
        lp = 1.0 / np.sqrt(1.0 + (f / hi) ** (2 * order))
        return hp * lp * (f > 5.0)
    return _apply_freq_mask(sig, mask)


def peaking_eq_fft(sig, center_hz, gain_db, q=1.8):
    fc = max(20.0, float(center_hz))
    g = 10.0 ** (gain_db / 20.0)
    def mask(f):
        rel = (f - fc) / max(10.0, fc / q)
        bump = np.exp(-0.5 * rel * rel)
        return 1.0 + (g - 1.0) * bump
    return _apply_freq_mask(sig, mask)


def svf_sweep(sig, f_start, f_end, q=1.8, mode="bandpass"):
    """Filtro State-Variable variante no tempo (2 polos) para whooshes Doppler realistas."""
    st = _to_stereo(sig)
    n = st.shape[0]
    out = np.zeros_like(st)
    f_curve = np.geomspace(max(30.0, f_start), max(30.0, f_end), n)
    damp = 1.0 / max(0.35, q)
    for ch in range(2):
        low = 0.0
        band = 0.0
        inp = st[:, ch]
        dst = out[:, ch]
        for i in range(n):
            f_coef = min(1.85, 2.0 * math.sin(math.pi * min(f_curve[i], SR * 0.42) / SR))
            low += f_coef * band
            high = inp[i] - low - damp * band
            band += f_coef * high
            if mode == "bandpass":
                dst[i] = band
            elif mode == "lowpass":
                dst[i] = low
            else:
                dst[i] = high
    return out


# ==============================================================================
# SÍNTESE FÍSICA: METAIS MODAIS, KARPLUS-STRONG, MADEIRA, METAIS/TROMPAS
# ==============================================================================

def modal_strike(base_freq, duration_s, decay_s=0.22,
                 ratios=(1.0, 1.58, 2.31, 3.17, 4.42, 5.89, 7.64),
                 amps=(1.0, 0.72, 0.56, 0.40, 0.28, 0.18, 0.10),
                 spread=0.006, impact_noise_ms=4.5, impact_band=(1400.0, 6800.0),
                 seed=1):
    """Banco de modos inarmônicos para aço forjado, moedas, sinos e armaduras."""
    n = max(64, int(duration_s * SR))
    t = np.arange(n, dtype=np.float64) / SR
    rng = np.random.default_rng(seed)

    out_l = np.zeros(n, dtype=np.float64)
    out_r = np.zeros(n, dtype=np.float64)

    for idx, (r, a) in enumerate(zip(ratios, amps)):
        f = base_freq * r
        if f > SR * 0.45:
            continue
        tau = decay_s / (r ** 1.32)
        env = np.exp(-t / max(0.006, tau))
        ph_l = rng.uniform(0.0, 2.0 * math.pi)
        ph_r = ph_l + rng.uniform(-0.5, 0.5)
        det = 1.0 + ((-1.0 if idx % 2 else 1.0) * spread)
        out_l += a * env * np.sin(2.0 * math.pi * f * t + ph_l)
        out_r += a * env * np.sin(2.0 * math.pi * f * det * t + ph_r)

    stereo = np.stack([out_l, out_r], axis=1)

    if impact_noise_ms > 0.0:
        imp_n = max(16, int((impact_noise_ms * 0.001) * SR))
        burst = noise_stereo(n, seed=seed + 11)
        burst *= np.exp(-t / (impact_noise_ms * 0.001))[:, None]
        burst = bandpass_fft(burst, impact_band[0], impact_band[1], order=2)
        stereo += burst * 1.15

    att = np.clip(t / 0.0012, 0.0, 1.0)
    return stereo * att[:, None]


def karplus_strong(freq_hz, duration_s, damping=0.992, brightness=0.65, seed=7):
    """Linha de atraso realimentada Karplus-Strong para corda de arco e tensão."""
    n = max(128, int(duration_s * SR))
    delay_len = max(8, int(round(SR / max(30.0, freq_hz))))
    rng = np.random.default_rng(seed)
    exc = rng.uniform(-1.0, 1.0, delay_len)
    # Suaviza excitação inicial para evitar som áspero de 8 bits
    exc = np.convolve(exc, [0.25, 0.5, 0.25], mode="same")

    buf = exc.copy()
    out = np.zeros(n, dtype=np.float64)
    prev = 0.0
    for i in range(n):
        idx = i % delay_len
        cur = buf[idx]
        out[i] = cur
        lp = brightness * cur + (1.0 - brightness) * prev
        buf[idx] = lp * damping
        prev = cur

    # Ligeira diferença de fase estéreo via atraso de subamostra
    out_r = np.roll(out, 3)
    out_r[:3] = 0.0
    return np.stack([out, out_r], axis=1)


def wood_body(base_freq=145.0, pitch_drop=0.62, duration_s=0.28, decay_s=0.036,
              crack_band=(1200.0, 4800.0), crack_ms=14.0, seed=3):
    """Impacto ressonante seco de madeira real (sem som de 'boop' tonal)."""
    n = max(64, int(duration_s * SR))
    t = np.arange(n, dtype=np.float64) / SR
    # Queda ultra-rápida da membrana/madeira (6ms) + decaimento curto natural
    f_t = base_freq * (pitch_drop + (1.0 - pitch_drop) * np.exp(-t / 0.007))
    ph = np.cumsum(2.0 * math.pi * f_t / SR)
    body_tau = min(decay_s, 0.042)
    body = (
        1.00 * np.sin(ph) * np.exp(-t / body_tau)
        + 0.62 * np.sin(ph * 2.14 + 0.5) * np.exp(-t / (body_tau * 0.55))
        + 0.35 * np.sin(ph * 3.42 + 1.2) * np.exp(-t / (body_tau * 0.32))
    )
    body_st = np.stack([body, body * 0.98], axis=1)

    # Ressonância de corpo de madeira excitada por impulso ruidoso (formante lenhoso)
    wood_noise = noise_stereo(n, seed=seed + 19)
    wood_noise *= np.exp(-t / max(0.008, decay_s * 0.85))[:, None]
    wood_res = bandpass_fft(wood_noise, max(120.0, base_freq * 1.4), min(2800.0, base_freq * 6.5), order=2)

    # Estalo agudo de fibra / superfície no contato
    crack = noise_stereo(n, seed=seed + 23)
    crack *= np.exp(-t / (crack_ms * 0.001))[:, None]
    crack = bandpass_fft(crack, crack_band[0], crack_band[1], order=2)

    att = np.clip(t / 0.0010, 0.0, 1.0)
    return (body_st * 0.62 + wood_res * 1.35 + crack * 1.15) * att[:, None]


def brass_voice(freq_start, freq_end, duration_s, attack_s=0.07, release_s=0.22,
                bright=1.0, vibrato_hz=4.5, vibrato_cents=10.0, flutter=0.0, seed=5):
    """
    Trompa / metal medieval expressivo com entrada por embocadura (pitch scoop),
    brilho dinâmico acompanhando o sopro, ensemble de 3 vozes e formantes acústicos.
    """
    n = max(128, int(duration_s * SR))
    t = np.arange(n, dtype=np.float64) / SR
    glide_tau = min(0.065, duration_s * 0.22)
    f_base = freq_end + (freq_start - freq_end) * np.exp(-t / max(0.008, glide_tau))
    vib_mask = np.clip((t - attack_s) / 0.24, 0.0, 1.0)
    vib_ratio = 2.0 ** ((vibrato_cents / 1200.0) * vib_mask * np.sin(2.0 * math.pi * vibrato_hz * t))
    f_t = f_base * vib_ratio

    env = adsr_env(n, attack_s=attack_s, decay_s=0.14, sustain=0.76, release_s=release_s)
    # Brilho sobe gradualmente com a pressão do ar (evita som de teclado estático)
    swell = np.clip(t / max(0.025, attack_s * 1.8), 0.0, 1.0) ** 0.75
    bright_env = (0.38 + 0.62 * swell * np.exp(-t / max(0.35, duration_s * 0.85))) * bright

    out_l = np.zeros(n, dtype=np.float64)
    out_r = np.zeros(n, dtype=np.float64)
    detunes = [(-8.0, 0.70, 0.30), (0.0, 0.50, 0.50), (9.0, 0.30, 0.70)]
    for cents, pan_l, pan_r in detunes:
        mult = 2.0 ** (cents / 1200.0)
        ph = np.cumsum(2.0 * math.pi * (f_t * mult) / SR)
        sig = np.zeros(n, dtype=np.float64)
        for h in range(1, 12):
            if np.max(f_t) * h > SR * 0.42:
                break
            # Metais têm pico espectral em 2o-4o harmônicos e decaimento suave nos agudos
            formant_boost = 1.15 if h in (2, 3, 4) else 1.0
            w = formant_boost * (1.0 / (h ** 1.18)) * (np.clip(bright_env, 0.15, 1.35) ** ((h - 1) * 0.30))
            sig += w * np.sin(ph * h)
        sig = np.tanh(sig * 1.05)
        out_l += sig * pan_l
        out_r += sig * pan_r

    stereo = np.stack([out_l, out_r], axis=1)
    if flutter > 0.0:
        rng = np.random.default_rng(seed + 41)
        fl = 1.0 + flutter * np.convolve(rng.standard_normal(n), np.ones(180) / 180.0, mode="same")
        stereo *= fl[:, None]

    # Sopro de ar realista na embocadura inicial + corpo de ar contínuo muito sutil
    breath = noise_stereo(n, seed=seed + 31)
    breath *= (exp_env(n, attack_s=0.012, decay_s=0.075) * 0.85 + env * 0.12)[:, None]
    breath = bandpass_fft(breath, 450.0, 2200.0, order=2)
    stereo = stereo * env[:, None] + breath * 0.24

    # Formantes naturais de campana de trompa de metal
    stereo = lowpass_fft(stereo, 1850.0 + 1150.0 * bright, order=2)
    stereo = peaking_eq_fft(stereo, 460.0, +4.0, q=1.4)
    stereo = peaking_eq_fft(stereo, 1080.0, +3.0, q=1.7)
    return stereo


def stereo_reverb(sig, wet=0.22, rt60_s=0.55, seed=99):
    """Reverb estéreo leve com reflexões primárias assimétricas e cauda difusa amortecida."""
    st = _to_stereo(sig)
    if wet <= 0.0:
        return st
    tail_n = int(rt60_s * SR)
    total_n = st.shape[0] + tail_n
    padded = _pad_to(st, total_n)

    # Reflexões primárias em milissegundos distintos L/R
    er = np.zeros_like(padded)
    taps_l = [(0.011, 0.52), (0.019, 0.38), (0.031, 0.27), (0.047, 0.18)]
    taps_r = [(0.013, 0.50), (0.023, 0.36), (0.037, 0.25), (0.053, 0.16)]
    for d_s, g in taps_l:
        d = int(d_s * SR)
        er[d:, 0] += padded[:total_n - d, 0] * g
    for d_s, g in taps_r:
        d = int(d_s * SR)
        er[d:, 1] += padded[:total_n - d, 1] * g

    # Cauda difusa amortecida por convolução rápida via FFT
    rng = np.random.default_rng(seed)
    ir_n = max(256, tail_n)
    t_ir = np.arange(ir_n, dtype=np.float64) / SR
    decay_ir = np.exp(-6.9 * t_ir / max(0.08, rt60_s))
    ir = np.stack([rng.standard_normal(ir_n), rng.standard_normal(ir_n)], axis=1) * decay_ir[:, None]
    ir = lowpass_fft(ir, 2800.0, order=2)
    ir /= (np.sqrt(np.sum(ir ** 2, axis=0)) + 1e-8)

    n_fft = 1 << (total_n + ir_n - 2).bit_length()
    tail = np.zeros_like(padded)
    for ch in range(2):
        conv = np.fft.irfft(np.fft.rfft(padded[:, ch], n=n_fft) * np.fft.rfft(ir[:, ch], n=n_fft), n=n_fft)
        tail[:, ch] = conv[:total_n]

    wet_sig = lowpass_fft(er * 0.55 + tail * 0.72, 4200.0, order=1)
    return padded * (1.0 - wet * 0.35) + wet_sig * wet


def master_and_save(filepath, raw_sig, target_peak_db=-2.0, wet=0.18, rt60_s=0.45):
    """Aplica espaço estéreo, HPF anti-DC, saturação suave, fade-out limpo e salva WAV 44.1kHz 16-bit."""
    sig = stereo_reverb(raw_sig, wet=wet, rt60_s=rt60_s)
    sig = highpass_fft(sig, 26.0, order=2)

    # Trim silêncio excessivo no final preservando cauda limpa
    energy = np.max(np.abs(sig), axis=1)
    peak_all = float(np.max(energy))
    if peak_all > 1e-8:
        above = np.where(energy > peak_all * 0.0025)[0]
        if len(above) > 0:
            end_idx = min(sig.shape[0], int(above[-1]) + int(0.04 * SR))
            sig = sig[:max(int(0.055 * SR), end_idx)]

    # Pré-normalização suave antes de saturação analógica para evitar compressão excessiva em fanfarras
    pre_peak = float(np.max(np.abs(sig)))
    if pre_peak > 1.25:
        sig = sig * (1.25 / pre_peak)
    sig = np.tanh(sig * 0.85)
    sig = highpass_fft(sig, 28.0, order=2)
    sig = sig - np.mean(sig, axis=0, keepdims=True)
    peak = float(np.max(np.abs(sig)))
    target_lin = 10.0 ** (target_peak_db / 20.0)
    if peak > 1e-9:
        sig = sig * (target_lin / peak)

    # De-click suave nas pontas e remoção residual de DC
    n = sig.shape[0]
    fi = min(n // 4, int(0.0025 * SR))
    fo = min(n // 3, int(0.020 * SR))
    if fi > 1:
        sig[:fi] *= np.linspace(0.0, 1.0, fi)[:, None]
    if fo > 1:
        sig[-fo:] *= np.linspace(1.0, 0.0, fo)[:, None]
    sig = sig - np.mean(sig, axis=0, keepdims=True)
    if fi > 1:
        sig[:fi] *= np.linspace(0.0, 1.0, fi)[:, None]
    if fo > 1:
        sig[-fo:] *= np.linspace(1.0, 0.0, fo)[:, None]

    sig = np.clip(sig, -0.999, 0.999)
    pcm = (sig * 32767.0).astype(np.int16)
    with wave.open(filepath, "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(pcm.tobytes())

    rms = float(np.sqrt(np.mean(sig ** 2)))
    peak_db = 20.0 * math.log10(max(1e-9, float(np.max(np.abs(sig)))))
    rms_db = 20.0 * math.log10(max(1e-9, rms))
    return {
        "file": os.path.basename(filepath),
        "dur_s": n / float(SR),
        "peak_db": peak_db,
        "rms_db": rms_db,
        "dc": float(np.max(np.abs(np.mean(sig, axis=0)))),
        "edge": float(max(np.max(np.abs(sig[0])), np.max(np.abs(sig[-1])))),
    }


# ==============================================================================
# RECEITAS DOS 51 EFEITOS SONOROS MEDIEVAIS
# ==============================================================================

def sfx_sword_hit(v):
    c = np.zeros((int(0.36 * SR), 2))
    # 1. Corte rápido da lâmina no ar
    swish = svf_sweep(noise_stereo(int(0.11 * SR), seed=100 + v), 3600.0, 900.0, q=1.2)
    swish *= exp_env(swish.shape[0], 0.005, 0.042)[:, None]
    mix_at(c, swish, 0.0, gain=0.45)
    # 2. Choque metálico seco e agressivo (aço contra placa/escudo, amortecido rápido)
    pitch = 920.0 * (0.94 + v * 0.07)
    clang1 = modal_strike(pitch, 0.22, decay_s=0.075,
                          ratios=(1.0, 1.44, 1.88, 2.38, 3.05, 4.12),
                          amps=(0.75, 0.88, 0.72, 0.54, 0.34, 0.18),
                          impact_noise_ms=14.0, impact_band=(1200, 6500), seed=110 + v)
    clang2 = modal_strike(pitch * 1.37, 0.18, decay_s=0.055,
                          ratios=(1.0, 1.49, 2.18, 3.10),
                          amps=(0.55, 0.45, 0.32, 0.18),
                          impact_noise_ms=9.0, impact_band=(1800, 7200), seed=120 + v)
    crunch = bandpass_fft(noise_stereo(int(0.08 * SR), seed=125 + v), 900.0, 4800.0)
    crunch *= exp_env(crunch.shape[0], 0.001, 0.024)[:, None]
    mix_at(c, clang1, 0.025, gain=0.72, pan=-0.12)
    mix_at(c, clang2, 0.044, gain=0.52, pan=0.14)
    mix_at(c, crunch, 0.025, gain=0.88)
    # 3. Impacto pesado no corpo/escudo
    punch = wood_body(122.0 + v * 8.0, 0.50, 0.14, decay_s=0.036, crack_band=(450, 1900), seed=130 + v)
    mix_at(c, punch, 0.024, gain=0.95)
    return c, -1.8, 0.16, 0.36


def sfx_halberd_hit(v):
    c = np.zeros((int(0.46 * SR), 2))
    # 1. Zumbido pesado da alabarda cortando o ar
    swish = svf_sweep(noise_stereo(int(0.16 * SR), seed=200 + v), 2200.0, 440.0, q=1.4)
    swish *= exp_env(swish.shape[0], 0.008, 0.062)[:, None]
    mix_at(c, swish, 0.0, gain=0.55)
    # 2. Impacto pesado aço-ferro amortecido (crunch de armadura, sem "sino")
    pitch = 560.0 * (0.95 + v * 0.06)
    clang = modal_strike(pitch, 0.28, decay_s=0.095,
                         ratios=(1.0, 1.41, 1.92, 2.55, 3.35, 4.45),
                         amps=(0.78, 0.85, 0.68, 0.48, 0.30, 0.16),
                         impact_noise_ms=18.0, impact_band=(800, 5600), seed=210 + v)
    crunch = bandpass_fft(noise_stereo(int(0.11 * SR), seed=215 + v), 650.0, 4200.0)
    crunch *= exp_env(crunch.shape[0], 0.001, 0.032)[:, None]
    mix_at(c, clang, 0.032, gain=0.72)
    mix_at(c, crunch, 0.032, gain=0.95)
    # 3. Sub-impacto maciço de golpe de Paladino
    punch = wood_body(88.0 + v * 6.0, 0.45, 0.20, decay_s=0.044, crack_band=(300, 1500), seed=220 + v)
    mix_at(c, punch, 0.030, gain=1.22)
    return c, -1.5, 0.18, 0.42


def sfx_worker_hit(v):
    c = np.zeros((int(0.26 * SR), 2))
    thump = wood_body(165.0 + v * 12.0, 0.55, 0.20, decay_s=0.055, crack_band=(900, 3800), seed=300 + v)
    tap = modal_strike(980.0 + v * 70.0, 0.14, decay_s=0.06,
                       ratios=(1.0, 1.72, 2.65), amps=(0.45, 0.30, 0.18),
                       impact_noise_ms=3.0, seed=310 + v)
    mix_at(c, thump, 0.0, gain=0.95)
    mix_at(c, tap, 0.004, gain=0.38)
    return c, -2.5, 0.14, 0.32


def sfx_arrow_shoot(v):
    c = np.zeros((int(0.30 * SR), 2))
    # 1. Estalo tenso da corda do arco (Karplus-Strong)
    twang = karplus_strong(148.0 + v * 9.0, 0.18, damping=0.986, brightness=0.58, seed=400 + v)
    twang *= exp_env(twang.shape[0], 0.002, 0.055)[:, None]
    twang = bandpass_fft(twang, 120.0, 2400.0, order=2)
    mix_at(c, twang, 0.0, gain=0.72)
    # 2. Silvo aerodinâmico da flecha com penas (varredura descendente)
    whoosh = svf_sweep(noise_stereo(int(0.18 * SR), seed=410 + v), 4800.0, 720.0, q=1.6)
    whoosh *= exp_env(whoosh.shape[0], 0.004, 0.062)[:, None]
    mix_at(c, whoosh, 0.008, gain=0.88)
    # 3. Toque seco da madeira do arco
    snap = wood_body(320.0, 0.70, 0.09, decay_s=0.025, crack_band=(1800, 5200), crack_ms=6.0, seed=420 + v)
    mix_at(c, snap, 0.0, gain=0.45)
    return c, -2.2, 0.16, 0.38


def sfx_arrow_hit(v):
    c = np.zeros((int(0.22 * SR), 2))
    # Impacto seco da ponta + vibração da haste de madeira
    thud = wood_body(215.0 + v * 16.0, 0.52, 0.14, decay_s=0.038, crack_band=(1600, 6200), crack_ms=8.0, seed=500 + v)
    shaft = karplus_strong(380.0 + v * 25.0, 0.15, damping=0.978, brightness=0.50, seed=510 + v)
    shaft *= exp_env(shaft.shape[0], 0.001, 0.045)[:, None]
    mix_at(c, thud, 0.0, gain=1.0)
    mix_at(c, shaft, 0.003, gain=0.34)
    return c, -2.0, 0.14, 0.34


def sfx_unit_death(v):
    c = np.zeros((int(0.60 * SR), 2))
    # 1. Queda do corpo no solo
    thud = wood_body(86.0 + v * 6.0, 0.45, 0.24, decay_s=0.08, crack_band=(250, 1200), crack_ms=18.0, seed=600 + v)
    mix_at(c, thud, 0.02, gain=1.05)
    # 2. Tilintar escalonado de placas e arma caindo na terra
    for j, off in enumerate((0.06, 0.16, 0.28)):
        cl = modal_strike(780.0 + j * 190.0 + v * 45.0, 0.22, decay_s=0.08,
                          ratios=(1.0, 1.67, 2.52, 3.85), amps=(0.65, 0.50, 0.35, 0.20),
                          impact_noise_ms=4.0, seed=610 + v * 10 + j)
        mix_at(c, cl, off, gain=0.52 * (0.82 ** j), pan=(-0.3 if j % 2 == 0 else 0.3))
    # 3. Poeira/cascalho leve
    gravel = bandpass_fft(noise_stereo(int(0.28 * SR), seed=630 + v), 500.0, 2600.0)
    gravel *= exp_env(gravel.shape[0], 0.02, 0.10)[:, None]
    mix_at(c, gravel, 0.10, gain=0.28)
    return c, -2.0, 0.22, 0.48


def sfx_mine_gold(v):
    c = np.zeros((int(0.36 * SR), 2))
    # 1. Picareta de aço batendo na rocha mineral (*clink/clang*)
    pitch = 1480.0 * (0.94 + v * 0.06)
    clink = modal_strike(pitch, 0.30, decay_s=0.14,
                         ratios=(1.0, 1.59, 2.41, 3.48, 4.90),
                         amps=(0.90, 0.78, 0.56, 0.36, 0.20),
                         impact_noise_ms=4.5, impact_band=(2200, 8200), seed=700 + v)
    mix_at(c, clink, 0.0, gain=0.85)
    # 2. Impacto duro na pedra + estilhaços de rocha
    rock = wood_body(245.0 + v * 15.0, 0.65, 0.14, decay_s=0.032, crack_band=(1400, 5600), crack_ms=10.0, seed=710 + v)
    mix_at(c, rock, 0.0, gain=0.68)
    pebbles = bandpass_fft(noise_stereo(int(0.18 * SR), seed=720 + v), 1800.0, 6200.0)
    pebbles *= exp_env(pebbles.shape[0], 0.015, 0.055)[:, None]
    mix_at(c, pebbles, 0.045, gain=0.22)
    return c, -2.5, 0.18, 0.40


def sfx_chop_wood(v):
    c = np.zeros((int(0.30 * SR), 2))
    # 1. Golpe seco e lenhoso de machado no tronco de carvalho (*thock!*)
    oak = wood_body(128.0 + v * 9.0, 0.62, 0.22, decay_s=0.032, crack_band=(900, 3800), crack_ms=13.0, seed=800 + v)
    mix_at(c, oak, 0.0, gain=1.12)
    # 2. Estalo de lasca de madeira logo após a lâmina entrar
    splinter = bandpass_fft(noise_stereo(int(0.08 * SR), seed=815 + v), 1800.0, 5800.0)
    splinter *= exp_env(splinter.shape[0], 0.002, 0.018)[:, None]
    mix_at(c, splinter, 0.010, gain=0.65, pan=0.14 if v % 2 else -0.14)
    # 3. Corte rápido da lâmina
    bite = svf_sweep(noise_stereo(int(0.055 * SR), seed=810 + v), 3200.0, 950.0, q=1.3)
    bite *= exp_env(bite.shape[0], 0.001, 0.016)[:, None]
    mix_at(c, bite, 0.0, gain=0.52)
    return c, -2.5, 0.14, 0.30


def sfx_deposit_gold():
    c = np.zeros((int(0.54 * SR), 2))
    # Cascata de 5 moedas de ouro reais tilintando no tesouro
    coins = [(0.00, 2950.0, -0.22), (0.058, 3380.0, 0.18), (0.115, 2720.0, -0.10),
             (0.172, 3690.0, 0.24), (0.235, 3180.0, 0.0)]
    for i, (off, f, pan) in enumerate(coins):
        coin = modal_strike(f, 0.24, decay_s=0.10,
                            ratios=(1.0, 1.56, 2.28, 3.19, 4.30),
                            amps=(0.85, 0.68, 0.48, 0.30, 0.15),
                            impact_noise_ms=2.2, impact_band=(3000, 9000), seed=900 + i)
        mix_at(c, coin, off, gain=0.58 * (0.94 ** i), pan=pan)
    # Bolsa de couro pousando
    pouch = wood_body(165.0, 0.72, 0.12, decay_s=0.032, crack_band=(400, 1400), seed=920)
    mix_at(c, pouch, 0.0, gain=0.35)
    return c, -2.8, 0.20, 0.42


def sfx_deposit_wood():
    c = np.zeros((int(0.44 * SR), 2))
    # 3 toras pesadas empilhando no depósito
    logs = [(0.00, 148.0, -0.18), (0.088, 128.0, 0.18), (0.178, 114.0, -0.05)]
    for i, (off, f, pan) in enumerate(logs):
        thud = wood_body(f, 0.65, 0.20, decay_s=0.055, crack_band=(700, 2800), crack_ms=10.0, seed=950 + i)
        mix_at(c, thud, off, gain=0.82 * (0.90 ** i), pan=pan)
    return c, -2.5, 0.16, 0.36


def sfx_build_hammer(v):
    c = np.zeros((int(0.30 * SR), 2))
    # Martelo de ferro em viga de carvalho + prego metálico
    timber = wood_body(172.0 + v * 10.0, 0.60, 0.22, decay_s=0.058, crack_band=(900, 3600), crack_ms=11.0, seed=1000 + v)
    nail = modal_strike(1380.0 + v * 85.0, 0.16, decay_s=0.065,
                        ratios=(1.0, 1.63, 2.55, 3.72), amps=(0.62, 0.45, 0.28, 0.15),
                        impact_noise_ms=2.5, seed=1010 + v)
    mix_at(c, timber, 0.0, gain=0.90)
    mix_at(c, nail, 0.002, gain=0.45)
    return c, -2.6, 0.18, 0.38


def sfx_build_place():
    c = np.zeros((int(0.44 * SR), 2))
    # Assentamento de fundação de pedra + vigas de madeira
    base_thud = wood_body(88.0, 0.48, 0.28, decay_s=0.095, crack_band=(300, 1500), crack_ms=22.0, seed=1100)
    beam = wood_body(146.0, 0.62, 0.22, decay_s=0.065, crack_band=(800, 3200), crack_ms=14.0, seed=1105)
    stone = bandpass_fft(noise_stereo(int(0.24 * SR), seed=1110), 220.0, 1400.0)
    stone *= exp_env(stone.shape[0], 0.01, 0.09)[:, None]
    mix_at(c, base_thud, 0.0, gain=0.95)
    mix_at(c, beam, 0.082, gain=0.80, pan=0.12)
    mix_at(c, stone, 0.03, gain=0.42)
    return c, -2.2, 0.18, 0.42


def sfx_build_complete():
    c = np.zeros((int(0.95 * SR), 2))
    # Trava firme de madeira + acorde medieval luminoso D4 - A4 - D5 (sino + trompa suave)
    latch = wood_body(185.0, 0.65, 0.18, decay_s=0.05, crack_band=(900, 3200), seed=1200)
    mix_at(c, latch, 0.0, gain=0.52)
    notes = [(0.02, 293.66, 0.62), (0.14, 440.00, 0.56), (0.27, 587.33, 0.68)]
    for i, (off, f, dur) in enumerate(notes):
        bell = modal_strike(f, dur, decay_s=0.30,
                            ratios=(1.0, 2.0, 2.98, 4.02, 5.40),
                            amps=(0.85, 0.46, 0.22, 0.12, 0.05),
                            impact_noise_ms=2.0, impact_band=(1200, 4200), seed=1210 + i)
        horn = brass_voice(f * 0.99, f, dur, attack_s=0.04, release_s=0.22, bright=0.68, seed=1220 + i)
        mix_at(c, bell, off, gain=0.58, pan=-0.12 + i * 0.12)
        mix_at(c, horn, off, gain=0.45, pan=0.08 - i * 0.08)
    return c, -2.0, 0.30, 0.72


def sfx_building_collapse():
    c = np.zeros((int(1.48 * SR), 2))
    # 1. Estalo inicial de madeira partindo
    snap = wood_body(175.0, 0.55, 0.26, decay_s=0.06, crack_band=(1200, 5200), crack_ms=22.0, seed=1300)
    mix_at(c, snap, 0.0, gain=0.95)
    # 2. Desabamento grave de alvenaria e estrondo
    boom = wood_body(52.0, 0.38, 0.65, decay_s=0.26, crack_band=(120, 750), crack_ms=85.0, seed=1305)
    rumble = lowpass_fft(noise_stereo(int(1.10 * SR), seed=1310), 260.0, order=2)
    rumble *= exp_env(rumble.shape[0], 0.04, 0.38)[:, None]
    mix_at(c, boom, 0.06, gain=1.25)
    mix_at(c, rumble, 0.08, gain=0.95)
    # 3. Cascata de pedras e escombros espalhando
    rng = np.random.default_rng(1320)
    for k in range(22):
        off = 0.12 + (k / 22.0) * 0.95 + rng.uniform(-0.02, 0.03)
        f_deb = rng.uniform(95.0, 310.0)
        deb = wood_body(f_deb, 0.60, 0.16, decay_s=0.045, crack_band=(600, 3200), crack_ms=10.0, seed=1330 + k)
        amp = 0.52 * ((1.0 - k / 24.0) ** 1.1)
        mix_at(c, deb, max(0.0, off), gain=amp, pan=rng.uniform(-0.75, 0.75))
    return c, -1.2, 0.28, 0.75


def sfx_select_worker():
    c = np.zeros((int(0.16 * SR), 2))
    tap = wood_body(240.0, 0.72, 0.14, decay_s=0.038, crack_band=(1000, 3400), crack_ms=7.0, seed=1400)
    mix_at(c, tap, 0.0, gain=0.88)
    return c, -3.0, 0.10, 0.22


def sfx_select_soldier():
    c = np.zeros((int(0.28 * SR), 2))
    # Saque metálico de espada (*shing!*)
    scrape = svf_sweep(noise_stereo(int(0.18 * SR), seed=1500), 1700.0, 5600.0, q=2.2)
    scrape *= exp_env(scrape.shape[0], 0.015, 0.065)[:, None]
    shing = modal_strike(2180.0, 0.25, decay_s=0.11,
                         ratios=(1.0, 1.48, 2.15, 3.05),
                         amps=(0.75, 0.62, 0.42, 0.22),
                         impact_noise_ms=2.5, impact_band=(2600, 7500), seed=1510)
    mix_at(c, scrape, 0.0, gain=0.72)
    mix_at(c, shing, 0.025, gain=0.64)
    return c, -2.8, 0.16, 0.35


def sfx_select_archer():
    c = np.zeros((int(0.20 * SR), 2))
    # Tensão leve da corda + roçar das penas
    pluck = karplus_strong(210.0, 0.15, damping=0.980, brightness=0.52, seed=1600)
    pluck *= exp_env(pluck.shape[0], 0.004, 0.045)[:, None]
    fletch = bandpass_fft(noise_stereo(int(0.11 * SR), seed=1610), 2800.0, 7200.0)
    fletch *= exp_env(fletch.shape[0], 0.012, 0.035)[:, None]
    mix_at(c, pluck, 0.0, gain=0.72)
    mix_at(c, fletch, 0.015, gain=0.45)
    return c, -3.0, 0.12, 0.25


def sfx_select_knight():
    c = np.zeros((int(0.28 * SR), 2))
    # Manopla de aço e armadura pesada ressoando
    cl1 = modal_strike(540.0, 0.24, decay_s=0.11,
                       ratios=(1.0, 1.56, 2.34, 3.45, 4.80),
                       amps=(0.85, 0.72, 0.48, 0.30, 0.15),
                       impact_noise_ms=3.5, seed=1700)
    cl2 = modal_strike(880.0, 0.18, decay_s=0.09,
                       ratios=(1.0, 1.65, 2.48), amps=(0.55, 0.38, 0.22),
                       impact_noise_ms=2.5, seed=1710)
    mix_at(c, cl1, 0.0, gain=0.80, pan=-0.10)
    mix_at(c, cl2, 0.042, gain=0.55, pan=0.12)
    return c, -2.6, 0.16, 0.36


def sfx_select_building():
    c = np.zeros((int(0.22 * SR), 2))
    # Batida grave em porta de carvalho/pedra
    knock = wood_body(122.0, 0.68, 0.20, decay_s=0.055, crack_band=(500, 2100), crack_ms=9.0, seed=1800)
    mix_at(c, knock, 0.0, gain=0.95)
    return c, -3.0, 0.14, 0.30


def sfx_select_resource():
    c = np.zeros((int(0.18 * SR), 2))
    chime = modal_strike(1220.0, 0.17, decay_s=0.07,
                         ratios=(1.0, 1.54, 2.35), amps=(0.65, 0.45, 0.25),
                         impact_noise_ms=2.0, seed=1900)
    wood = wood_body(220.0, 0.72, 0.12, decay_s=0.032, crack_band=(900, 3200), seed=1910)
    mix_at(c, chime, 0.0, gain=0.55)
    mix_at(c, wood, 0.0, gain=0.55)
    return c, -3.2, 0.14, 0.28


def sfx_cmd_move(v):
    c = np.zeros((int(0.080 * SR), 2))
    # Toque tátil seco, limpo e discreto de peça de madeira nobre sobre pergaminho (zero sweep, zero "vuvuu")
    n_w = int(0.055 * SR)
    w = karplus_strong(265.0 + v * 28.0, 0.055, damping=0.82, brightness=0.38, seed=2000 + v * 11)
    w *= exp_env(w.shape[0], attack_s=0.001, decay_s=0.010)[:, None]
    w = bandpass_fft(w, 240.0, 2200.0, order=2)

    n_t = int(0.045 * SR)
    t_contact = noise_stereo(n_t, seed=2020 + v * 17)
    t_contact *= exp_env(n_t, attack_s=0.001, decay_s=0.007)[:, None]
    t_contact = bandpass_fft(t_contact, 1150.0, 3800.0, order=2)

    mix_at(c, w, 0.0, gain=1.0)
    mix_at(c, t_contact, 0.0, gain=0.36)
    return c, -5.4, 0.02, 0.08


def sfx_cmd_attack():
    c = np.zeros((int(0.32 * SR), 2))
    # Ordem de ataque: duplo entrechoque de lâminas
    c1 = modal_strike(1180.0, 0.20, decay_s=0.09,
                      ratios=(1.0, 1.58, 2.35, 3.40), amps=(0.80, 0.62, 0.40, 0.22),
                      impact_noise_ms=3.5, seed=2100)
    c2 = modal_strike(1420.0, 0.24, decay_s=0.12,
                      ratios=(1.0, 1.62, 2.44, 3.60), amps=(0.85, 0.65, 0.42, 0.24),
                      impact_noise_ms=3.5, seed=2110)
    mix_at(c, c1, 0.0, gain=0.72, pan=-0.15)
    mix_at(c, c2, 0.075, gain=0.88, pan=0.15)
    return c, -2.6, 0.16, 0.36


def sfx_cmd_gather():
    c = np.zeros((int(0.18 * SR), 2))
    w1 = wood_body(210.0, 0.70, 0.11, decay_s=0.030, crack_band=(1200, 4200), seed=2200)
    t2 = modal_strike(1340.0, 0.12, decay_s=0.05, ratios=(1.0, 1.68), amps=(0.55, 0.35),
                      impact_noise_ms=2.0, seed=2210)
    mix_at(c, w1, 0.0, gain=0.78)
    mix_at(c, t2, 0.055, gain=0.58)
    return c, -3.2, 0.10, 0.24


def sfx_cmd_rally():
    c = np.zeros((int(0.20 * SR), 2))
    # Estalo seco e rápido de estandarte + haste fincada no solo (sem filtro varrido)
    n_fl = int(0.075 * SR)
    flap = bandpass_fft(noise_stereo(n_fl, seed=2300), 650.0, 2400.0, order=2)
    flap *= exp_env(n_fl, 0.002, 0.014)[:, None]
    staff = wood_body(165.0, 0.65, 0.12, decay_s=0.024, crack_band=(750, 2600), crack_ms=8.0, seed=2310)
    mix_at(c, flap, 0.0, gain=0.72)
    mix_at(c, staff, 0.025, gain=0.90)
    return c, -3.2, 0.08, 0.18


def sfx_ui_click():
    c = np.zeros((int(0.095 * SR), 2))
    # Clique tátil em madeira entalhada e latão
    w = wood_body(340.0, 0.75, 0.08, decay_s=0.018, crack_band=(1400, 4600), crack_ms=4.0, seed=2400)
    tick = modal_strike(1950.0, 0.06, decay_s=0.018, ratios=(1.0, 1.72), amps=(0.45, 0.25),
                        impact_noise_ms=1.5, seed=2410)
    mix_at(c, w, 0.0, gain=0.85)
    mix_at(c, tick, 0.0, gain=0.42)
    return c, -3.5, 0.06, 0.15


def sfx_ui_error():
    c = np.zeros((int(0.22 * SR), 2))
    # Negativa grave abafada
    d1 = wood_body(108.0, 0.72, 0.12, decay_s=0.045, crack_band=(250, 950), seed=2500)
    d2 = wood_body(86.0, 0.65, 0.14, decay_s=0.055, crack_band=(200, 800), seed=2510)
    mix_at(c, d1, 0.0, gain=0.85)
    mix_at(c, d2, 0.075, gain=0.90)
    return c, -2.8, 0.10, 0.24


def sfx_train_queue():
    c = np.zeros((int(0.24 * SR), 2))
    # Moeda + carimbo de recrutamento
    coin = modal_strike(3100.0, 0.18, decay_s=0.08,
                        ratios=(1.0, 1.58, 2.34), amps=(0.70, 0.50, 0.30),
                        impact_noise_ms=2.0, seed=2600)
    stamp = wood_body(195.0, 0.70, 0.12, decay_s=0.032, crack_band=(800, 2600), seed=2610)
    mix_at(c, stamp, 0.0, gain=0.65)
    mix_at(c, coin, 0.035, gain=0.62)
    return c, -3.0, 0.12, 0.28


def sfx_train_cancel():
    c = np.zeros((int(0.20 * SR), 2))
    c1 = modal_strike(2350.0, 0.14, decay_s=0.06, ratios=(1.0, 1.56), amps=(0.55, 0.35),
                      impact_noise_ms=1.5, seed=2700)
    c2 = modal_strike(1780.0, 0.15, decay_s=0.06, ratios=(1.0, 1.56), amps=(0.50, 0.30),
                      impact_noise_ms=1.5, seed=2710)
    mix_at(c, c1, 0.0, gain=0.60)
    mix_at(c, c2, 0.055, gain=0.55)
    return c, -3.2, 0.12, 0.28


def sfx_unit_ready():
    c = np.zeros((int(0.62 * SR), 2))
    # Chamada breve de trompa de caça medieval (A3 -> D4 com oitava suave)
    h1 = brass_voice(208.0, 220.0, 0.20, attack_s=0.035, release_s=0.08, bright=0.68, seed=2800)
    h2 = brass_voice(278.0, 293.66, 0.42, attack_s=0.035, release_s=0.18, bright=0.80, seed=2810)
    h2_oct = brass_voice(568.0, 587.33, 0.38, attack_s=0.055, release_s=0.18, bright=0.65, seed=2820)
    mix_at(c, h1, 0.0, gain=0.72, pan=-0.10)
    mix_at(c, h2, 0.14, gain=0.78, pan=0.08)
    mix_at(c, h2_oct, 0.15, gain=0.38, pan=-0.08)
    return c, -2.5, 0.30, 0.72


def sfx_horn_alert():
    c = np.zeros((int(1.75 * SR), 2))
    # Trompa de guerra medieval (olifante em D3 -> F3 -> D3 com sopro e rugosidade)
    h1 = brass_voice(134.0, 146.83, 0.56, attack_s=0.10, release_s=0.14, bright=0.92, vibrato_cents=10.0, flutter=0.12, seed=2900)
    h2 = brass_voice(148.0, 174.61, 0.42, attack_s=0.06, release_s=0.12, bright=1.00, vibrato_cents=12.0, flutter=0.10, seed=2910)
    h3 = brass_voice(168.0, 146.83, 0.92, attack_s=0.07, release_s=0.40, bright=0.85, vibrato_cents=14.0, flutter=0.14, seed=2920)
    # Sub-grave de suporte (oitava abaixo suave) para imponência sem soar sintético
    sub = brass_voice(70.0, 73.42, 0.90, attack_s=0.12, release_s=0.38, bright=0.42, vibrato_cents=6.0, seed=2930)
    mix_at(c, h1, 0.0, gain=0.82)
    mix_at(c, h2, 0.42, gain=0.90)
    mix_at(c, h3, 0.72, gain=0.95)
    mix_at(c, sub, 0.72, gain=0.48)
    return c, -1.6, 0.42, 1.15


def sfx_age_up():
    c = np.zeros((int(2.10 * SR), 2))
    # Fanfarra Real solene em metais medievais (D4 - A4 - D5 sustentado em acorde nobre)
    drum = wood_body(68.0, 0.45, 0.35, decay_s=0.11, crack_band=(90, 500), seed=3040)
    mix_at(c, drum, 0.0, gain=0.85)
    fanfare = [
        (0.00, 293.66, 0.28, -0.18, 0.65),
        (0.20, 440.00, 0.28, 0.16, 0.75),
        (0.42, 587.33, 1.10, 0.12, 0.88),
        (0.42, 440.00, 1.10, -0.18, 0.72),
        (0.42, 293.66, 1.10, -0.05, 0.62),
        (0.42, 146.83, 1.10, 0.05, 0.50),
    ]
    for i, (off, f, dur, pan, br) in enumerate(fanfare):
        v = brass_voice(f * 0.96, f, dur, attack_s=0.055, release_s=0.38, bright=br, seed=3000 + i)
        mix_at(c, v, off, gain=0.68 if off < 0.4 else 0.46, pan=pan)
    bell = modal_strike(587.33, 1.25, decay_s=0.48,
                        ratios=(1.0, 2.0, 3.0, 4.02), amps=(0.65, 0.32, 0.15, 0.06),
                        impact_noise_ms=2.0, seed=3050)
    mix_at(c, bell, 0.42, gain=0.48)
    return c, -1.5, 0.42, 1.15


def sfx_victory():
    c = np.zeros((int(2.35 * SR), 2))
    # Tambores de guerra + acorde heróico de trompas reais (D4 -> F#4 -> A4 -> D5)
    d1 = wood_body(66.0, 0.45, 0.34, decay_s=0.12, crack_band=(90, 520), seed=3100)
    d2 = wood_body(62.0, 0.45, 0.38, decay_s=0.14, crack_band=(90, 520), seed=3105)
    mix_at(c, d1, 0.0, gain=0.95)
    mix_at(c, d2, 0.24, gain=1.08)

    notes = [
        (0.04, 293.66, 0.28, -0.20, 0.70),
        (0.24, 369.99, 0.28, 0.20, 0.76),
        (0.46, 440.00, 0.32, -0.14, 0.82),
        (0.68, 587.33, 1.25, 0.16, 0.88),
        (0.68, 440.00, 1.25, -0.20, 0.74),
        (0.68, 369.99, 1.25, 0.22, 0.68),
        (0.68, 293.66, 1.25, 0.00, 0.62),
        (0.68, 146.83, 1.25, 0.00, 0.48),
    ]
    for i, (off, f, dur, pan, br) in enumerate(notes):
        v = brass_voice(f * 0.96, f, dur, attack_s=0.055, release_s=0.42, bright=br, seed=3110 + i)
        mix_at(c, v, off, gain=0.62 if off < 0.6 else 0.42, pan=pan)
    return c, -1.5, 0.44, 1.25


def sfx_defeat():
    c = np.zeros((int(2.15 * SR), 2))
    # Frase descendente sombria em trompas graves (D3 -> C3 -> Bb2 -> A2) + sino fúnebre
    notes = [
        (0.00, 146.83, 0.44, -0.12),
        (0.38, 130.81, 0.44, 0.12),
        (0.76, 116.54, 0.48, -0.10),
        (1.14, 110.00, 0.88, 0.0),
    ]
    for i, (off, f, dur, pan) in enumerate(notes):
        v = brass_voice(f * 1.02, f, dur, attack_s=0.075, release_s=0.32, bright=0.58, vibrato_cents=11.0, seed=3200 + i)
        mix_at(c, v, off, gain=0.72, pan=pan)
    toll = modal_strike(146.83, 1.50, decay_s=0.62,
                        ratios=(1.0, 1.48, 2.02, 2.86, 3.74),
                        amps=(0.82, 0.48, 0.32, 0.18, 0.08),
                        impact_noise_ms=3.0, impact_band=(300, 1800), seed=3250)
    mix_at(c, toll, 0.02, gain=0.58)
    return c, -1.8, 0.42, 1.25


def main():
    catalog = {
        # Combate 3D
        "sfx_sword_hit_1.wav": lambda: sfx_sword_hit(0),
        "sfx_sword_hit_2.wav": lambda: sfx_sword_hit(1),
        "sfx_sword_hit_3.wav": lambda: sfx_sword_hit(2),
        "sfx_halberd_hit_1.wav": lambda: sfx_halberd_hit(0),
        "sfx_halberd_hit_2.wav": lambda: sfx_halberd_hit(1),
        "sfx_halberd_hit_3.wav": lambda: sfx_halberd_hit(2),
        "sfx_worker_hit_1.wav": lambda: sfx_worker_hit(0),
        "sfx_worker_hit_2.wav": lambda: sfx_worker_hit(1),
        "sfx_arrow_shoot_1.wav": lambda: sfx_arrow_shoot(0),
        "sfx_arrow_shoot_2.wav": lambda: sfx_arrow_shoot(1),
        "sfx_arrow_shoot_3.wav": lambda: sfx_arrow_shoot(2),
        "sfx_arrow_hit_1.wav": lambda: sfx_arrow_hit(0),
        "sfx_arrow_hit_2.wav": lambda: sfx_arrow_hit(1),
        "sfx_arrow_hit_3.wav": lambda: sfx_arrow_hit(2),
        "sfx_unit_death_1.wav": lambda: sfx_unit_death(0),
        "sfx_unit_death_2.wav": lambda: sfx_unit_death(1),
        "sfx_unit_death_3.wav": lambda: sfx_unit_death(2),
        # Economia & Prédios 3D
        "sfx_mine_gold_1.wav": lambda: sfx_mine_gold(0),
        "sfx_mine_gold_2.wav": lambda: sfx_mine_gold(1),
        "sfx_mine_gold_3.wav": lambda: sfx_mine_gold(2),
        "sfx_chop_wood_1.wav": lambda: sfx_chop_wood(0),
        "sfx_chop_wood_2.wav": lambda: sfx_chop_wood(1),
        "sfx_chop_wood_3.wav": lambda: sfx_chop_wood(2),
        "sfx_deposit_gold.wav": sfx_deposit_gold,
        "sfx_deposit_wood.wav": sfx_deposit_wood,
        "sfx_build_hammer_1.wav": lambda: sfx_build_hammer(0),
        "sfx_build_hammer_2.wav": lambda: sfx_build_hammer(1),
        "sfx_build_hammer_3.wav": lambda: sfx_build_hammer(2),
        "sfx_build_place.wav": sfx_build_place,
        "sfx_build_complete.wav": sfx_build_complete,
        "sfx_building_collapse.wav": sfx_building_collapse,
        # Seleção & Ordens 2D
        "sfx_select_worker.wav": sfx_select_worker,
        "sfx_select_soldier.wav": sfx_select_soldier,
        "sfx_select_archer.wav": sfx_select_archer,
        "sfx_select_knight.wav": sfx_select_knight,
        "sfx_select_building.wav": sfx_select_building,
        "sfx_select_resource.wav": sfx_select_resource,
        "sfx_cmd_move_1.wav": lambda: sfx_cmd_move(0),
        "sfx_cmd_move_2.wav": lambda: sfx_cmd_move(1),
        "sfx_cmd_attack.wav": sfx_cmd_attack,
        "sfx_cmd_gather.wav": sfx_cmd_gather,
        "sfx_cmd_rally.wav": sfx_cmd_rally,
        # UI, Produção & Stingers 2D
        "sfx_ui_click.wav": sfx_ui_click,
        "sfx_ui_error.wav": sfx_ui_error,
        "sfx_train_queue.wav": sfx_train_queue,
        "sfx_train_cancel.wav": sfx_train_cancel,
        "sfx_unit_ready.wav": sfx_unit_ready,
        "sfx_horn_alert.wav": sfx_horn_alert,
        "sfx_age_up.wav": sfx_age_up,
        "sfx_victory.wav": sfx_victory,
        "sfx_defeat.wav": sfx_defeat,
    }

    assert len(catalog) == 51, f"Expected 51 SFX files, got {len(catalog)}"

    failures = []
    print(f"[SFXGen] Generating {len(catalog)} medieval RTS SFX into {OUT_DIR} ...")
    for fname, fn in catalog.items():
        raw, target_pk, wet, rt60 = fn()
        if not np.all(np.isfinite(raw)):
            failures.append((fname, "NaN/Inf in raw buffer"))
            continue
        stats = master_and_save(os.path.join(OUT_DIR, fname), raw, target_peak_db=target_pk, wet=wet, rt60_s=rt60)
        ok = (
            stats["dur_s"] >= 0.05
            and -8.0 <= stats["peak_db"] <= -0.3
            and stats["rms_db"] >= -36.0
            and stats["dc"] < 0.005
            and stats["edge"] < 0.003
        )
        status = "OK" if ok else "FAIL"
        if not ok:
            failures.append((fname, stats))
        print(f"  {status:4s} {stats['file']:28s} dur={stats['dur_s']:.2f}s peak={stats['peak_db']:.1f}dBFS rms={stats['rms_db']:.1f}dBFS")

    if failures:
        raise RuntimeError(f"QA failed for {len(failures)} SFX files: {failures}")
    print(f"[SFXGen] ALL {len(catalog)} SFX PASSED ACOUSTIC QA.")


if __name__ == "__main__":
    main()
