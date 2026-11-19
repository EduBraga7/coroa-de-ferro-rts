"""
Gerador Offline de Mapa Baked PBR 2048x2048 (Albedo Composto + Masks) e Normal Map Micro-Detalhe (256x256)
para o terreno de alta fidelidade e alto FPS do RTS 'Coroa de Ferro' (2 texture reads por pixel no shader).
Executado via Blender 5.2 headless (-b -P) aproveitando bpy + numpy.
"""

import os
import bpy
import numpy as np


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
TEXTURES_DIR = os.path.join(PROJECT_DIR, "assets", "textures")

os.makedirs(TEXTURES_DIR, exist_ok=True)


def _periodic_value_noise(size, cells, seed=0):
    rng = np.random.default_rng(seed)
    c = max(2, int(cells))
    grid = rng.random((c, c), dtype=np.float32)
    t = np.linspace(0.0, float(c), size, endpoint=False, dtype=np.float32)
    i0 = np.floor(t).astype(np.int32) % c
    i1 = (i0 + 1) % c
    f = t - np.floor(t)
    f = f * f * (3.0 - 2.0 * f)
    fx = f[None, :]
    fy = f[:, None]
    v00 = grid[i0[:, None], i0[None, :]]
    v10 = grid[i0[:, None], i1[None, :]]
    v01 = grid[i1[:, None], i0[None, :]]
    v11 = grid[i1[:, None], i1[None, :]]
    return (v00 * (1.0 - fx) + v10 * fx) * (1.0 - fy) + (v01 * (1.0 - fx) + v11 * fx) * fy


def _periodic_fbm(size, octaves=(4, 8, 16, 32), seed=1):
    acc = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    tot = 0.0
    for idx, sc in enumerate(octaves):
        acc += _periodic_value_noise(size, sc, seed=seed + idx * 31) * amp
        tot += amp
        amp *= 0.5
    return acc / tot


def _height_to_normal_rgb(height, strength=3.2):
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(height)
    inv_l = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    r = nx * inv_l * 0.5 + 0.5
    g = ny * inv_l * 0.5 + 0.5
    b = nz * inv_l * 0.5 + 0.5
    return np.stack([r, g, b], axis=-1)


def _save_png(filename, array_float):
    h, w, c = array_float.shape
    path = os.path.join(TEXTURES_DIR, filename)
    img = bpy.data.images.new(name=filename, width=w, height=h, alpha=False)
    if c == 3:
        rgba = np.concatenate([array_float, np.ones((h, w, 1), dtype=np.float32)], axis=-1)
    else:
        rgba = array_float
    # Blender espera bottom-up; flip vertical para que row=0 do array (z=-110) fique no topo do PNG (UV.y=0 no Godot)
    flipped = np.flipud(np.clip(rgba, 0.0, 1.0))
    buf = np.ascontiguousarray(flipped, dtype=np.float32).ravel()
    img.pixels.foreach_set(buf)
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    print(f"[Textures] Saved: {path}")


