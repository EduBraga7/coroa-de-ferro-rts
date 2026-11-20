"""
Gerador dos assets 3D da expansão de economia/militar do RTS 'Coroa de Ferro'.
Reaproveita os helpers de geometria e materiais de generate_blender_assets.py (prédios/recursos)
e generate_unit_assets.py (personagens com esqueleto e animações), sem regenerar os assets antigos.

Executar com o Blender 5.2 em modo headless:
    blender -b -P tools/generate_expansion_assets.py

Assets gerados em assets/models/:
  Prédios : building_farm, building_mill, building_lumber_camp, building_mining_camp,
            building_archery_range, building_siege_workshop, building_market, building_castle
  Recursos: resource_berry_bush, resource_stone_quarry
  Unidades: unit_spearman (rig + animações), unit_scout (rig + animações), unit_ram (estático)

Convenções (iguais aos geradores originais): frente = +Y no Blender (-Z no Godot), Z para cima,
base do modelo em Z = 0.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix, Euler

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import generate_blender_assets as gba  # noqa: E402
import generate_unit_assets as gua  # noqa: E402

PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
MODELS_DIR = os.path.join(PROJECT_DIR, "assets", "models")
BLENDER_DIR = os.path.join(PROJECT_DIR, "assets", "blender")

HALF_PI = math.pi * 0.5


# ==============================================================================
# MATERIAIS EXTRAS
# ==============================================================================

def create_extra_materials(mats, unit_mats):
    tex_soil = gba.generate_pbr_texture_set("TilledSoil", "foliage", (0.34, 0.23, 0.14), (0.20, 0.13, 0.08), seed=121)
    tex_quarry = gba.generate_pbr_texture_set("QuarryRock", "rock_strata", (0.48, 0.47, 0.44), (0.24, 0.23, 0.21), seed=122)
    tex_hide = gba.generate_pbr_texture_set("HideCover", "foliage", (0.50, 0.37, 0.24), (0.33, 0.23, 0.14), seed=123)
    extra = dict(mats)
    extra.update({
        "soil": gba.make_pbr_material("Mat_TilledSoil", (0.30, 0.21, 0.13), tex_set=tex_soil, uv_scale=0.8),
        "soil_dark": gba.make_pbr_material("Mat_SoilDark", (0.20, 0.13, 0.08), roughness=0.95),
        "crop_green": gba.make_pbr_material("Mat_CropGreen", (0.30, 0.55, 0.16), roughness=0.80),
        "berry": gba.make_pbr_material("Mat_BerryRed", (0.76, 0.06, 0.12), roughness=0.22),
        "quarry": gba.make_pbr_material("Mat_QuarryRock", (0.45, 0.44, 0.41), tex_set=tex_quarry, uv_scale=0.55),
        "hide": gba.make_pbr_material("Mat_HideCover", (0.46, 0.34, 0.22), tex_set=tex_hide, uv_scale=0.7),
        "awning_red": gba.make_pbr_material("Mat_AwningRed", (0.72, 0.17, 0.14), roughness=0.82),
        "awning_ochre": gba.make_pbr_material("Mat_AwningOchre", (0.86, 0.62, 0.20), roughness=0.82),
        "awning_green": gba.make_pbr_material("Mat_AwningGreen", (0.20, 0.46, 0.30), roughness=0.82),
        "target_white": gba.make_pbr_material("Mat_TargetWhite", (0.90, 0.87, 0.80), roughness=0.85),
        "target_red": gba.make_pbr_material("Mat_TargetRed", (0.78, 0.12, 0.10), roughness=0.80),
        "rope": gba.make_pbr_material("Mat_Rope", (0.66, 0.55, 0.36), roughness=0.92),
        # Mesmo material de time usado pelos personagens (tintado por time no Godot)
        "team_primary": unit_mats["team_primary"],
    })
    return extra


# ==============================================================================
# PRÉDIOS
# ==============================================================================

def _fence_ring(bm, half, height, post_mat, rail_mat, gap_front=0.0):
    """Cerca de madeira quadrada ao redor do centro (meia largura 'half')."""
    posts = []
    steps = 4
    for i in range(steps + 1):
        t = -half + (2.0 * half) * i / steps
        posts.extend([(t, -half), (t, half), (-half, t), (half, t)])
    seen = set()
    for px, py in posts:
        key = (round(px, 2), round(py, 2))
        if key in seen:
            continue
        seen.add(key)
        if gap_front > 0.0 and abs(py - half) < 0.01 and abs(px) < gap_front:
            continue
        gba.add_cylinder(bm, 0.07, 0.06, height, segments=8, center=(px, py, height * 0.5), mat_idx=post_mat)
    for hz in (height * 0.45, height * 0.82):
        # Trás e laterais completas
        gba.add_beveled_box(bm, half * 2.0, 0.06, 0.07, center=(0.0, -half, hz), bevel_amt=0.01, mat_idx=rail_mat)
        gba.add_beveled_box(bm, 0.06, half * 2.0, 0.07, center=(-half, 0.0, hz), bevel_amt=0.01, mat_idx=rail_mat)
        gba.add_beveled_box(bm, 0.06, half * 2.0, 0.07, center=(half, 0.0, hz), bevel_amt=0.01, mat_idx=rail_mat)
        if gap_front > 0.0:
            seg = half - gap_front
            for sx in (-1.0, 1.0):
                gba.add_beveled_box(bm, seg, 0.06, 0.07, center=(sx * (gap_front + seg * 0.5), half, hz), bevel_amt=0.01, mat_idx=rail_mat)
        else:
            gba.add_beveled_box(bm, half * 2.0, 0.06, 0.07, center=(0.0, half, hz), bevel_amt=0.01, mat_idx=rail_mat)


def build_building_farm(m, col):
    bm = bmesh.new()
    mlist = [m["soil"], m["soil_dark"], m["straw"], m["crop_green"], m["wood_dark"], m["wood"], m["banner_neutral"]]
    # Campo arado
    gba.add_beveled_box(bm, 6.0, 6.0, 0.14, center=(0, 0, 0.07), bevel_amt=0.05, mat_idx=0)
    # Sulcos com plantações (fileiras de trigo dourado alternando com brotos verdes)
    rows = 7
    for i in range(rows):
        x = -2.55 + i * 0.85
        gba.add_beveled_box(bm, 0.50, 5.3, 0.14, center=(x, 0.0, 0.19), bevel_amt=0.05, mat_idx=1)
        crop_mat = 2 if i % 3 != 1 else 3
        h = 0.42 if crop_mat == 2 else 0.24
        gba.add_beveled_box(bm, 0.40, 5.0, h, center=(x, 0.0, 0.26 + h * 0.5), bevel_amt=0.12, mat_idx=crop_mat)
        for j in range(9):
            y = -2.2 + j * 0.55
            gba.add_sphere(bm, 0.17 if crop_mat == 2 else 0.13, subdivisions=1,
                           center=(x + (0.06 if j % 2 else -0.06), y, 0.26 + h + 0.02),
                           scale=(1.0, 1.0, 0.8), mat_idx=crop_mat, noise_amp=0.1, seed=i * 9 + j)
    # Cerca com abertura frontal
    _fence_ring(bm, 3.05, 0.85, 4, 5, gap_front=0.9)
    # Espantalho
    gba.add_cylinder(bm, 0.05, 0.05, 1.7, segments=8, center=(1.6, -1.6, 0.85), mat_idx=4)
    gba.add_cylinder(bm, 0.04, 0.04, 1.0, segments=8, center=(1.6, -1.6, 1.35), rot=(0, HALF_PI, 0), mat_idx=4)
    gba.add_beveled_box(bm, 0.42, 0.22, 0.55, center=(1.6, -1.6, 1.15), bevel_amt=0.04, mat_idx=6)
    gba.add_sphere(bm, 0.17, subdivisions=2, center=(1.6, -1.6, 1.78), mat_idx=2, noise_amp=0.08, seed=3)
    gba.add_cylinder(bm, 0.30, 0.02, 0.32, segments=12, center=(1.6, -1.6, 1.98), mat_idx=2)
    return gba.finalize_mesh("building_farm", bm, mlist, col, split_angle_deg=50.0)


def build_building_mill(m, col):
    bm = bmesh.new()
    mlist = [m["stone_dark"], m["stone"], m["plaster"], m["wood_dark"], m["straw"], m["window_glow"], m["banner_neutral"], m["wood"]]
    gba.add_beveled_box(bm, 4.4, 4.4, 0.32, center=(0, 0, 0.16), bevel_amt=0.07, mat_idx=0)
    # Torre do moinho: pedra embaixo, reboco em cima
    gba.add_cylinder(bm, 1.50, 1.36, 1.85, segments=22, center=(0, 0, 1.25), mat_idx=1)
    gba.add_cylinder(bm, 1.40, 1.42, 0.18, segments=22, center=(0, 0, 2.18), mat_idx=3)
    gba.add_cylinder(bm, 1.32, 1.14, 2.05, segments=22, center=(0, 0, 3.27), mat_idx=2)
    for ang in range(0, 360, 60):
        r = math.radians(ang)
        gba.add_beveled_box(bm, 0.12, 0.12, 2.0, center=(math.cos(r) * 1.23, math.sin(r) * 1.23, 3.25), rot=(0, 0, r), bevel_amt=0.02, mat_idx=3)
    # Capota de palha
    gba.add_cylinder(bm, 1.52, 0.06, 1.65, segments=22, center=(0, 0, 5.12), mat_idx=4)
    # Eixo das pás (as pás giram em código no Godot)
    gba.add_cylinder(bm, 0.14, 0.12, 0.75, segments=12, center=(0, 1.38, 4.05), rot=(HALF_PI, 0, 0), mat_idx=3)
    # Porta, janela iluminada e anexo com sacos de grãos
    gba.add_beveled_box(bm, 0.72, 0.20, 1.20, center=(0, 1.42, 0.92), bevel_amt=0.03, mat_idx=3)
    gba.add_beveled_box(bm, 0.36, 0.16, 0.44, center=(0, 1.22, 3.10), bevel_amt=0.02, mat_idx=5)
    gba.add_beveled_box(bm, 1.5, 1.3, 1.05, center=(1.75, -0.75, 0.84), bevel_amt=0.04, mat_idx=2)
    gba.add_pitched_roof(bm, 1.5, 1.3, 0.62, center=(1.75, -0.75, 1.36), overhang=0.18, mat_idx=4, ridge_mat_idx=3)
    for sx, sy in ((-1.1, 1.65), (-1.55, 1.25), (-1.35, 1.95)):
        gba.add_sphere(bm, 0.30, subdivisions=2, center=(sx, sy, 0.55), scale=(1.0, 0.9, 1.15), mat_idx=6, noise_amp=0.05, seed=7)
    return gba.finalize_mesh("building_mill", bm, mlist, col, split_angle_deg=46.0)


def build_building_lumber_camp(m, col):
    bm = bmesh.new()
    mlist = [m["wood_dark"], m["wood"], m["roof_terracotta"], m["iron"], m["stone_dark"], m["straw"]]
    gba.add_beveled_box(bm, 4.8, 4.2, 0.24, center=(0, 0, 0.12), bevel_amt=0.06, mat_idx=4)
    # Galpão aberto com telhado inclinado
    for px in (-1.9, 1.9):
        for py in (-1.5, 0.5):
            h = 2.7 if py < 0 else 2.2
            gba.add_cylinder(bm, 0.14, 0.13, h, segments=10, center=(px, py, 0.24 + h * 0.5), mat_idx=0)
    gba.add_beveled_box(bm, 4.5, 2.7, 0.16, center=(0, -0.5, 2.78), rot=(-0.22, 0, 0), bevel_amt=0.03, mat_idx=2)
    gba.add_beveled_box(bm, 4.2, 0.18, 1.5, center=(0, -1.55, 1.0), bevel_amt=0.03, mat_idx=1)
    # Pranchas empilhadas sob o galpão
    for k in range(4):
        gba.add_beveled_box(bm, 2.6, 0.9, 0.09, center=(-0.4, -0.7, 0.32 + k * 0.11), rot=(0, 0, 0.02 * k), bevel_amt=0.01, mat_idx=1)
    # Pilha de toras na frente
    log_r = 0.21
    for row, count in enumerate((4, 3, 2)):
        for i in range(count):
            off = (i - (count - 1) * 0.5) * (log_r * 2.05)
            gba.add_cylinder(bm, log_r, log_r, 2.4, segments=12,
                             center=(0.75, 1.3 + off, 0.24 + log_r + row * log_r * 1.75),
                             rot=(0, HALF_PI, 0), mat_idx=0)
    # Toco com machado
    gba.add_cylinder(bm, 0.36, 0.40, 0.55, segments=14, center=(-1.6, 1.4, 0.52), mat_idx=0)
    gba.add_cylinder(bm, 0.03, 0.03, 0.75, segments=8, center=(-1.55, 1.4, 1.02), rot=(0.0, 0.5, 0.0), mat_idx=1)
    gba.add_beveled_box(bm, 0.08, 0.28, 0.18, center=(-1.38, 1.4, 0.80), bevel_amt=0.02, mat_idx=3)
    # Cavalete
    for sx in (-0.5, 0.5):
        gba.add_beveled_box(bm, 0.08, 0.08, 0.8, center=(-0.6 + sx, 0.95, 0.55), rot=(0.35, 0, 0), bevel_amt=0.01, mat_idx=1)
    return gba.finalize_mesh("building_lumber_camp", bm, mlist, col, split_angle_deg=46.0)


def build_building_mining_camp(m, col):
    bm = bmesh.new()
    mlist = [m["stone_dark"], m["wood_dark"], m["roof_slate"], m["plaster"], m["iron"], m["gold"], m["rock"], m["stone"], m["ember_glow"], m["wood"]]
    gba.add_beveled_box(bm, 4.8, 4.2, 0.26, center=(0, 0, 0.13), bevel_amt=0.06, mat_idx=0)
    # Galpão com parede traseira e telhado de ardósia
    gba.add_beveled_box(bm, 3.8, 0.24, 2.1, center=(0, -1.35, 1.31), bevel_amt=0.03, mat_idx=3)
    for px in (-1.85, 1.85):
        for py in (-1.35, 0.55):
            gba.add_cylinder(bm, 0.13, 0.12, 2.3, segments=10, center=(px, py, 1.41), mat_idx=1)
    gba.add_pitched_roof(bm, 4.0, 2.4, 1.05, center=(0, -0.4, 2.55), overhang=0.25, mat_idx=2, ridge_mat_idx=1)
    # Carrinho de mina com ouro e pedra
    gba.add_beveled_box(bm, 1.05, 0.75, 0.45, center=(1.1, 1.3, 0.62), bevel_amt=0.04, mat_idx=1)
    for wx in (0.7, 1.5):
        for wy in (0.95, 1.65):
            gba.add_cylinder(bm, 0.17, 0.17, 0.08, segments=12, center=(wx, wy, 0.42), rot=(0, HALF_PI, 0), mat_idx=4)
    for i, (gx, gy) in enumerate(((0.95, 1.2), (1.25, 1.4), (1.1, 1.5))):
        gba.add_sphere(bm, 0.17, subdivisions=1, center=(gx, gy, 0.92), mat_idx=5 if i != 1 else 6)
    # Pilha de blocos de pedra cortada
    for i, (bx, by, bz) in enumerate(((-1.3, 1.2, 0.42), (-0.75, 1.25, 0.42), (-1.05, 1.15, 0.78))):
        gba.add_beveled_box(bm, 0.5, 0.45, 0.34, center=(bx, by, bz), rot=(0, 0, 0.1 * i), bevel_amt=0.04, mat_idx=7)
    # Pilha de pepitas de ouro e picaretas encostadas
    for i in range(5):
        a = i * 1.26
        gba.add_sphere(bm, 0.16, subdivisions=1, center=(-1.4 + math.cos(a) * 0.25, -0.35 + math.sin(a) * 0.25, 0.38), mat_idx=5)
    for k in range(2):
        gba.add_cylinder(bm, 0.03, 0.03, 1.0, segments=8, center=(0.9 + k * 0.3, -1.05, 0.75), rot=(0.25, 0, 0), mat_idx=9)
        gba.add_beveled_box(bm, 0.55, 0.06, 0.07, center=(0.9 + k * 0.3, -0.93, 1.22), rot=(0, 0, 0.12), bevel_amt=0.015, mat_idx=4)
    # Lanterna
    gba.add_sphere(bm, 0.12, subdivisions=2, center=(1.85, 0.55, 2.1), scale=(0.9, 0.9, 1.3), mat_idx=8)
    return gba.finalize_mesh("building_mining_camp", bm, mlist, col, split_angle_deg=46.0)


def _archery_target(bm, center, mats_idx):
    white, red, wood = mats_idx
    cx, cy, cz = center
    for sx in (-0.38, 0.38):
        gba.add_beveled_box(bm, 0.09, 0.09, 1.25, center=(cx + sx, cy - 0.12, cz - 0.35), rot=(0.22, 0, 0), bevel_amt=0.01, mat_idx=wood)
    rings = [(0.56, white, 0.10), (0.42, red, 0.12), (0.28, white, 0.14), (0.13, red, 0.16)]
    for r, mat_i, d in rings:
        gba.add_cylinder(bm, r, r, d, segments=22, center=(cx, cy + (d - 0.10) * 0.5, cz), rot=(HALF_PI, 0, 0), mat_idx=mat_i)


def build_building_archery_range(m, col):
    bm = bmesh.new()
    mlist = [m["stone_dark"], m["plaster"], m["wood_dark"], m["roof_terracotta"], m["target_white"], m["target_red"], m["straw"], m["wood"], m["window_glow"]]
    gba.add_beveled_box(bm, 5.6, 5.0, 0.28, center=(0, 0, 0.14), bevel_amt=0.06, mat_idx=0)
    # Pavilhão de treino nos fundos
    gba.add_beveled_box(bm, 4.6, 2.0, 1.75, center=(0, -1.3, 1.15), bevel_amt=0.04, mat_idx=1)
    for sx in (-2.3, -0.77, 0.77, 2.3):
        gba.add_beveled_box(bm, 0.16, 2.1, 1.78, center=(sx, -1.3, 1.15), bevel_amt=0.02, mat_idx=2)
    for wx in (-1.5, 1.5):
        gba.add_beveled_box(bm, 0.5, 0.12, 0.5, center=(wx, -0.28, 1.35), bevel_amt=0.02, mat_idx=8)
    gba.add_pitched_roof(bm, 4.7, 2.1, 1.25, center=(0, -1.3, 2.03), overhang=0.3, mat_idx=3, ridge_mat_idx=2)
    # Alvos no pátio
    for tx, ty in ((-1.75, 1.75), (0.0, 2.0), (1.75, 1.75)):
        _archery_target(bm, (tx, ty, 1.05), (4, 5, 2))
    # Fardos de feno e porta-flechas
    gba.add_beveled_box(bm, 0.9, 0.55, 0.5, center=(-2.2, 0.4, 0.53), bevel_amt=0.08, mat_idx=6)
    gba.add_beveled_box(bm, 0.9, 0.55, 0.5, center=(2.2, 0.3, 0.53), bevel_amt=0.08, mat_idx=6)
    gba.add_cylinder(bm, 0.16, 0.13, 0.6, segments=10, center=(1.4, 0.3, 0.58), mat_idx=7)
    for k in range(4):
        gba.add_cylinder(bm, 0.012, 0.012, 0.55, segments=5, center=(1.36 + (k % 2) * 0.07, 0.28 + (k // 2) * 0.06, 0.98), mat_idx=7)
    return gba.finalize_mesh("building_archery_range", bm, mlist, col, split_angle_deg=46.0)


def build_building_siege_workshop(m, col):
    bm = bmesh.new()
    mlist = [m["stone_dark"], m["plaster"], m["wood_dark"], m["roof_slate"], m["wood"], m["iron"], m["rope"]]
    gba.add_beveled_box(bm, 6.4, 5.6, 0.3, center=(0, 0, 0.15), bevel_amt=0.07, mat_idx=0)
    # Galpão grande com frente aberta
    gba.add_beveled_box(bm, 5.8, 0.3, 3.1, center=(0, -2.3, 1.85), bevel_amt=0.04, mat_idx=1)
    for sx in (-2.8, 2.8):
        gba.add_beveled_box(bm, 0.3, 2.6, 3.1, center=(sx, -1.15, 1.85), bevel_amt=0.04, mat_idx=1)
    for px in (-2.8, -0.95, 0.95, 2.8):
        gba.add_beveled_box(bm, 0.22, 0.22, 3.2, center=(px, 0.15, 1.9), bevel_amt=0.02, mat_idx=2)
    gba.add_beveled_box(bm, 6.0, 0.24, 0.3, center=(0, 0.15, 3.4), bevel_amt=0.03, mat_idx=2)
    gba.add_pitched_roof(bm, 6.0, 2.8, 1.5, center=(0, -1.1, 3.4), overhang=0.35, mat_idx=3, ridge_mat_idx=2)
    # Guindaste em A com tora suspensa
    for sx in (-0.55, 0.55):
        gba.add_beveled_box(bm, 0.16, 0.16, 3.6, center=(-2.0 + sx * 0.6, 1.8, 1.9), rot=(0, sx * 0.32, 0), bevel_amt=0.02, mat_idx=4)
    gba.add_beveled_box(bm, 1.3, 0.18, 0.18, center=(-2.0, 1.8, 3.6), bevel_amt=0.02, mat_idx=4)
    gba.add_cylinder(bm, 0.02, 0.02, 1.4, segments=6, center=(-2.0, 1.8, 2.85), mat_idx=6)
    gba.add_cylinder(bm, 0.2, 0.2, 1.8, segments=12, center=(-2.0, 1.8, 2.05), rot=(0, HALF_PI, 0), mat_idx=2)
    # Roda grande de engrenagem com raios
    wc = (1.9, 1.7, 1.05)
    gba.add_cylinder(bm, 0.95, 0.95, 0.14, segments=24, center=wc, rot=(0, HALF_PI, 0), mat_idx=4, cap_ends=False)
    gba.add_cylinder(bm, 0.82, 0.82, 0.16, segments=24, center=wc, rot=(0, HALF_PI, 0), mat_idx=5, cap_ends=False)
    gba.add_cylinder(bm, 0.18, 0.18, 0.3, segments=12, center=wc, rot=(0, HALF_PI, 0), mat_idx=2)
    for k in range(6):
        a = k * math.pi / 6.0
        gba.add_beveled_box(bm, 0.08, 0.08, 1.75, center=wc, rot=(a, 0, 0), bevel_amt=0.01, mat_idx=2)
    # Madeira empilhada
    for k in range(3):
        gba.add_beveled_box(bm, 2.2, 0.32, 0.18, center=(0.2, -1.3, 0.42 + k * 0.2), rot=(0, 0, 0.03 * k), bevel_amt=0.02, mat_idx=4)
    return gba.finalize_mesh("building_siege_workshop", bm, mlist, col, split_angle_deg=46.0)


def _market_stall(bm, center, yaw, awning_mat, wood_mat, goods_mat, goods_mat2):
    cx, cy = center
    rot_m = Matrix.Rotation(yaw, 3, "Z")

    def p(lx, ly, lz):
        v = rot_m @ Vector((lx, ly, 0.0))
        return (cx + v.x, cy + v.y, lz)

    for lx in (-0.85, 0.85):
        for ly in (-0.55, 0.55):
            gba.add_cylinder(bm, 0.06, 0.06, 2.1, segments=8, center=p(lx, ly, 1.05 + 0.2), mat_idx=wood_mat)
    gba.add_beveled_box(bm, 1.9, 0.75, 0.75, center=p(0.0, 0.25, 0.58), rot=(0, 0, yaw), bevel_amt=0.04, mat_idx=wood_mat)
    gba.add_beveled_box(bm, 2.1, 1.5, 0.08, center=p(0.0, 0.05, 2.3), rot=(-0.18, 0, yaw), bevel_amt=0.02, mat_idx=awning_mat)
    for k in range(4):
        gba.add_sphere(bm, 0.13, subdivisions=1, center=p(-0.6 + k * 0.4, 0.3, 1.05), mat_idx=goods_mat if k % 2 == 0 else goods_mat2)


def build_building_market(m, col):
    bm = bmesh.new()
    mlist = [m["stone"], m["stone_dark"], m["wood_dark"], m["wood"], m["awning_red"], m["awning_ochre"], m["awning_green"],
             m["berry"], m["gold_trim"], m["straw"], m["roof_terracotta"]]
    gba.add_beveled_box(bm, 6.2, 6.2, 0.22, center=(0, 0, 0.11), bevel_amt=0.06, mat_idx=0)
    _market_stall(bm, (-1.85, -1.5), 0.6, 4, 2, 7, 8)
    _market_stall(bm, (1.85, -1.5), -0.6, 5, 2, 9, 7)
    _market_stall(bm, (0.0, 2.0), math.pi, 6, 2, 8, 9)
    # Poço central coberto
    gba.add_cylinder(bm, 0.75, 0.80, 0.75, segments=18, center=(0, 0, 0.6), mat_idx=1)
    gba.add_cylinder(bm, 0.55, 0.55, 0.2, segments=18, center=(0, 0, 0.9), mat_idx=2)
    for sx in (-0.65, 0.65):
        gba.add_cylinder(bm, 0.06, 0.06, 1.6, segments=8, center=(sx, 0, 1.6), mat_idx=3)
    gba.add_pitched_roof(bm, 1.6, 1.2, 0.55, center=(0, 0, 2.38), overhang=0.15, mat_idx=10, ridge_mat_idx=2)
    # Barris e caixotes
    for bx, by in ((2.6, 1.0), (2.5, 1.6), (-2.6, 1.2)):
        gba.add_cylinder(bm, 0.26, 0.24, 0.62, segments=14, center=(bx, by, 0.53), mat_idx=3)
    for k, (cx, cy) in enumerate(((-2.5, 0.3), (-2.0, 0.5))):
        gba.add_beveled_box(bm, 0.5, 0.5, 0.5, center=(cx, cy, 0.47), rot=(0, 0, 0.3 * k), bevel_amt=0.03, mat_idx=3)
    return gba.finalize_mesh("building_market", bm, mlist, col, split_angle_deg=46.0)


def build_building_castle(m, col):
    bm = bmesh.new()
    mlist = [m["stone_dark"], m["stone"], m["roof_slate"], m["wood_dark"], m["iron"], m["gold_trim"], m["window_glow"], m["banner_neutral"], m["ember_glow"]]
    base_h = 0.6
    gba.add_beveled_box(bm, 9.8, 9.8, base_h, center=(0, 0, base_h * 0.5), bevel_amt=0.1, mat_idx=0)
    wall_h = 3.4
    wall_z = base_h + wall_h * 0.5
    half = 4.0
    # Muralhas
    gba.add_beveled_box(bm, 8.0, 0.9, wall_h, center=(0, -half, wall_z), bevel_amt=0.05, mat_idx=1)
    gba.add_beveled_box(bm, 0.9, 8.0, wall_h, center=(-half, 0, wall_z), bevel_amt=0.05, mat_idx=1)
    gba.add_beveled_box(bm, 0.9, 8.0, wall_h, center=(half, 0, wall_z), bevel_amt=0.05, mat_idx=1)
    for sx in (-1.0, 1.0):
        gba.add_beveled_box(bm, 2.6, 0.9, wall_h, center=(sx * 2.7, half, wall_z), bevel_amt=0.05, mat_idx=1)
    # Ameias
    top = base_h + wall_h
    for i in range(8):
        t = -3.15 + i * 0.9
        gba.add_beveled_box(bm, 0.5, 0.95, 0.45, center=(t, -half, top + 0.22), bevel_amt=0.03, mat_idx=0)
        gba.add_beveled_box(bm, 0.95, 0.5, 0.45, center=(-half, t, top + 0.22), bevel_amt=0.03, mat_idx=0)
        gba.add_beveled_box(bm, 0.95, 0.5, 0.45, center=(half, t, top + 0.22), bevel_amt=0.03, mat_idx=0)
        if abs(t) > 1.5:
            gba.add_beveled_box(bm, 0.5, 0.95, 0.45, center=(t, half, top + 0.22), bevel_amt=0.03, mat_idx=0)
    # Torres de canto com telhado cônico
    tower_h = 5.4
    for sx in (-half, half):
        for sy in (-half, half):
            gba.add_cylinder(bm, 1.3, 1.18, tower_h, segments=22, center=(sx, sy, base_h + tower_h * 0.5), mat_idx=1)
            gba.add_cylinder(bm, 1.42, 1.42, 0.38, segments=22, center=(sx, sy, base_h + tower_h + 0.1), mat_idx=0)
            gba.add_cylinder(bm, 1.55, 0.05, 2.1, segments=22, center=(sx, sy, base_h + tower_h + 1.3), mat_idx=2)
            gba.add_beveled_box(bm, 0.18, 0.18, 0.48, center=(sx * 1.16, sy * 1.16, base_h + 3.8), bevel_amt=0.02, mat_idx=6)
    # Portaria frontal (+Y) com portão e grade
    gba.add_beveled_box(bm, 2.7, 1.5, 4.3, center=(0, half + 0.1, base_h + 2.15), bevel_amt=0.05, mat_idx=0)
    gba.add_beveled_box(bm, 1.5, 0.35, 2.3, center=(0, half + 0.75, base_h + 1.15), bevel_amt=0.03, mat_idx=3)
    for gx in (-0.5, -0.17, 0.17, 0.5):
        gba.add_cylinder(bm, 0.035, 0.035, 2.2, segments=8, center=(gx, half + 0.95, base_h + 1.12), mat_idx=4)
    for i in range(3):
        gba.add_beveled_box(bm, 0.55, 1.55, 0.42, center=(-0.9 + i * 0.9, half + 0.1, base_h + 4.5), bevel_amt=0.03, mat_idx=1)
    # Torre de menagem central
    keep_h = 6.4
    gba.add_beveled_box(bm, 4.2, 4.2, keep_h, center=(0, 0, base_h + keep_h * 0.5), bevel_amt=0.06, mat_idx=1)
    for sx in (-2.1, 2.1):
        for sy in (-2.1, 2.1):
            gba.add_beveled_box(bm, 0.55, 0.55, keep_h + 0.2, center=(sx, sy, base_h + keep_h * 0.5), bevel_amt=0.04, mat_idx=0)
    for wz in (3.4, 5.2):
        for wx in (-0.9, 0.9):
            gba.add_beveled_box(bm, 0.36, 4.28, 0.62, center=(wx, 0, base_h + wz), bevel_amt=0.02, mat_idx=6)
    gba.add_pitched_roof(bm, 4.0, 4.0, 2.1, center=(0, 0, base_h + keep_h), overhang=0.3, mat_idx=2, ridge_mat_idx=5)
    gba.add_cylinder(bm, 0.07, 0.05, 1.6, segments=10, center=(0, 0, base_h + keep_h + 2.8), mat_idx=5)
    # Braseiros na entrada
    for sx in (-1.7, 1.7):
        gba.add_cylinder(bm, 0.25, 0.32, 0.8, segments=12, center=(sx, half + 1.4, base_h + 0.4), mat_idx=0)
        gba.add_sphere(bm, 0.24, subdivisions=2, center=(sx, half + 1.4, base_h + 0.92), scale=(1.0, 1.0, 0.7), mat_idx=8)
    return gba.finalize_mesh("building_castle", bm, mlist, col, split_angle_deg=44.0)


def build_building_lair(m, col):
    """Covil inimigo: paliçada de toras pontudas, casa comprida, torre de vigia, fogueira e estandartes."""
    bm = bmesh.new()
    mlist = [m["soil_dark"], m["wood_dark"], m["wood"], m["straw"], m["awning_red"], m["ember_glow"],
             m["rock"], m["iron"], m["hide"]]
    # Chão de terra batida
    gba.add_cylinder(bm, 4.7, 4.9, 0.18, segments=28, center=(0, 0, 0.09), mat_idx=0)
    # Paliçada circular com abertura frontal (+Y)
    n_logs = 30
    for i in range(n_logs):
        a = 2.0 * math.pi * i / n_logs
        if abs(math.atan2(math.cos(a), math.sin(a))) < 0.28:
            continue  # portão
        r = 4.05
        h = 2.0 + 0.25 * math.sin(i * 1.7)
        x, y = math.cos(a) * r, math.sin(a) * r
        gba.add_cylinder(bm, 0.19, 0.17, h, segments=8, center=(x, y, h * 0.5), mat_idx=1)
        gba.add_cylinder(bm, 0.17, 0.01, 0.42, segments=8, center=(x, y, h + 0.21), mat_idx=2)
    # Travessas da paliçada
    for hz in (0.7, 1.45):
        for i in range(12):
            a0 = 2.0 * math.pi * i / 12.0
            if abs(math.atan2(math.cos(a0 + 0.26), math.sin(a0 + 0.26))) < 0.45:
                continue
            gba.add_beveled_box(bm, 2.05, 0.08, 0.1, center=(math.cos(a0 + 0.26) * 3.9, math.sin(a0 + 0.26) * 3.9, hz),
                                rot=(0, 0, a0 + 0.26 + HALF_PI), bevel_amt=0.02, mat_idx=2)
    # Casa comprida central com telhado de palha
    gba.add_beveled_box(bm, 3.4, 2.1, 1.5, center=(-0.3, -0.8, 0.93), bevel_amt=0.05, mat_idx=1)
    gba.add_pitched_roof(bm, 2.1, 3.6, 1.35, center=(-0.3, -0.8, 1.68), overhang=0.3, mat_idx=3, ridge_mat_idx=1)
    gba.add_beveled_box(bm, 0.7, 0.18, 1.1, center=(-0.3, 0.28, 0.73), bevel_amt=0.03, mat_idx=2)
    # Torre de vigia de madeira
    tx, ty = 2.35, -2.05
    for sx in (-0.45, 0.45):
        for sy in (-0.45, 0.45):
            gba.add_cylinder(bm, 0.1, 0.09, 3.6, segments=8, center=(tx + sx, ty + sy, 1.8), mat_idx=1)
    gba.add_beveled_box(bm, 1.35, 1.35, 0.14, center=(tx, ty, 3.2), bevel_amt=0.02, mat_idx=2)
    gba.add_beveled_box(bm, 1.35, 0.08, 0.5, center=(tx, ty + 0.64, 3.5), bevel_amt=0.01, mat_idx=1)
    gba.add_beveled_box(bm, 1.35, 0.08, 0.5, center=(tx, ty - 0.64, 3.5), bevel_amt=0.01, mat_idx=1)
    gba.add_cylinder(bm, 1.05, 0.05, 0.9, segments=4, center=(tx, ty, 4.25), rot=(0, 0, math.pi * 0.25), mat_idx=8)
    # Fogueira com pedras
    for i in range(8):
        a = 2.0 * math.pi * i / 8.0
        gba.add_sphere(bm, 0.16, subdivisions=1, center=(1.4 + math.cos(a) * 0.5, 1.5 + math.sin(a) * 0.5, 0.2), mat_idx=6)
    gba.add_sphere(bm, 0.32, subdivisions=2, center=(1.4, 1.5, 0.32), scale=(1.0, 1.0, 1.3), mat_idx=5)
    # Estandartes vermelhos e armas encostadas
    for bx, by in ((-2.2, 2.6), (2.2, 2.6), (-2.6, -2.4)):
        gba.add_cylinder(bm, 0.05, 0.04, 3.0, segments=8, center=(bx, by, 1.5), mat_idx=1)
        gba.add_beveled_box(bm, 0.05, 0.7, 1.0, center=(bx, by + 0.36, 2.45), bevel_amt=0.01, mat_idx=4)
    for k in range(5):
        gba.add_cylinder(bm, 0.025, 0.025, 1.7, segments=6, center=(-2.0 + k * 0.18, 0.7, 0.85), rot=(0.18, 0.0, 0.0), mat_idx=2)
        gba.add_cylinder(bm, 0.05, 0.005, 0.22, segments=6, center=(-2.0 + k * 0.18, 0.86, 1.71), rot=(0.18, 0.0, 0.0), mat_idx=7)
    # Peles esticadas e caixotes
    gba.add_beveled_box(bm, 0.9, 0.06, 0.8, center=(-2.7, -0.4, 0.75), rot=(0, 0, 0.6), bevel_amt=0.01, mat_idx=8)
    gba.add_beveled_box(bm, 0.55, 0.55, 0.5, center=(0.9, -2.7, 0.43), rot=(0, 0, 0.3), bevel_amt=0.03, mat_idx=2)
    return gba.finalize_mesh("building_lair", bm, mlist, col, split_angle_deg=46.0)


# ==============================================================================
# RECURSOS
# ==============================================================================

def build_resource_berry_bush(m, col):
    bm = bmesh.new()
    mlist = [m["wood_dark"], m["foliage_1"], m["foliage_2"], m["foliage_3"], m["berry"]]
    # Ramos lenhosos na base
    for ang in (0.0, 1.3, 2.6, 4.1, 5.3):
        gba.add_cylinder(bm, 0.05, 0.02, 0.48, segments=6,
                         center=(math.cos(ang) * 0.22, math.sin(ang) * 0.22, 0.22),
                         rot=(math.sin(ang) * 0.45, -math.cos(ang) * 0.45, 0), mat_idx=0)
    # 16 tufos folhosos recortados em camadas (silhueta silvestre natural, zero esferas lisas)
    for i in range(8):
        a = (2.0 * math.pi * i) / 8.0 + 0.15 * (i % 2)
        gba.add_foliage_cluster(bm, 0.36 + (i % 2) * 0.05, subdivisions=2,
                                center=(math.cos(a) * 0.44, math.sin(a) * 0.42, 0.40 + (i % 2) * 0.08),
                                scale=(1.18, 1.05, 0.62), rot=(0.1, -0.1, a),
                                mat_idx=1 if i % 2 == 0 else 2, seed=70 + i)
    for i in range(6):
        a = (2.0 * math.pi * i) / 6.0 + 0.4
        gba.add_foliage_cluster(bm, 0.34, subdivisions=2,
                                center=(math.cos(a) * 0.26, math.sin(a) * 0.25, 0.64 + (i % 2) * 0.06),
                                scale=(1.12, 1.04, 0.60), rot=(0.0, 0.12, a * 1.4),
                                mat_idx=2 if i % 3 == 0 else 3, seed=82 + i)
    gba.add_foliage_cluster(bm, 0.40, subdivisions=2, center=(0.0, 0.0, 0.78), scale=(1.15, 1.08, 0.68), mat_idx=3, seed=89)
    # 9 cachos agrupados (3 frutinhas por cacho) aninhados entre a folhagem
    bunch_centers = [
        (0.48, 0.32, 0.56), (-0.46, 0.34, 0.54), (0.36, -0.45, 0.52), (-0.42, -0.36, 0.56),
        (0.0, 0.56, 0.52), (0.18, 0.12, 0.90), (-0.24, 0.18, 0.84), (0.15, -0.26, 0.82), (0.56, -0.05, 0.48),
    ]
    for bi, (bx, by, bz) in enumerate(bunch_centers):
        for k in range(3):
            ka = bi * 1.7 + k * 2.1
            ox = math.cos(ka) * 0.065
            oy = math.sin(ka) * 0.065
            oz = (k - 1) * 0.035
            gba.add_sphere(bm, 0.055 if k != 1 else 0.062, subdivisions=1, center=(bx + ox, by + oy, bz + oz), mat_idx=4)
    return gba.finalize_mesh("resource_berry_bush", bm, mlist, col, split_angle_deg=92.0)


def build_resource_stone_quarry(m, col):
    bm = bmesh.new()
    tex_dark_quarry = gba.generate_pbr_texture_set("QuarryGraniteDark", "rock_strata", (0.34, 0.34, 0.33), (0.19, 0.19, 0.18), seed=129)
    granite = gba.make_pbr_material("Mat_GraniteQuarryDark", (0.30, 0.30, 0.29), tex_set=tex_dark_quarry, uv_scale=0.60)
    mlist = [m["quarry"], granite, m["stone"], m["wood_dark"], m["iron"], m["wood"], m["rope"]]
    # Maciço rochoso angular em degraus de extração (split_angle_deg=22 para facetas bem marcadas sem brilho liso)
    gba.add_craggy_rock(bm, 1.78, subdivisions=2, center=(0.0, -0.38, 0.84), scale=(1.18, 0.96, 0.72), rot=(0.05, -0.08, 0.3), mat_idx=0, seed=81)
    gba.add_craggy_rock(bm, 1.22, subdivisions=2, center=(-0.98, -0.24, 1.12), scale=(1.02, 0.92, 0.92), rot=(0.2, 0.1, -0.4), mat_idx=1, seed=82)
    gba.add_craggy_rock(bm, 1.08, subdivisions=2, center=(1.02, -0.52, 1.02), scale=(0.95, 1.02, 0.88), rot=(-0.15, 0.2, 0.6), mat_idx=0, seed=83)
    # Lascas angulares e cascalho de pedreira ao redor
    for i in range(6):
        a = i * 1.08 + 0.2
        gba.add_craggy_rock(bm, 0.24 + 0.05 * (i % 2), subdivisions=1,
                            center=(0.65 + math.cos(a) * 0.65, 1.38 + math.sin(a) * 0.42, 0.16),
                            scale=(1.2, 0.9, 0.6), rot=(0.1, 0.2, a), mat_idx=1, seed=85 + i)
    # Frente de lavra em degraus cinzelados + blocos também visíveis na face Sul (-Y)
    gba.add_beveled_box(bm, 1.55, 0.78, 0.85, center=(0.08, 0.56, 0.43), bevel_amt=0.04, mat_idx=0)
    gba.add_beveled_box(bm, 1.15, 0.68, 0.56, center=(0.0, 0.18, 1.02), bevel_amt=0.04, mat_idx=1)
    gba.add_beveled_box(bm, 0.62, 0.48, 0.44, center=(0.82, -1.48, 0.22), rot=(0, 0, 0.22), bevel_amt=0.03, mat_idx=2)
    gba.add_beveled_box(bm, 0.54, 0.46, 0.40, center=(-0.78, -1.42, 0.20), rot=(0, 0, -0.18), bevel_amt=0.03, mat_idx=1)
    # Estrado de madeira + blocos de cantaria empilhados
    gba.add_beveled_box(bm, 1.35, 0.95, 0.08, center=(-0.95, 1.42, 0.04), rot=(0, 0, 0.08), bevel_amt=0.01, mat_idx=5)
    blocks = [((-1.25, 1.35, 0.29), 0.15), ((-0.65, 1.52, 0.29), -0.2), ((-0.95, 1.40, 0.75), 0.05), ((1.28, 1.24, 0.24), 0.38)]
    for (bx, by, bz), yaw in blocks:
        gba.add_beveled_box(bm, 0.56, 0.46, 0.44, center=(bx, by, bz), rot=(0, 0, yaw), bevel_amt=0.03, mat_idx=2)
    # Pequeno guindaste / tripé de madeira sobre a frente da pedreira
    for lx, ly, rx, ry in ((-0.45, 0.95, -0.25, 0.35), (0.65, 0.95, -0.25, -0.35), (0.10, 1.65, 0.35, 0.0)):
        gba.add_cylinder(bm, 0.045, 0.04, 1.65, segments=8, center=(lx, ly, 0.78), rot=(rx, ry, 0), mat_idx=3)
    gba.add_cylinder(bm, 0.015, 0.015, 0.75, segments=6, center=(0.10, 1.12, 1.12), mat_idx=6)
    gba.add_beveled_box(bm, 0.36, 0.32, 0.28, center=(0.10, 1.12, 0.72), bevel_amt=0.02, mat_idx=2)
    # Marreta e cinzel apoiados
    gba.add_cylinder(bm, 0.03, 0.03, 0.9, segments=8, center=(1.75, 0.7, 0.42), rot=(0.0, 0.85, 0.0), mat_idx=3)
    gba.add_beveled_box(bm, 0.14, 0.14, 0.26, center=(2.05, 0.7, 0.13), bevel_amt=0.02, mat_idx=4)
    return gba.finalize_mesh("resource_stone_quarry", bm, mlist, col, split_angle_deg=22.0)


# ==============================================================================
# ARÍETE (unidade de cerco estática, sem esqueleto)
# ==============================================================================

def build_unit_ram(m, col):
    bm = bmesh.new()
    mlist = [m["wood_dark"], m["wood"], m["hide"], m["iron"], m["steel"], m["team_primary"], m["gold_trim"]]
    # Chassi
    for sx in (-0.72, 0.72):
        gba.add_beveled_box(bm, 0.2, 3.1, 0.22, center=(sx, 0.0, 0.62), bevel_amt=0.03, mat_idx=0)
    for sy in (-1.2, 0.0, 1.2):
        gba.add_beveled_box(bm, 1.6, 0.18, 0.18, center=(0.0, sy, 0.62), bevel_amt=0.03, mat_idx=0)
    # Rodas
    for sx in (-0.92, 0.92):
        for sy in (-1.0, 1.0):
            gba.add_cylinder(bm, 0.42, 0.42, 0.16, segments=18, center=(sx, sy, 0.42), rot=(0, HALF_PI, 0), mat_idx=1)
            gba.add_cylinder(bm, 0.44, 0.44, 0.08, segments=18, center=(sx * 1.02, sy, 0.42), rot=(0, HALF_PI, 0), mat_idx=3, cap_ends=False)
            gba.add_cylinder(bm, 0.1, 0.1, 0.22, segments=10, center=(sx, sy, 0.42), rot=(0, HALF_PI, 0), mat_idx=3)
    # Postes e telhado de couro
    for sx in (-0.72, 0.72):
        for sy in (-1.3, 1.3):
            gba.add_beveled_box(bm, 0.14, 0.14, 0.95, center=(sx, sy, 1.12), bevel_amt=0.02, mat_idx=0)
    gba.add_pitched_roof(bm, 1.7, 2.9, 0.85, center=(0.0, 0.0, 1.58), overhang=0.22, mat_idx=2, ridge_mat_idx=0)
    # Tora do aríete com ponta de ferro
    gba.add_cylinder(bm, 0.2, 0.2, 3.3, segments=14, center=(0.0, 0.35, 1.0), rot=(HALF_PI, 0, 0), mat_idx=1)
    gba.add_cylinder(bm, 0.27, 0.12, 0.45, segments=14, center=(0.0, 2.15, 1.0), rot=(-HALF_PI, 0, 0), mat_idx=4)
    for sy in (-0.6, 0.6):
        gba.add_cylinder(bm, 0.015, 0.015, 0.6, segments=6, center=(0.0, sy, 1.32), mat_idx=0)
    # Estandarte do time
    gba.add_cylinder(bm, 0.035, 0.035, 1.3, segments=8, center=(0.55, -1.45, 2.1), mat_idx=6)
    gba.add_beveled_box(bm, 0.05, 0.55, 0.38, center=(0.55, -1.2, 2.52), bevel_amt=0.01, mat_idx=5)
    gba.add_beveled_box(bm, 1.75, 0.08, 0.28, center=(0.0, 1.5, 1.32), bevel_amt=0.02, mat_idx=5)
    return gba.finalize_mesh("unit_ram", bm, mlist, col, split_angle_deg=46.0)


# ==============================================================================
# PERSONAGENS COM ESQUELETO: LANCEIRO E BATEDOR
# ==============================================================================

def build_unit_spearman(mats, col):
    BI = gua.BONE_IDX
    spec = {
        "hips_z": 0.75, "spine_z": 0.93, "chest_z": 1.13, "neck_z": 1.31, "head_top_z": 1.70,
        "sh_pt_l": Vector((-0.26, 0.0, 1.25)),
        "elb_pt_l": Vector((-0.36, 0.04, 0.99)),
        "hand_pt_l": Vector((-0.39, 0.14, 0.77)),
        "leg_x": 0.135, "knee_z": 0.44, "ankle_z": 0.12,
        "cape_y": -0.19, "cape_top_z": 1.22, "cape_mid_z": 0.92, "cape_bot_z": 0.62,
    }
    arm_obj = gua.create_character_armature("unit_spearman", spec, col)
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    mlist = [
        mats["skin"],          # 0
        mats["hair"],          # 1
        mats["eye"],           # 2
        mats["team_primary"],  # 3
        mats["leather"],       # 4
        mats["dark_leather"],  # 5
        mats["steel"],         # 6
        mats["iron"],          # 7
        mats["wood"],          # 8
        mats["trousers"],      # 9
        mats["gold_trim"],     # 10
        mats["team_accent"],   # 11
    ]
    gua.add_boot_pair(bm, deform, spec["leg_x"], 0.33, 0.096, 5, 4,
                      BI["Foot.L"], BI["Foot.R"], BI["Shin.L"], BI["Shin.R"])
    gua.add_leg_tubes(bm, deform, spec["leg_x"], spec["ankle_z"] + 0.16, spec["knee_z"], spec["hips_z"],
                      0.092, 0.118, 9, 9,
                      BI["Shin.L"], BI["Thigh.L"], BI["Shin.R"], BI["Thigh.R"], BI["Hips"])
    # Gibão acolchoado (cor do time) com saia
    tw = gua._torso_weights_fn(spec["hips_z"], spec["spine_z"], spec["chest_z"], spec["neck_z"])
    gambeson = [
        (0.54, 0.27, 0.21, 0.0, 0.0),
        (0.70, 0.25, 0.19, 0.0, 0.0),
        (0.88, 0.235, 0.178, 0.0, 0.0),
        (1.06, 0.272, 0.205, 0.0, 0.012),
        (1.22, 0.262, 0.198, 0.0, 0.006),
        (1.31, 0.15, 0.135, 0.0, 0.0),
    ]
    gua.add_loft(bm, deform, gambeson, segments=18, mat_idx=3, weights_fn=tw)
    # Faixas de costura acolchoada
    for z in (0.66, 0.84, 1.0, 1.16):
        gua.add_cylinder(bm, deform, 0.262 if z > 0.95 else 0.245, 0.262 if z > 0.95 else 0.245, 0.018, segments=18,
                         center=(0.0, 0.0, z), scale=(1.02, 0.80, 1.0), mat_idx=5,
                         weights=BI["Chest"] if z > 1.0 else (BI["Spine"] if z > 0.8 else BI["Hips"]))
    # Cinto e alça
    gua.add_cylinder(bm, deform, 0.25, 0.25, 0.08, segments=18, center=(0.0, 0.0, 0.77),
                     scale=(1.04, 0.84, 1.0), mat_idx=4, weights=BI["Hips"])
    gua.add_beveled_box(bm, deform, 0.08, 0.04, 0.09, center=(0.0, 0.215, 0.77), bevel_amt=0.012, mat_idx=10, weights=BI["Hips"])
    gua.add_cylinder(bm, deform, 0.035, 0.035, 0.6, segments=8, center=(0.0, 0.0, 1.05),
                     rot=(0.0, -0.6, 0.0), scale=(1.0, 5.2, 1.0), mat_idx=5, weights=BI["Chest"])
    # Braços: mangas acolchoadas, braçadeiras de couro
    gua.add_arm_pair(bm, deform, spec["sh_pt_l"], spec["elb_pt_l"], spec["hand_pt_l"], 0.086, 0.074, 3, 4, 0)
    # Cabeça + chapéu de ferro (kettle hat)
    gua.add_sculpted_head(bm, deform, (0.0, 0.01, 1.45), (0.94, 0.96, 1.0),
                          skin_mat=0, hair_mat=1, eye_mat=2, bone_idx=BI["Head"], with_beard=True, with_hair=True)
    gua.add_cylinder(bm, deform, 0.285, 0.275, 0.028, segments=22, center=(0.0, 0.0, 1.585),
                     mat_idx=6, weights=BI["Head"])
    hat = [
        (1.585, 0.185, 0.195, 0.0, 0.0),
        (1.66, 0.178, 0.188, 0.0, 0.0),
        (1.72, 0.13, 0.138, 0.0, 0.0),
        (1.755, 0.05, 0.055, 0.0, 0.0),
    ]
    gua.add_loft(bm, deform, hat, segments=18, mat_idx=6, weights_fn=lambda *_: BI["Head"])
    gua.add_cylinder(bm, deform, 0.19, 0.19, 0.03, segments=18, center=(0.0, 0.0, 1.61), mat_idx=11, weights=BI["Head"])
    # Escudo redondo na mão esquerda
    hl = spec["hand_pt_l"]
    sc = Vector((hl.x - 0.11, hl.y + 0.03, hl.z + 0.05))
    s_rot = (0.0, HALF_PI, 0.12)
    gua.add_cylinder(bm, deform, 0.29, 0.29, 0.034, segments=22, center=sc, rot=s_rot, mat_idx=7, weights=BI["Hand.L"])
    gua.add_cylinder(bm, deform, 0.27, 0.27, 0.05, segments=22, center=sc + Vector((-0.004, 0.0, 0.0)), rot=s_rot, mat_idx=3, weights=BI["Hand.L"])
    gua.add_sphere(bm, deform, 0.07, subdivisions=2, center=sc + Vector((-0.04, 0.0, 0.0)), scale=(0.6, 1.0, 1.0), mat_idx=6, weights=BI["Hand.L"])
    # Lança longa na mão direita
    hr = Vector((-hl.x, hl.y, hl.z))
    sp_rot = (-0.30, 0.0, 0.0)
    sp_dir = Euler(sp_rot, "XYZ").to_matrix() @ Vector((0.0, 0.0, 1.0))
    shaft_len = 2.3
    gua.add_cylinder(bm, deform, 0.022, 0.02, shaft_len, segments=10,
                     center=hr + sp_dir * (shaft_len * 0.5 - 0.62), rot=sp_rot, mat_idx=8, weights=BI["Hand.R"])
    gua.add_blade_diamond(bm, deform, length=0.30, base_w=0.075, tip_w=0.012, thick=0.026,
                          center=hr + sp_dir * (shaft_len - 0.62), rot=sp_rot, mat_idx=6, bone_idx=BI["Hand.R"])
    gua.add_cylinder(bm, deform, 0.03, 0.026, 0.07, segments=10,
                     center=hr + sp_dir * (shaft_len - 0.64), rot=sp_rot, mat_idx=7, weights=BI["Hand.R"])
    gua.add_cylinder(bm, deform, 0.026, 0.026, 0.06, segments=10,
                     center=hr + sp_dir * -0.6, rot=sp_rot, mat_idx=7, weights=BI["Hand.R"])

    mesh_obj = gua.finalize_rigged_mesh("unit_spearman", bm, mlist, col, arm_obj, split_angle_deg=52.0)
    gua.build_unit_animations(arm_obj, "soldier", spec)
    return arm_obj, mesh_obj


def build_unit_scout(mats, col):
    BI = gua.BONE_IDX
    spec = {
        "hips_z": 0.74, "spine_z": 0.92, "chest_z": 1.11, "neck_z": 1.29, "head_top_z": 1.64,
        "sh_pt_l": Vector((-0.23, 0.0, 1.23)),
        "elb_pt_l": Vector((-0.31, 0.04, 0.98)),
        "hand_pt_l": Vector((-0.34, 0.14, 0.76)),
        "leg_x": 0.125, "knee_z": 0.43, "ankle_z": 0.12,
        "cape_y": -0.17, "cape_top_z": 1.24, "cape_mid_z": 0.90, "cape_bot_z": 0.55,
    }
    arm_obj = gua.create_character_armature("unit_scout", spec, col)
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    mlist = [
        mats["skin"],          # 0
        mats["hair"],          # 1
        mats["eye"],           # 2
        mats["leather"],       # 3
        mats["dark_leather"],  # 4
        mats["trousers"],      # 5
        mats["steel"],         # 6
        mats["gold_trim"],     # 7
        mats["team_primary"],  # 8
        mats["team_cape"],     # 9
        mats["team_accent"],   # 10
        mats["tunic_cloth"],   # 11
        mats["wood"],          # 12
    ]
    gua.add_boot_pair(bm, deform, spec["leg_x"], 0.36, 0.088, 4, 7,
                      BI["Foot.L"], BI["Foot.R"], BI["Shin.L"], BI["Shin.R"])
    gua.add_leg_tubes(bm, deform, spec["leg_x"], spec["ankle_z"] + 0.15, spec["knee_z"], spec["hips_z"],
                      0.082, 0.104, 5, 5,
                      BI["Shin.L"], BI["Thigh.L"], BI["Shin.R"], BI["Thigh.R"], BI["Hips"])
    tw = gua._torso_weights_fn(spec["hips_z"], spec["spine_z"], spec["chest_z"], spec["neck_z"])
    jerkin = [
        (0.56, 0.235, 0.185, 0.0, 0.0),
        (0.74, 0.21, 0.165, 0.0, 0.0),
        (0.92, 0.20, 0.155, 0.0, 0.0),
        (1.12, 0.24, 0.18, 0.0, 0.01),
        (1.26, 0.21, 0.158, 0.0, 0.0),
        (1.31, 0.12, 0.118, 0.0, 0.0),
    ]
    gua.add_loft(bm, deform, jerkin, segments=18, mat_idx=3, weights_fn=tw)
    # Tabardo estreito com a cor do time + cinto com trompa
    gua.add_tabard_panel(bm, deform, 0.17, 0.21, 1.22, 0.48, 0.17, True, 8, 7, thickness=0.02)
    gua.add_cylinder(bm, deform, 0.22, 0.22, 0.08, segments=18, center=(0.0, 0.0, 0.75),
                     scale=(1.02, 0.84, 1.0), mat_idx=4, weights=BI["Hips"])
    horn_pts = [
        (Vector((0.20, 0.06, 0.70)), 0.012, 0.012),
        (Vector((0.25, 0.02, 0.64)), 0.026, 0.026),
        (Vector((0.27, -0.06, 0.60)), 0.038, 0.038),
        (Vector((0.25, -0.14, 0.62)), 0.05, 0.05),
    ]
    gua.add_limb_chain(bm, deform, horn_pts, segments=10, mat_idx=11, weights_fn=lambda *_: BI["Hips"])
    gua.add_cylinder(bm, deform, 0.054, 0.054, 0.025, segments=12, center=(0.25, -0.145, 0.62),
                     rot=(HALF_PI, 0.0, 0.0), mat_idx=7, weights=BI["Hips"])
    # Manto curto do time e capuz de couro
    gua.add_flowing_cape(bm, deform, 0.42, 0.58, 1.24, 0.55, -0.17, 0.2, 9, border_mat_idx=8)
    gua.add_arm_pair(bm, deform, spec["sh_pt_l"], spec["elb_pt_l"], spec["hand_pt_l"], 0.074, 0.064, 3, 4, 0)
    gua.add_sculpted_head(bm, deform, (0.0, 0.01, 1.43), (0.94, 0.96, 1.0),
                          skin_mat=0, hair_mat=1, eye_mat=2, bone_idx=BI["Head"], with_hair=False)
    hood = [
        (1.30, 0.17, 0.182, 0.0, -0.03),
        (1.44, 0.19, 0.202, 0.0, -0.03),
        (1.58, 0.182, 0.208, 0.0, -0.025),
        (1.65, 0.13, 0.185, 0.0, -0.07),
        (1.60, 0.04, 0.07, 0.0, -0.24),
    ]
    gua.add_loft(bm, deform, hood, segments=16, mat_idx=5, weights_fn=lambda *_: BI["Head"])
    scarf = [
        (1.25, 0.15, 0.15, 0.0, 0.0),
        (1.31, 0.165, 0.165, 0.0, 0.01),
        (1.35, 0.14, 0.14, 0.0, 0.0),
    ]
    gua.add_loft(bm, deform, scarf, segments=16, mat_idx=10, weights_fn=lambda *_: BI["Chest"])
    # Espada curta na mão direita
    hl = spec["hand_pt_l"]
    hr = Vector((-hl.x, hl.y, hl.z))
    sw_rot = (-1.0, 0.0, 0.0)
    sw_x = Matrix.Translation(hr) @ Euler(sw_rot, "XYZ").to_matrix().to_4x4()
    gua.add_cylinder(bm, deform, 0.022, 0.02, 0.16, segments=10, center=sw_x @ Vector((0.0, 0.0, 0.02)),
                     rot=sw_rot, mat_idx=4, weights=BI["Hand.R"])
    gua.add_beveled_box(bm, deform, 0.03, 0.19, 0.032, center=sw_x @ Vector((0.0, 0.0, 0.11)), rot=sw_rot,
                        bevel_amt=0.008, mat_idx=7, weights=BI["Hand.R"])
    gua.add_blade_diamond(bm, deform, length=0.56, base_w=0.065, tip_w=0.026, thick=0.022,
                          center=sw_x @ Vector((0.0, 0.0, 0.13)), rot=sw_rot, mat_idx=6, bone_idx=BI["Hand.R"])
    # Adaga na bainha da cintura esquerda
    gua.add_cylinder(bm, deform, 0.024, 0.016, 0.34, segments=8, center=(-0.24, 0.05, 0.66),
                     rot=(0.4, 0.2, 0.0), mat_idx=4, weights=BI["Hips"])

    mesh_obj = gua.finalize_rigged_mesh("unit_scout", bm, mlist, col, arm_obj, split_angle_deg=54.0)
    gua.build_unit_animations(arm_obj, "soldier", spec)
    return arm_obj, mesh_obj


# ==============================================================================
# PREVIEW
# ==============================================================================

def render_preview(static_objs, units, unit_mats, out_path):
    gua._tint_preview_team_materials(unit_mats)
    col = gba.get_or_create_collection("ExpansionShowcase")
    bm = bmesh.new()
    gba.add_beveled_box(bm, 60.0, 30.0, 0.5, center=(6.0, 3.0, -0.25), bevel_amt=0.05, mat_idx=0)
    floor_mat = gba.make_pbr_material("Mat_ExpansionFloor", (0.16, 0.24, 0.14), roughness=0.9)
    gba.finalize_mesh("Expansion_Floor", bm, [floor_mat], col)

    row_back = ["building_castle", "building_lair", "building_siege_workshop", "building_market", "building_archery_range"]
    row_front = ["building_mill", "building_lumber_camp", "building_mining_camp", "building_farm",
                 "resource_stone_quarry", "resource_berry_bush", "unit_ram"]
    by_name = {o.name: o for o in static_objs}
    x = -14.0
    for name in row_back:
        o = by_name.get(name)
        if o is None:
            continue
        w = 11.0 if name == "building_castle" else 8.0
        o.location = (x + w * 0.5, 10.0, 0.0)
        o.rotation_euler = Euler((0.0, 0.0, math.pi), "XYZ")
        x += w
    x = -16.0
    for name in row_front:
        o = by_name.get(name)
        if o is None:
            continue
        w = 6.2 if name.startswith("building") else 4.4
        o.location = (x + w * 0.5, -0.5, 0.0)
        o.rotation_euler = Euler((0.0, 0.0, math.pi), "XYZ")
        x += w
    for i, (arm_obj, _mesh) in enumerate(units):
        arm_obj.location = (19.0 + i * 1.8, -6.0, 0.0)
        arm_obj.rotation_euler = Euler((0.0, 0.0, math.pi), "XYZ")
        arm_obj.scale = (2.2, 2.2, 2.2)
        gua._evaluate_nla_pose(arm_obj, "Idle", 15)

    world = bpy.data.worlds.new("ExpansionWorld")
    bpy.context.scene.world = world
    if hasattr(world, "use_nodes"):
        world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs[0].default_value = (0.36, 0.50, 0.72, 1.0)
        bg.inputs[1].default_value = 1.0

    sun_data = bpy.data.lights.new("ExpSun", type="SUN")
    sun_data.energy = 3.4
    sun_obj = bpy.data.objects.new("ExpSun", sun_data)
    sun_obj.rotation_euler = Euler((math.radians(48), math.radians(12), math.radians(-32)), "XYZ")
    col.objects.link(sun_obj)

    cam_data = bpy.data.cameras.new("ExpCam")
    cam_data.lens = 30.0
    cam_obj = bpy.data.objects.new("ExpCam", cam_data)
    col.objects.link(cam_obj)
    cam_obj.location = (6.0, -30.0, 19.0)
    cam_obj.rotation_euler = (Vector((6.0, 4.5, 1.5)) - cam_obj.location).to_track_quat("-Z", "Y").to_euler()

    scene = bpy.context.scene
    scene.camera = cam_obj
    gba.set_eevee_engine(scene)
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    print(f"[Expansion] Rendered preview: {out_path}")


def main():
    gba.clear_scene()
    # Materiais de personagem primeiro: o aríete reaproveita Mat_TeamPrimary texturizado.
    unit_mats = gua.create_character_materials()
    mats = create_extra_materials(gba.create_materials(), unit_mats)
    col = gba.get_or_create_collection("RTS_Expansion")

    static_builders = [
        ("building_farm", build_building_farm),
        ("building_mill", build_building_mill),
        ("building_lumber_camp", build_building_lumber_camp),
        ("building_mining_camp", build_building_mining_camp),
        ("building_archery_range", build_building_archery_range),
        ("building_siege_workshop", build_building_siege_workshop),
        ("building_market", build_building_market),
        ("building_castle", build_building_castle),
        ("building_lair", build_building_lair),
        ("resource_berry_bush", build_resource_berry_bush),
        ("resource_stone_quarry", build_resource_stone_quarry),
        ("unit_ram", build_unit_ram),
    ]
    only = os.environ.get("EXPANSION_ONLY", "").strip()
    static_objs = []
    for name, fn in static_builders:
        if only and name not in only.split(","):
            continue
        obj = fn(mats, col)
        gba.export_glb(obj, os.path.join(MODELS_DIR, f"{name}.glb"))
        static_objs.append(obj)

    unit_builders = [
        ("unit_spearman", build_unit_spearman),
        ("unit_scout", build_unit_scout),
    ]
    units = []
    for name, fn in unit_builders:
        if only and name not in only.split(","):
            continue
        arm_obj, mesh_obj = fn(unit_mats, col)
        gua.export_unit_glb(arm_obj, mesh_obj, os.path.join(MODELS_DIR, f"{name}.glb"))
        units.append((arm_obj, mesh_obj))

    preview_path = os.environ.get("EXPANSION_PREVIEW", os.path.join(BLENDER_DIR, "expansion_assets_preview.png"))
    if preview_path.lower() != "none":
        render_preview(static_objs, units, unit_mats, preview_path)
    print("[Expansion] ALL EXPANSION ASSETS GENERATED SUCCESSFULLY.")


if __name__ == "__main__":
    main()
