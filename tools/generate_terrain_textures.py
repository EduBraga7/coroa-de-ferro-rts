"""
Gerador Offline de Mapa Baked PBR 2048x2048 (Albedo Composto + Masks) e Normal Map Micro-Detalhe (256x256)
para o terreno de alta fidelidade e alto FPS do RTS 'Coroa de Ferro' (2 texture reads por pixel no shader).
Executado via Blender 5.2 headless (-b -P) aproveitando bpy + numpy.
"""

import json
import os
import bpy
import numpy as np


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
TEXTURES_DIR = os.path.join(PROJECT_DIR, "assets", "textures")
LAYOUT_PATH = os.path.join(PROJECT_DIR, "data", "map_layout.json")

os.makedirs(TEXTURES_DIR, exist_ok=True)


def load_layout():
    """Lê data/map_layout.json (mesmo arquivo usado por scripts/map_generator.gd) e espelha o lado NE."""
    with open(LAYOUT_PATH, "r", encoding="utf-8") as fh:
        lay = json.load(fh)

    def mirror_pts(lst):
        out = []
        for e in lst:
            m = list(e)
            m[0] = -float(e[0])
            m[1] = -float(e[1])
            out.append(m)
        return list(lst) + out

    slots = []
    for s in lay["slots"]:
        slots.append(s)
        ms = {k: v for k, v in s.items()}
        ms["pos"] = [-s["pos"][0], -s["pos"][1]]
        for key in ("gold", "stone", "berries", "forests"):
            ms[key] = [[-e[0], -e[1]] + list(e[2:]) for e in s.get(key, [])]
        slots.append(ms)
    neutral = {k: mirror_pts(v) for k, v in lay.get("neutral", {}).items()}
    roads = []
    for r in lay.get("roads", []):
        roads.append(tuple(float(v) for v in r))
        roads.append((-float(r[0]), -float(r[1]), -float(r[2]), -float(r[3]), float(r[4])))
    return {
        "map_half": float(lay.get("map_half", 100.0)),
        "terrain_half": float(lay.get("terrain_half", 130.0)),
        "plaza_radius": float(lay.get("plaza_radius", 12.0)),
        "slots": slots,
        "neutral": neutral,
        "roads": roads,
    }


LAYOUT = load_layout()
TERRAIN_HALF = LAYOUT["terrain_half"]
HILLS_START = LAYOUT["map_half"] - 2.0


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
    has_alpha = (c == 4)
    img = bpy.data.images.new(name=filename, width=w, height=h, alpha=has_alpha)
    if c == 3:
        rgba = np.concatenate([array_float, np.ones((h, w, 1), dtype=np.float32)], axis=-1)
    else:
        rgba = array_float
    # Blender espera bottom-up; flip vertical para que row=0 do array (z=-terrain_half) fique no topo do PNG (UV.y=0 no Godot)
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
    outer_mask = _smoothstep(HILLS_START, HILLS_START + 30.0, border_dist)
    hill_n = (np.sin(xx * 0.0585 + np.cos(zz * 0.0495)) * 0.5 + np.cos(zz * 0.0765 - np.sin(xx * 0.0405)) * 0.5) * 0.5 + 0.5
    hills = outer_mask * (2.6 + hill_n * 8.5) * _smoothstep(4.0, 9.0, dr)
    return river_cut + hills