def _smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / max(1e-6, edge1 - edge0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def _dist_to_segment(px, pz, ax, az, bx, bz):
    abx = bx - ax
    abz = bz - az
    len_sq = abx * abx + abz * abz
    if len_sq < 1e-6:
        return np.sqrt((px - ax) ** 2 + (pz - az) ** 2)
    t = np.clip(((px - ax) * abx + (pz - az) * abz) / len_sq, 0.0, 1.0)
    cx = ax + t * abx
    cz = az + t * abz
    return np.sqrt((px - cx) ** 2 + (pz - cz) ** 2)


def _river_distance(xx, zz):
    meander = np.sin((xx + zz) * 0.038) * 1.35 + np.cos((xx + zz) * 0.09) * 0.45
    return np.abs(xx - zz + meander)


def _terrain_height(xx, zz):
    dr = _river_distance(xx, zz)
    river_cut = (1.0 - _smoothstep(2.2, 6.2, dr)) * -1.05
    border_dist = np.maximum(np.abs(xx), np.abs(zz))
    outer_mask = _smoothstep(72.0, 104.0, border_dist)
    hill_n = (np.sin(xx * 0.0585 + np.cos(zz * 0.0495)) * 0.5 + np.cos(zz * 0.0765 - np.sin(xx * 0.0405)) * 0.5) * 0.5 + 0.5
    hills = outer_mask * (2.6 + hill_n * 8.5) * _smoothstep(4.0, 9.0, dr)
    return river_cut + hills


def _build_grass_tile(size=512):
    f_macro = _periodic_fbm(size, octaves=(4, 8, 16, 32), seed=301)
    f_med = _periodic_fbm(size, octaves=(32, 64, 128), seed=302)
    clover_patch = _periodic_fbm(size, octaves=(6, 12, 24), seed=305)
    blades = (
        _periodic_value_noise(size, 128, seed=303) * 0.45
        + _periodic_value_noise(size, 256, seed=304) * 0.55
    )
    blades = np.clip((blades - 0.28) * 1.75, 0.0, 1.0)

    c_soil = np.array([0.08, 0.14, 0.04], dtype=np.float32)[None, None, :]
    c_deep = np.array([0.06, 0.20, 0.05], dtype=np.float32)[None, None, :]
    c_lush = np.array([0.14, 0.33, 0.08], dtype=np.float32)[None, None, :]
    c_clover = np.array([0.12, 0.37, 0.10], dtype=np.float32)[None, None, :]
    c_tip = np.array([0.25, 0.45, 0.11], dtype=np.float32)[None, None, :]

    base = c_deep * (1.0 - f_macro[..., None]) + c_lush * f_macro[..., None]
    clover_m = _smoothstep(0.54, 0.78, clover_patch)[..., None] * 0.38
    base = base * (1.0 - clover_m) + c_clover * clover_m
    base = base * (1.0 - blades[..., None] * 0.48) + c_tip * (blades[..., None] * 0.48)
    turf = c_soil * (1.0 - f_med[..., None]) * 0.30 + base * (0.70 + 0.30 * f_med[..., None])

    # Flores silvestres douradas e brancas concentradas em manchas orgânicas no prado
    flower_patch = _smoothstep(0.52, 0.72, _periodic_fbm(size, octaves=(4, 8, 16), seed=310))
    fl_gold = _smoothstep(0.84, 0.93, _periodic_value_noise(size, 256, seed=311)) * flower_patch
    fl_white = _smoothstep(0.85, 0.94, _periodic_value_noise(size, 256, seed=312)) * flower_patch
    c_gold = np.array([0.92, 0.78, 0.22], dtype=np.float32)[None, None, :]
    c_white = np.array([0.90, 0.93, 0.96], dtype=np.float32)[None, None, :]
    turf = turf * (1.0 - fl_gold[..., None] * 0.85) + c_gold * (fl_gold[..., None] * 0.85)
    turf = turf * (1.0 - fl_white[..., None] * 0.80) + c_white * (fl_white[..., None] * 0.80)
    return turf


def _build_moss_tile(size=512):
    f1 = _periodic_fbm(size, octaves=(4, 12, 32, 64), seed=351)
    f2 = _periodic_fbm(size, octaves=(64, 128, 256), seed=352)
    needles = _periodic_value_noise(size, 192, seed=353)
    c_humus = np.array([0.06, 0.09, 0.03], dtype=np.float32)[None, None, :]
    c_moss = np.array([0.10, 0.22, 0.06], dtype=np.float32)[None, None, :]
    c_leaf = np.array([0.16, 0.20, 0.07], dtype=np.float32)[None, None, :]

    col = c_humus * (1.0 - f1[..., None]) + c_moss * f1[..., None]
    col = col * (0.76 + 0.32 * f2[..., None])
    needle_m = _smoothstep(0.58, 0.85, needles)[..., None] * 0.38
    return col * (1.0 - needle_m) + c_leaf * needle_m


def _build_road_tile(size=512):
    f1 = _periodic_fbm(size, octaves=(4, 12, 32, 64), seed=401)
    f2 = _periodic_fbm(size, octaves=(48, 96, 192), seed=402)
    pebbles_raw = _periodic_value_noise(size, 160, seed=403) * 0.6 + _periodic_value_noise(size, 256, seed=404) * 0.4
    pebbles = _smoothstep(0.64, 0.84, pebbles_raw)

    c_dark = np.array([0.21, 0.15, 0.09], dtype=np.float32)[None, None, :]
    c_warm = np.array([0.37, 0.28, 0.17], dtype=np.float32)[None, None, :]
    c_pebble = np.array([0.44, 0.41, 0.37], dtype=np.float32)[None, None, :]

    rgb = c_dark * (1.0 - f1[..., None]) + c_warm * f1[..., None]
    rgb = rgb * (0.78 + 0.32 * f2[..., None])
    return rgb * (1.0 - pebbles[..., None] * 0.62) + c_pebble * (pebbles[..., None] * 0.62)


def _build_cobble_tile(size=512):
    # 64 linhas x 48 colunas no tile de 55m => blocos medievais nitidos (~0.85m x 1.15m) perfeitamente visiveis no zoom RTS
    yy, xx = np.mgrid[0:size, 0:size]
    u = xx.astype(np.float32) / float(size)
    v = yy.astype(np.float32) / float(size)

    rows = 64.0
    cols = 48.0
    row_i = np.floor(v * rows)
    u_st = np.mod(u * cols + np.mod(row_i, 2.0) * 0.5, 1.0)
    v_st = np.mod(v * rows, 1.0)

    cell_x = np.floor(np.mod(u * cols + np.mod(row_i, 2.0) * 0.5, cols)).astype(np.int32)
    cell_y = row_i.astype(np.int32) % int(rows)

    rng = np.random.default_rng(501)
    cell_var = rng.random((int(rows), int(cols)), dtype=np.float32)[cell_y, cell_x]

    fbm_stone = _periodic_fbm(size, octaves=(16, 48, 128, 256), seed=502)
    dx = np.minimum(u_st, 1.0 - u_st)
    dy = np.minimum(v_st, 1.0 - v_st)
    edge = np.minimum(dx * 1.25, dy)
    bevel = _smoothstep(0.05, 0.22, edge)
    mortar = 1.0 - _smoothstep(0.03, 0.09, edge)

    c_mortar = np.array([0.11, 0.13, 0.09], dtype=np.float32)[None, None, :]
    c_st_a = np.array([0.27, 0.28, 0.30], dtype=np.float32)[None, None, :]
    c_st_b = np.array([0.43, 0.41, 0.37], dtype=np.float32)[None, None, :]

    stone_col = c_st_a * (1.0 - cell_var[..., None]) + c_st_b * cell_var[..., None]
    stone_col *= (0.74 + 0.34 * fbm_stone[..., None]) * (0.82 + 0.22 * bevel[..., None])
    return stone_col * (1.0 - mortar[..., None]) + c_mortar * mortar[..., None]


def _build_shore_tile(size=512):
    f1 = _periodic_fbm(size, octaves=(4, 12, 32, 64), seed=601)
    f2 = _periodic_fbm(size, octaves=(48, 128, 256), seed=602)
    stones = _smoothstep(0.55, 0.78, _periodic_value_noise(size, 160, seed=603))

    c_sand = np.array([0.46, 0.40, 0.29], dtype=np.float32)[None, None, :]
    c_wet = np.array([0.28, 0.24, 0.18], dtype=np.float32)[None, None, :]
    c_gravel = np.array([0.39, 0.39, 0.38], dtype=np.float32)[None, None, :]

    rgb = c_wet * (1.0 - f1[..., None]) + c_sand * f1[..., None]
    rgb = rgb * (0.82 + 0.28 * f2[..., None])
    return rgb * (1.0 - stones[..., None] * 0.55) + c_gravel * (stones[..., None] * 0.55)


def generate_baked_albedo(size=2048):
    coords = np.linspace(-110.0, 110.0, size, endpoint=False, dtype=np.float32) + (110.0 / float(size))
    xx, zz = np.meshgrid(coords, coords)  # zz[0] = -110 (Norte, UV.y = 0)

    n_macro = _periodic_fbm(size, octaves=(6, 12, 24, 48), seed=101)
    n_detail = _periodic_fbm(size, octaves=(32, 64, 128), seed=202)
    jitter = (n_macro - 0.5) * 3.4 + (n_detail - 0.5) * 1.2
    jitter_road = (n_macro - 0.5) * 2.2 + (n_detail - 0.5) * 0.45

    # 1. Máscara de Estradas Imperiais e trilhas secundárias (bordas mais limpas sem ruído pontilhado)
    road_paths = [
        (-55.0, 55.0, 0.0, 0.0, 3.6),
        (0.0, 0.0, 55.0, -55.0, 3.6),
        (-55.0, 55.0, -48.0, 10.0, 2.5),
        (-48.0, 10.0, -34.0, -34.0, 2.6),
        (-55.0, 55.0, -10.0, 46.0, 2.5),
        (-10.0, 46.0, 34.0, 34.0, 2.6),
        (55.0, -55.0, 10.0, -46.0, 2.5),
        (10.0, -46.0, -34.0, -34.0, 2.6),
        (55.0, -55.0, 48.0, -10.0, 2.5),
        (48.0, -10.0, 34.0, 34.0, 2.6),
        (-16.0, 12.0, -3.0, 3.0, 2.0),
        (16.0, -12.0, 3.0, -3.0, 2.0),
        (-55.0, 55.0, -68.0, 56.0, 2.1),
        (-55.0, 55.0, -52.0, 71.0, 2.1),
        (55.0, -55.0, 68.0, -56.0, 2.1),
        (55.0, -55.0, 52.0, -71.0, 2.1),
    ]
    road_mask = np.zeros((size, size), dtype=np.float32)
    road_center = np.zeros((size, size), dtype=np.float32)
    for ax, az, bx, bz, half_w in road_paths:
        d = _dist_to_segment(xx, zz, ax, az, bx, bz) + jitter_road * 0.55
        m = 1.0 - _smoothstep(half_w * 0.52, half_w * 1.25, d)
        c_m = 1.0 - _smoothstep(0.0, half_w * 0.65, d)
        road_mask = np.maximum(road_mask, m)
        road_center = np.maximum(road_center, c_m)

    # 2. Máscara de Calçamento Real das bases + Pátios das ruínas antigas (separados das minas)
    d_sw = np.sqrt((xx + 55.0) ** 2 + (zz - 55.0) ** 2)
    d_ne = np.sqrt((xx - 55.0) ** 2 + (zz + 55.0) ** 2)
    cobble_mask = 1.0 - _smoothstep(10.0, 13.8, np.minimum(d_sw, d_ne) + jitter * 0.72)

    ruin_centers = [(-15.0, -4.0), (15.0, 4.0), (-24.0, 22.0), (24.0, -22.0)]
    for rx, rz in ruin_centers:
        dr_p = np.sqrt((xx - rx) ** 2 + (zz - rz) ** 2) + jitter * 0.45
        cobble_mask = np.maximum(cobble_mask, (1.0 - _smoothstep(2.6, 4.4, dr_p)) * 0.88)

    # 3. Máscara Florestal musgosa sob os bosques e minas
    forest_spots = [
        (-73.0, 42.0, 9.0), (-69.0, 72.0, 10.0), (-40.0, 72.0, 8.0), (-62.0, 30.0, 8.5),
        (73.0, -42.0, 9.0), (69.0, -72.0, 10.0), (40.0, -72.0, 8.0), (62.0, -30.0, 8.5),
        (-25.0, 38.0, 7.5), (-46.0, 12.0, 6.5), (25.0, -38.0, 7.5), (46.0, -12.0, 6.5),
        (-16.0, 12.0, 5.5), (16.0, -12.0, 5.5), (-32.0, -14.0, 5.5), (32.0, 14.0, 5.5),
    ]
    forest_mask = np.zeros((size, size), dtype=np.float32)
    for fx, fz, fr in forest_spots:
        df = np.sqrt((xx - fx) ** 2 + (zz - fz) ** 2) + jitter * 0.85
        forest_mask = np.maximum(forest_mask, 1.0 - _smoothstep(fr * 0.40, fr * 1.15, df))
    forest_mask *= (1.0 - cobble_mask * 0.82)

    # 4. Máscaras do Rio (margem cascalhada e faixa úmida) + Encostas rochosas externas
    dr = _river_distance(xx, zz)
    shore_mask = 1.0 - _smoothstep(4.2, 7.2, dr + (n_detail - 0.5) * 2.2)
    wet_mask = 1.0 - _smoothstep(2.4, 4.9, dr)
    pebble_band = _smoothstep(4.0, 4.8, dr) * (1.0 - _smoothstep(6.2, 6.9, dr))
    pebble_dots = _smoothstep(0.70, 0.86, _periodic_value_noise(size, 256, seed=611)) * pebble_band

    step = 220.0 / float(size)
    h0 = _terrain_height(xx, zz)
    hx = _terrain_height(xx + step, zz)
    hz = _terrain_height(xx, zz + step)
    slope = 1.0 - (step / np.sqrt((h0 - hx) ** 2 + (h0 - hz) ** 2 + step * step))
    rock_mask = _smoothstep(0.08, 0.25, slope) * _smoothstep(70.0, 80.0, np.maximum(np.abs(xx), np.abs(zz)))

    # Construir padrões 512x512 e replicar em tiling contínuo 4x4 para 2048x2048
    grass_2k = np.tile(_build_grass_tile(512), (4, 4, 1))
    moss_2k = np.tile(_build_moss_tile(512), (4, 4, 1))
    road_2k = np.tile(_build_road_tile(512), (4, 4, 1))
    cobble_2k = np.tile(_build_cobble_tile(512), (4, 4, 1))
    shore_2k = np.tile(_build_shore_tile(512), (4, 4, 1))

    # Variação orgânica macro no prado para evitar uniformidade de cor
    macro_tint = 0.86 + 0.26 * n_macro[..., None]
    final_rgb = grass_2k * macro_tint
    final_rgb = final_rgb * (1.0 - forest_mask[..., None] * 0.82) + moss_2k * (forest_mask[..., None] * 0.82)

    # Trilho compactado/desgastado nas estradas com borda suavizada
    road_border = np.clip(road_mask - road_center, 0.0, 1.0)
    road_shade = road_2k * (0.94 - 0.14 * road_border[..., None] + 0.10 * n_detail[..., None])
    final_rgb = final_rgb * (1.0 - road_mask[..., None]) + road_shade * road_mask[..., None]

    # Calçamento das bases e ruínas (com desgaste orgânico nos limites)
    final_rgb = final_rgb * (1.0 - cobble_mask[..., None]) + cobble_2k * cobble_mask[..., None]

    # Margens, seixos naturais e leito úmido do rio
    river_pebble_col = np.array([0.45, 0.43, 0.40], dtype=np.float32)[None, None, :]
    shore_wet = shore_2k * (1.0 - wet_mask[..., None] * 0.44)
    shore_wet = shore_wet * (1.0 - pebble_dots[..., None] * 0.55) + river_pebble_col * (pebble_dots[..., None] * 0.55)
    final_rgb = final_rgb * (1.0 - shore_mask[..., None]) + shore_wet * shore_mask[..., None]

    # Rocha estratificada nas colinas de borda
    rock_col = shore_2k * np.array([0.66, 0.68, 0.72], dtype=np.float32)[None, None, :]
    final_rgb = final_rgb * (1.0 - rock_mask[..., None]) + rock_col * rock_mask[..., None]

    _save_png("terrain_baked_albedo.png", final_rgb)


def generate_detail_normal(size=256):
    f1 = _periodic_fbm(size, octaves=(4, 8, 16, 32), seed=701)
    f2 = _periodic_fbm(size, octaves=(32, 64, 128), seed=702)
    grain = _periodic_value_noise(size, 96, seed=703) * 0.55 + _periodic_value_noise(size, 128, seed=704) * 0.45
    height = np.clip(0.32 * f1 + 0.36 * f2 + 0.32 * grain, 0.0, 1.0)
    nrm = _height_to_normal_rgb(height, strength=3.4)
    _save_png("terrain_detail_normal.png", nrm)


def main():
    generate_baked_albedo(2048)
    generate_detail_normal(256)
    print("[Textures] BAKED TERRAIN ALBEDO (2048x2048) + DETAIL NORMAL (256x256) GENERATED SUCCESSFULLY.")


if __name__ == "__main__":
    main()