def _build_grass_tile(size=512):
    f_macro = _periodic_fbm(size, octaves=(4, 8, 16, 32), seed=301)
    f_med = _periodic_fbm(size, octaves=(32, 64, 128), seed=302)
    clover_patch = _periodic_fbm(size, octaves=(6, 12, 24), seed=305)
    warm_glade = _periodic_fbm(size, octaves=(4, 8, 16), seed=306)
    blades = (
        _periodic_value_noise(size, 128, seed=303) * 0.45
        + _periodic_value_noise(size, 256, seed=304) * 0.55
    )
    blades = np.clip((blades - 0.25) * 1.85, 0.0, 1.0)

    c_soil = np.array([0.07, 0.12, 0.04], dtype=np.float32)[None, None, :]
    c_deep = np.array([0.065, 0.20, 0.055], dtype=np.float32)[None, None, :]
    c_lush = np.array([0.145, 0.34, 0.085], dtype=np.float32)[None, None, :]
    c_clover = np.array([0.11, 0.36, 0.11], dtype=np.float32)[None, None, :]
    c_warm = np.array([0.23, 0.38, 0.10], dtype=np.float32)[None, None, :]
    c_tip = np.array([0.27, 0.46, 0.12], dtype=np.float32)[None, None, :]

    base = c_deep * (1.0 - f_macro[..., None]) + c_lush * f_macro[..., None]
    clover_m = _smoothstep(0.52, 0.78, clover_patch)[..., None] * 0.42
    base = base * (1.0 - clover_m) + c_clover * clover_m
    warm_m = _smoothstep(0.56, 0.82, warm_glade)[..., None] * 0.36
    base = base * (1.0 - warm_m) + c_warm * warm_m
    base = base * (1.0 - blades[..., None] * 0.44) + c_tip * (blades[..., None] * 0.44)
    # Flores 3D reais em WorldFoliage substituem os antigos pontos pixelizados no albedo
    turf = c_soil * (1.0 - f_med[..., None]) * 0.26 + base * (0.74 + 0.26 * f_med[..., None])
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
    th = TERRAIN_HALF
    coords = np.linspace(-th, th, size, endpoint=False, dtype=np.float32) + (th / float(size))
    xx, zz = np.meshgrid(coords, coords)  # zz[0] = -th (Norte, UV.y = 0)

    n_macro = _periodic_fbm(size, octaves=(6, 12, 24, 48), seed=101)
    n_detail = _periodic_fbm(size, octaves=(32, 64, 128), seed=202)
    jitter = (n_macro - 0.5) * 3.4 + (n_detail - 0.5) * 1.2
    jitter_road = (n_macro - 0.5) * 2.2 + (n_detail - 0.5) * 0.45

    # 1. Estradas de terra ligando as 6 posições de base às pontes (data/map_layout.json)
    road_mask = np.zeros((size, size), dtype=np.float32)
    road_center = np.zeros((size, size), dtype=np.float32)
    road_tracks = np.zeros((size, size), dtype=np.float32)
    for ax, az, bx, bz, half_w in LAYOUT["roads"]:
        d = _dist_to_segment(xx, zz, ax, az, bx, bz) + jitter_road * 0.55
        m = 1.0 - _smoothstep(half_w * 0.52, half_w * 1.28, d)
        c_m = 1.0 - _smoothstep(0.0, half_w * 0.65, d)
        # Sulcos sutis paralelos de carroça nas estradas
        trk = np.exp(-((d - half_w * 0.36) ** 2) / max(0.05, (half_w * 0.16) ** 2)) * m
        road_mask = np.maximum(road_mask, m)
        road_center = np.maximum(road_center, c_m)
        road_tracks = np.maximum(road_tracks, trk)

    # 2. Calçamento das praças nas 6 posições de base (ocupadas ou vilarejos abandonados) + ruínas
    plaza_r = LAYOUT["plaza_radius"]
    d_plaza = np.full((size, size), 1.0e6, dtype=np.float32)
    for s in LAYOUT["slots"]:
        px, pz = float(s["pos"][0]), float(s["pos"][1])
        d_plaza = np.minimum(d_plaza, np.sqrt((xx - px) ** 2 + (zz - pz) ** 2))
    cobble_mask = 1.0 - _smoothstep(plaza_r - 2.0, plaza_r + 1.8, d_plaza + jitter * 0.72)

    for ruin in LAYOUT["neutral"].get("ruins", []):
        rx, rz = float(ruin[0]), float(ruin[1])
        dr_p = np.sqrt((xx - rx) ** 2 + (zz - rz) ** 2) + jitter * 0.45
        cobble_mask = np.maximum(cobble_mask, (1.0 - _smoothstep(2.6, 4.4, dr_p)) * 0.88)

    # Solo pedregoso batido ao redor de minas de ouro e pedreiras
    mine_spots = []
    for s in LAYOUT["slots"]:
        mine_spots.extend(s.get("gold", []))
        mine_spots.extend(s.get("stone", []))
    mine_spots.extend(LAYOUT["neutral"].get("gold", []))
    mine_spots.extend(LAYOUT["neutral"].get("stone", []))
    for mspot in mine_spots:
        mx, mz = float(mspot[0]), float(mspot[1])
        dm = np.sqrt((xx - mx) ** 2 + (zz - mz) ** 2) + jitter * 0.6
        road_mask = np.maximum(road_mask, (1.0 - _smoothstep(2.4, 5.2, dm)) * 0.75)

    # 3. Máscara florestal musgosa sob os bosques das bases e florestas neutras
    forest_spots = []
    for s in LAYOUT["slots"]:
        forest_spots.extend(s.get("forests", []))
    forest_spots.extend(LAYOUT["neutral"].get("forests", []))
    forest_mask = np.zeros((size, size), dtype=np.float32)
    for spot in forest_spots:
        fx, fz, fr = float(spot[0]), float(spot[1]), float(spot[2])
        df = np.sqrt((xx - fx) ** 2 + (zz - fz) ** 2) + jitter * 0.85
        forest_mask = np.maximum(forest_mask, 1.0 - _smoothstep(fr * 0.55, fr * 1.25, df))
    forest_mask *= (1.0 - cobble_mask * 0.82)

    # 4. Máscaras do Rio (margem cascalhada e faixa úmida) + Encostas rochosas externas
    dr = _river_distance(xx, zz)
    shore_mask = 1.0 - _smoothstep(4.3, 7.4, dr + (n_detail - 0.5) * 2.2)
    wet_mask = 1.0 - _smoothstep(2.4, 5.1, dr)
    pebble_band = _smoothstep(4.2, 5.0, dr) * (1.0 - _smoothstep(6.2, 7.0, dr))
    pebble_dots = _smoothstep(0.70, 0.86, _periodic_value_noise(size, 256, seed=611)) * pebble_band

    step = (2.0 * th) / float(size)
    h0 = _terrain_height(xx, zz)
    hx = _terrain_height(xx + step, zz)
    hz = _terrain_height(xx, zz + step)
    slope = 1.0 - (step / np.sqrt((h0 - hx) ** 2 + (h0 - hz) ** 2 + step * step))
    rock_mask = _smoothstep(0.08, 0.25, slope) * _smoothstep(HILLS_START - 2.0, HILLS_START + 8.0, np.maximum(np.abs(xx), np.abs(zz)))

    # Construir padrões 512x512 e replicar em tiling contínuo 4x4 para 2048x2048
    grass_2k = np.tile(_build_grass_tile(512), (4, 4, 1))
    moss_2k = np.tile(_build_moss_tile(512), (4, 4, 1))
    road_2k = np.tile(_build_road_tile(512), (4, 4, 1))
    shore_2k = np.tile(_build_shore_tile(512), (4, 4, 1))

    # Variação orgânica macro no prado para evitar uniformidade de cor
    macro_tint = 0.84 + 0.30 * n_macro[..., None]
    final_rgb = grass_2k * macro_tint
    final_rgb = final_rgb * (1.0 - forest_mask[..., None] * 0.84) + moss_2k * (forest_mask[..., None] * 0.84)

    # Trilho compactado/desgastado nas estradas com borda suavizada e sulcos sutis
    road_border = np.clip(road_mask - road_center, 0.0, 1.0)
    road_shade = road_2k * (0.95 - 0.14 * road_border[..., None] - 0.12 * road_tracks[..., None] + 0.10 * n_detail[..., None])
    final_rgb = final_rgb * (1.0 - road_mask[..., None]) + road_shade * road_mask[..., None]

    # Nas praças/ruínas gravamos apenas variação macro de desgaste/AO (o padrão nítido vem do cobble_albedo tileado no shader!)
    plaza_wear = (0.86 + 0.22 * n_macro - 0.10 * (1.0 - n_detail))[..., None]
    plaza_base = np.array([0.33, 0.32, 0.30], dtype=np.float32)[None, None, :] * plaza_wear
    final_rgb = final_rgb * (1.0 - cobble_mask[..., None] * 0.78) + plaza_base * (cobble_mask[..., None] * 0.78)

    # Margens, seixos naturais e leito úmido do rio
    river_pebble_col = np.array([0.44, 0.42, 0.39], dtype=np.float32)[None, None, :]
    shore_wet = shore_2k * (1.0 - wet_mask[..., None] * 0.48)
    shore_wet = shore_wet * (1.0 - pebble_dots[..., None] * 0.55) + river_pebble_col * (pebble_dots[..., None] * 0.55)
    final_rgb = final_rgb * (1.0 - shore_mask[..., None]) + shore_wet * shore_mask[..., None]

    # Rocha estratificada nas colinas de borda
    rock_col = shore_2k * np.array([0.62, 0.65, 0.69], dtype=np.float32)[None, None, :]
    final_rgb = final_rgb * (1.0 - rock_mask[..., None]) + rock_col * rock_mask[..., None]

    _save_png("terrain_baked_albedo.png", final_rgb)

    # Exportar Splat Mask RGBA 1024x1024 perfeitamente alinhada por média 2x2
    splat_2k = np.stack([
        cobble_mask,
        road_mask,
        np.maximum(shore_mask, rock_mask),
        forest_mask,
    ], axis=-1)
    splat_1k = splat_2k.reshape(size // 2, 2, size // 2, 2, 4).mean(axis=(1, 3))
    _save_png("terrain_splat_mask.png", splat_1k)


def generate_cobble_maps(size=512):
    """Gera albedo e normal map artesanais de lajotas medievais para tiling de alta nitidez."""
    yy, xx = np.mgrid[0:size, 0:size]
    u = xx.astype(np.float32) / float(size)
    v = yy.astype(np.float32) / float(size)

    rows = 10
    cols = 10
    rng = np.random.default_rng(909)
    # Jitter periódico por célula para quebrar linhas retas artificiais
    jx = (rng.random((rows, cols), dtype=np.float32) - 0.5) * 0.24
    jy = (rng.random((rows, cols), dtype=np.float32) - 0.5) * 0.24
    col_var = rng.random((rows, cols), dtype=np.float32)
    hue_var = rng.random((rows, cols), dtype=np.float32)

    gx = u * float(cols)
    gy = v * float(rows)

    d1 = np.full((size, size), 1e6, dtype=np.float32)
    d2 = np.full((size, size), 1e6, dtype=np.float32)
    best_c = np.zeros((size, size), dtype=np.float32)
    best_h = np.zeros((size, size), dtype=np.float32)

    base_ix = np.floor(gx).astype(np.int32)
    base_iy = np.floor(gy).astype(np.int32)

    for dy_off in (-1, 0, 1):
        for dx_off in (-1, 0, 1):
            cx = (base_ix + dx_off) % cols
            cy = (base_iy + dy_off) % rows
            # Tijolamento escalonado nas linhas ímpares + jitter orgânico
            stagger = (cy % 2) * 0.45
            px = (base_ix + dx_off) + 0.5 + stagger * 0.35 + jx[cy, cx]
            py = (base_iy + dy_off) + 0.5 + jy[cy, cx]
            # Distância suavemente achatada para parecer bloco talhado e não círculo
            ddx = np.abs(gx - px) * 0.96
            ddy = np.abs(gy - py) * 1.06
            dist = np.sqrt(ddx * ddx + ddy * ddy) + 0.25 * np.maximum(ddx, ddy)
            mask1 = dist < d1
            d2 = np.where(mask1, d1, np.minimum(d2, dist))
            d1 = np.where(mask1, dist, d1)
            best_c = np.where(mask1, col_var[cy, cx], best_c)
            best_h = np.where(mask1, hue_var[cy, cx], best_h)

    edge_dist = d2 - d1
    mortar = 1.0 - _smoothstep(0.035, 0.11, edge_dist)
    bevel = _smoothstep(0.05, 0.24, edge_dist)
    fbm_rock = _periodic_fbm(size, octaves=(8, 24, 64, 128), seed=915)
    moss_patch = _smoothstep(0.56, 0.80, _periodic_fbm(size, octaves=(4, 8, 16), seed=919)) * mortar

    c_cool = np.array([0.33, 0.34, 0.36], dtype=np.float32)[None, None, :]
    c_warm = np.array([0.46, 0.43, 0.38], dtype=np.float32)[None, None, :]
    c_rust = np.array([0.42, 0.37, 0.31], dtype=np.float32)[None, None, :]
    c_mortar = np.array([0.13, 0.14, 0.12], dtype=np.float32)[None, None, :]
    c_moss = np.array([0.16, 0.24, 0.10], dtype=np.float32)[None, None, :]

    stone = c_cool * (1.0 - best_c[..., None]) + c_warm * best_c[..., None]
    stone = stone * (1.0 - best_h[..., None] * 0.35) + c_rust * (best_h[..., None] * 0.35)
    stone *= (0.78 + 0.34 * fbm_rock[..., None]) * (0.76 + 0.26 * bevel[..., None])

    m_col = c_mortar * (1.0 - moss_patch[..., None] * 0.72) + c_moss * (moss_patch[..., None] * 0.72)
    alb = stone * (1.0 - mortar[..., None]) + m_col * mortar[..., None]

    height = np.clip((1.0 - mortar) * (0.35 + 0.45 * bevel + 0.20 * fbm_rock), 0.0, 1.0)
    nrm = _height_to_normal_rgb(height, strength=4.2)

    _save_png("terrain_cobble_albedo.png", alb)
    _save_png("terrain_cobble_normal.png", nrm)


def generate_micro_detail(size=512):
    """R = micro-grão de grama, G = terra/pedregulhos de estrada, B = seixos/rocha estratificada."""
    grass_hi = _periodic_value_noise(size, 192, seed=801) * 0.6 + _periodic_value_noise(size, 256, seed=802) * 0.4
    grass_mid = _periodic_fbm(size, octaves=(24, 64, 128), seed=803)
    r_ch = np.clip(0.5 + (grass_hi - 0.5) * 0.65 + (grass_mid - 0.5) * 0.45, 0.0, 1.0)

    dirt_grit = _periodic_fbm(size, octaves=(16, 48, 128, 256), seed=811)
    pebbles = _smoothstep(0.66, 0.88, _periodic_value_noise(size, 160, seed=812))
    g_ch = np.clip(0.5 + (dirt_grit - 0.5) * 0.65 + pebbles * 0.26, 0.0, 1.0)

    rock_strata = _periodic_fbm(size, octaves=(8, 24, 64, 128), seed=821)
    shore_pebble = _smoothstep(0.58, 0.84, _periodic_value_noise(size, 128, seed=822))
    b_ch = np.clip(0.5 + (rock_strata - 0.5) * 0.6 + (shore_pebble - 0.3) * 0.35, 0.0, 1.0)

    rgb = np.stack([r_ch, g_ch, b_ch], axis=-1)
    _save_png("terrain_micro_detail.png", rgb)


def generate_detail_normal(size=512):
    f1 = _periodic_fbm(size, octaves=(8, 16, 32, 64), seed=701)
    f2 = _periodic_fbm(size, octaves=(48, 96, 192), seed=702)
    grain = _periodic_value_noise(size, 160, seed=703) * 0.55 + _periodic_value_noise(size, 256, seed=704) * 0.45
    height = np.clip(0.28 * f1 + 0.38 * f2 + 0.34 * grain, 0.0, 1.0)
    nrm = _height_to_normal_rgb(height, strength=3.8)
    _save_png("terrain_detail_normal.png", nrm)


def main():
    generate_baked_albedo(2048)
    generate_detail_normal(512)
    generate_cobble_maps(512)
    generate_micro_detail(512)
    print("[Textures] BAKED TERRAIN + SPLAT RGBA + HIGH-RES COBBLE/MICRO MAPS GENERATED SUCCESSFULLY.")


if __name__ == "__main__":
    main()
