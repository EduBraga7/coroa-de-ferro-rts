"""
Gerador procedural de personagens 3D de alta fidelidade (PBR 512x512 + Esqueleto Humanoide + Animações NLA)
para o RTS 'Coroa de Ferro: Crônicas da Fronteira'.
Executado em Blender 5.2+ em modo headless (-b -P).

Unidades geradas em assets/models/:
  - unit_worker.glb   (Camponês)
  - unit_soldier.glb  (Espadachim)
  - unit_archer.glb   (Arqueiro)
  - unit_knight.glb   (Paladino Real)

Convenções:
  - Frente no Blender: +Y (export_yup=True -> Godot -Z, alinhado a RTSUnit._face_point)
  - Direita do personagem: +X (.R), Esquerda: -X (.L), Cima: +Z, Sola dos pés em Z = 0.0
  - Materiais de time: Mat_TeamPrimary, Mat_TeamCape, Mat_TeamAccent (tintados por time no Godot)
"""

import math
import os
import bpy
import bmesh
import numpy as np
from mathutils import Vector, Matrix, Euler


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
MODELS_DIR = os.path.join(PROJECT_DIR, "assets", "models")
BLENDER_DIR = os.path.join(PROJECT_DIR, "assets", "blender")

os.makedirs(MODELS_DIR, exist_ok=True)
os.makedirs(BLENDER_DIR, exist_ok=True)

BONE_NAMES = [
    "Root",
    "Hips",
    "Spine",
    "Chest",
    "Head",
    "Shoulder.L",
    "UpperArm.L",
    "Forearm.L",
    "Hand.L",
    "Shoulder.R",
    "UpperArm.R",
    "Forearm.R",
    "Hand.R",
    "Cape.1",
    "Cape.2",
    "Thigh.L",
    "Shin.L",
    "Foot.L",
    "Thigh.R",
    "Shin.R",
    "Foot.R",
]
BONE_IDX = {name: i for i, name in enumerate(BONE_NAMES)}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def get_or_create_collection(name, parent=None):
    if name in bpy.data.collections:
        return bpy.data.collections[name]
    col = bpy.data.collections.new(name)
    if parent is None:
        bpy.context.scene.collection.children.link(col)
    else:
        parent.children.link(col)
    return col


# ==============================================================================
# GERADOR DE TEXTURAS PBR 512x512 PARA PERSONAGENS
# ==============================================================================

def _value_noise_2d(h, w, scale, seed=0):
    rng = np.random.default_rng(seed)
    gh = max(2, int(scale))
    gw = max(2, int(scale))
    grid = rng.random((gh, gw), dtype=np.float32)
    y = np.linspace(0, gh, h, endpoint=False)
    x = np.linspace(0, gw, w, endpoint=False)
    yi = np.floor(y).astype(np.int32) % gh
    xi = np.floor(x).astype(np.int32) % gw
    yi1 = (yi + 1) % gh
    xi1 = (xi + 1) % gw
    yf = (y - np.floor(y))[:, None]
    xf = (x - np.floor(x))[None, :]
    yf = yf * yf * (3.0 - 2.0 * yf)
    xf = xf * xf * (3.0 - 2.0 * xf)
    v00 = grid[yi[:, None], xi[None, :]]
    v10 = grid[yi[:, None], xi1[None, :]]
    v01 = grid[yi1[:, None], xi[None, :]]
    v11 = grid[yi1[:, None], xi1[None, :]]
    top = v00 * (1.0 - xf) + v10 * xf
    bot = v01 * (1.0 - xf) + v11 * xf
    return top * (1.0 - yf) + bot * yf


def _fbm_2d(size, octaves=(4, 8, 16, 32, 64), seed=1):
    acc = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for idx, sc in enumerate(octaves):
        acc += _value_noise_2d(size, size, sc, seed=seed + idx * 19) * amp
        total += amp
        amp *= 0.5
    return acc / total


def _height_to_normal_rgba(height, strength=2.6):
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(height)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    nx = nx * inv_len * 0.5 + 0.5
    ny = ny * inv_len * 0.5 + 0.5
    nz = nz * inv_len * 0.5 + 0.5
    return np.stack([nx, ny, nz, np.ones_like(height)], axis=-1)


def _array_to_packed_image(name, rgba_float, non_color=False):
    h, w, _ = rgba_float.shape
    img = bpy.data.images.new(name=name, width=w, height=h, alpha=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    buf = np.ascontiguousarray(np.clip(rgba_float, 0.0, 1.0), dtype=np.float32).ravel()
    img.pixels.foreach_set(buf)
    img.pack()
    return img


def generate_char_texture_set(prefix, kind, base_rgb, sec_rgb, size=512, seed=10):
    fbm = _fbm_2d(size, octaves=(4, 8, 16, 32, 64), seed=seed)
    fine = _fbm_2d(size, octaves=(16, 32, 64, 128), seed=seed + 71)
    yy, xx = np.mgrid[0:size, 0:size]
    u = xx / float(size)
    v = yy / float(size)

    normal_strength = 2.4

    if kind == "cloth":
        weave_u = 0.5 + 0.5 * np.sin(u * 96.0 * math.pi)
        weave_v = 0.5 + 0.5 * np.sin(v * 96.0 * math.pi)
        weave = 0.5 * weave_u + 0.5 * weave_v
        fold = 0.5 + 0.5 * np.sin(u * 6.0 * math.pi + fbm * 3.0)
        height = np.clip(0.45 * weave + 0.35 * fbm + 0.20 * fold, 0.0, 1.0)
        mix_t = np.clip(0.25 * fbm + 0.35 * (1.0 - weave) + 0.25 * (1.0 - fold), 0.0, 1.0)
        rough = np.clip(0.80 + 0.12 * (1.0 - weave) + (fbm - 0.5) * 0.08, 0.72, 0.96)
        normal_strength = 2.2
    elif kind == "cape":
        pleat = 0.5 + 0.5 * np.sin(u * 10.0 * math.pi + fbm * 2.2)
        weave_u = 0.5 + 0.5 * np.sin(u * 80.0 * math.pi)
        weave_v = 0.5 + 0.5 * np.sin(v * 80.0 * math.pi)
        weave = 0.5 * weave_u + 0.5 * weave_v
        height = np.clip(0.55 * pleat + 0.25 * weave + 0.20 * fbm, 0.0, 1.0)
        mix_t = np.clip(0.50 * (1.0 - pleat) + 0.30 * fbm, 0.0, 1.0)
        rough = np.clip(0.82 + 0.12 * fbm, 0.74, 0.95)
        normal_strength = 2.5
    elif kind == "plume":
        strands = 0.5 + 0.5 * np.sin((u * 46.0 + fbm * 4.0) * math.pi)
        height = np.clip(0.65 * strands + 0.35 * fine, 0.0, 1.0)
        mix_t = np.clip(0.45 * (1.0 - strands) + 0.25 * fbm, 0.0, 1.0)
        rough = np.clip(0.52 + 0.18 * (1.0 - strands), 0.42, 0.78)
        normal_strength = 2.6
    elif kind == "quilted":
        d1 = np.abs(np.mod((u + v) * 10.0, 1.0) - 0.5) * 2.0
        d2 = np.abs(np.mod((u - v) * 10.0, 1.0) - 0.5) * 2.0
        seam = np.clip(np.minimum(d1, d2) * 3.5, 0.0, 1.0)
        puff = np.sqrt(np.clip(seam, 0.0, 1.0))
        height = np.clip(0.70 * puff + 0.30 * fbm, 0.0, 1.0)
        mix_t = np.clip(0.45 * (1.0 - seam) + 0.30 * fbm, 0.0, 1.0)
        rough = np.clip(0.76 + 0.14 * (1.0 - seam), 0.65, 0.92)
        normal_strength = 2.8
    elif kind == "leather":
        grain = 0.5 + 0.5 * np.sin(fine * 18.0 + fbm * 6.0)
        creases = np.clip(1.0 - np.abs(fbm - 0.5) * 6.0, 0.0, 1.0)
        height = np.clip(0.55 * fine + 0.25 * grain - 0.20 * creases, 0.0, 1.0)
        mix_t = np.clip(0.35 * fbm + 0.40 * creases, 0.0, 1.0)
        rough = np.clip(0.48 + 0.22 * creases + 0.12 * (1.0 - fine), 0.38, 0.76)
        normal_strength = 2.4
    elif kind == "chainmail":
        gx = np.mod(u * 28.0 + np.mod(np.floor(v * 28.0), 2.0) * 0.5, 1.0) - 0.5
        gy = np.mod(v * 28.0, 1.0) - 0.5
        r = np.sqrt(gx * gx + gy * gy)
        ring = np.exp(-((r - 0.33) ** 2) / (2.0 * 0.095 * 0.095))
        height = np.clip(ring * (0.75 + 0.25 * fine), 0.0, 1.0)
        mix_t = np.clip(1.0 - ring * 0.85 + 0.15 * fbm, 0.0, 1.0)
        rough = np.clip(0.50 - 0.22 * ring + 0.10 * fine, 0.22, 0.62)
        normal_strength = 3.8
    elif kind == "metal":
        brush = _value_noise_2d(size, size, 8, seed=seed + 5) * 0.3 + fine * 0.7
        hammer = 0.5 + 0.5 * np.sin(fbm * 14.0)
        height = np.clip(0.45 * hammer + 0.55 * brush, 0.0, 1.0)
        mix_t = np.clip(0.35 * fbm + 0.35 * (1.0 - brush), 0.0, 1.0)
        rough = np.clip(0.18 + 0.20 * brush, 0.12, 0.44)
        normal_strength = 1.4
    elif kind == "straw":
        weave = 0.5 + 0.5 * np.sin((u * 38.0 + v * 14.0 + fbm * 2.5) * math.pi)
        ring = 0.5 + 0.5 * np.sin(v * 26.0 * math.pi)
        height = np.clip(0.55 * weave + 0.30 * ring + 0.15 * fine, 0.0, 1.0)
        mix_t = np.clip(0.40 * (1.0 - weave) + 0.35 * fbm, 0.0, 1.0)
        rough = np.clip(0.84 + 0.10 * (1.0 - weave), 0.74, 0.96)
        normal_strength = 2.8
    elif kind == "wood":
        grain = 0.5 + 0.5 * np.sin((u * 20.0 + fbm * 7.0) * math.pi)
        height = np.clip(0.55 * grain + 0.45 * fine, 0.0, 1.0)
        mix_t = np.clip(0.30 * fbm + 0.50 * (1.0 - grain), 0.0, 1.0)
        rough = np.clip(0.68 + 0.16 * (1.0 - grain), 0.52, 0.88)
        normal_strength = 2.2
    else:  # skin / hair
        height = 0.55 * fbm + 0.45 * fine
        mix_t = np.clip(0.25 * fbm, 0.0, 1.0)
        rough = np.clip(0.58 + 0.10 * fine, 0.50, 0.72)
        normal_strength = 0.9

    c0 = np.array(base_rgb, dtype=np.float32)[None, None, :]
    c1 = np.array(sec_rgb, dtype=np.float32)[None, None, :]
    rgb = c0 * (1.0 - mix_t[..., None]) + c1 * mix_t[..., None]
    albedo_rgba = np.concatenate([rgb, np.ones((size, size, 1), dtype=np.float32)], axis=-1)
    normal_rgba = _height_to_normal_rgba(height, strength=normal_strength)
    rough_rgba = np.stack([rough, rough, rough, np.ones_like(rough)], axis=-1)

    return {
        "albedo": _array_to_packed_image(f"{prefix}_Albedo", albedo_rgba, non_color=False),
        "normal": _array_to_packed_image(f"{prefix}_Normal", normal_rgba, non_color=True),
        "roughness": _array_to_packed_image(f"{prefix}_Roughness", rough_rgba, non_color=True),
    }


def make_char_pbr_material(name, color, roughness=0.65, metallic=0.0, tex_set=None,
                           uv_scale=1.0, normal_strength=0.85,
                           emission_color=None, emission_strength=0.0):
    if name in bpy.data.materials:
        return bpy.data.materials[name]
    mat = bpy.data.materials.new(name=name)
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    nt = mat.node_tree
    nodes = nt.nodes
    links = nt.links
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nodes.new("ShaderNodeBsdfPrincipled")

    if tex_set is not None:
        tex_coord = nodes.new("ShaderNodeTexCoord")
        mapping = nodes.new("ShaderNodeMapping")
        mapping.inputs["Scale"].default_value = (uv_scale, uv_scale, uv_scale)
        links.new(tex_coord.outputs["UV"], mapping.inputs["Vector"])

        t_alb = nodes.new("ShaderNodeTexImage")
        t_alb.image = tex_set["albedo"]
        links.new(mapping.outputs["Vector"], t_alb.inputs["Vector"])
        if "Base Color" in bsdf.inputs:
            links.new(t_alb.outputs["Color"], bsdf.inputs["Base Color"])

        t_rgh = nodes.new("ShaderNodeTexImage")
        t_rgh.image = tex_set["roughness"]
        links.new(mapping.outputs["Vector"], t_rgh.inputs["Vector"])
        if "Roughness" in bsdf.inputs:
            links.new(t_rgh.outputs["Color"], bsdf.inputs["Roughness"])

        t_nrm = nodes.new("ShaderNodeTexImage")
        t_nrm.image = tex_set["normal"]
        links.new(mapping.outputs["Vector"], t_nrm.inputs["Vector"])
        nrm_node = nodes.new("ShaderNodeNormalMap")
        nrm_node.inputs["Strength"].default_value = normal_strength
        links.new(t_nrm.outputs["Color"], nrm_node.inputs["Color"])
        if "Normal" in bsdf.inputs:
            links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    else:
        rgba = (color[0], color[1], color[2], 1.0)
        if "Base Color" in bsdf.inputs:
            bsdf.inputs["Base Color"].default_value = rgba
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = roughness

    if "Metallic" in bsdf.inputs:
        bsdf.inputs["Metallic"].default_value = metallic

    if emission_color is not None and emission_strength > 0.0:
        em_rgba = (emission_color[0], emission_color[1], emission_color[2], 1.0)
        if "Emission Color" in bsdf.inputs:
            bsdf.inputs["Emission Color"].default_value = em_rgba
        elif "Emission" in bsdf.inputs:
            bsdf.inputs["Emission"].default_value = em_rgba
        if "Emission Strength" in bsdf.inputs:
            bsdf.inputs["Emission Strength"].default_value = emission_strength

    mat.diffuse_color = (color[0], color[1], color[2], 1.0)
    return mat


def create_character_materials():
    tex_team_cloth = generate_char_texture_set("CharTeamCloth", "cloth", (0.96, 0.96, 0.96), (0.82, 0.82, 0.84), size=512, seed=201)
    tex_team_cape = generate_char_texture_set("CharTeamCape", "cape", (0.90, 0.90, 0.92), (0.68, 0.68, 0.72), size=512, seed=202)
    tex_team_accent = generate_char_texture_set("CharTeamAccent", "plume", (0.98, 0.98, 0.98), (0.76, 0.76, 0.80), size=512, seed=203)
    tex_linen = generate_char_texture_set("CharLinen", "cloth", (0.86, 0.81, 0.71), (0.72, 0.65, 0.54), size=512, seed=204)
    tex_trousers = generate_char_texture_set("CharTrousers", "cloth", (0.38, 0.33, 0.27), (0.27, 0.22, 0.18), size=512, seed=205)
    tex_leather = generate_char_texture_set("CharLeather", "leather", (0.42, 0.24, 0.12), (0.26, 0.14, 0.07), size=512, seed=206)
    tex_dark_leather = generate_char_texture_set("CharDarkLeather", "leather", (0.20, 0.13, 0.09), (0.11, 0.07, 0.05), size=512, seed=207)
    tex_chainmail = generate_char_texture_set("CharChainmail", "chainmail", (0.64, 0.68, 0.74), (0.24, 0.26, 0.30), size=512, seed=208)
    tex_steel = generate_char_texture_set("CharSteel", "metal", (0.78, 0.82, 0.88), (0.52, 0.56, 0.63), size=512, seed=209)
    tex_iron = generate_char_texture_set("CharDarkIron", "metal", (0.42, 0.45, 0.50), (0.25, 0.27, 0.32), size=512, seed=210)
    tex_gold = generate_char_texture_set("CharRoyalGold", "metal", (0.96, 0.76, 0.20), (0.74, 0.52, 0.10), size=512, seed=211)
    tex_ranger = generate_char_texture_set("CharRangerCloth", "quilted", (0.17, 0.40, 0.20), (0.09, 0.24, 0.12), size=512, seed=212)
    tex_straw = generate_char_texture_set("CharStraw", "straw", (0.86, 0.72, 0.34), (0.64, 0.49, 0.20), size=512, seed=213)
    tex_wood = generate_char_texture_set("CharWoodGrip", "wood", (0.46, 0.27, 0.13), (0.28, 0.16, 0.07), size=512, seed=214)
    tex_skin = generate_char_texture_set("CharSkin", "skin", (0.89, 0.69, 0.55), (0.79, 0.57, 0.44), size=512, seed=215)

    return {
        # Materiais tintados por time no Godot (nomes exatos começam por Mat_Team*)
        "team_primary": make_char_pbr_material("Mat_TeamPrimary", (0.92, 0.92, 0.92), roughness=0.84, tex_set=tex_team_cloth, uv_scale=1.6, normal_strength=0.75),
        "team_cape": make_char_pbr_material("Mat_TeamCape", (0.82, 0.82, 0.84), roughness=0.86, tex_set=tex_team_cape, uv_scale=1.2, normal_strength=0.85),
        "team_accent": make_char_pbr_material("Mat_TeamAccent", (0.95, 0.95, 0.95), roughness=0.58, tex_set=tex_team_accent, uv_scale=1.8, normal_strength=0.85),
        # Materiais orgânicos / roupas / armaduras
        "skin": make_char_pbr_material("Mat_CharSkin", (0.87, 0.67, 0.53), roughness=0.60, tex_set=tex_skin, uv_scale=1.0, normal_strength=0.35),
        "hair": make_char_pbr_material("Mat_CharHair", (0.22, 0.14, 0.09), roughness=0.80),
        "eye": make_char_pbr_material("Mat_CharEye", (0.07, 0.06, 0.06), roughness=0.22),
        "visor_dark": make_char_pbr_material("Mat_VisorDark", (0.05, 0.05, 0.06), roughness=0.85),
        "tunic_cloth": make_char_pbr_material("Mat_CharLinen", (0.82, 0.77, 0.66), roughness=0.86, tex_set=tex_linen, uv_scale=1.8, normal_strength=0.70),
        "trousers": make_char_pbr_material("Mat_CharTrousers", (0.34, 0.29, 0.24), roughness=0.88, tex_set=tex_trousers, uv_scale=1.8, normal_strength=0.70),
        "leather": make_char_pbr_material("Mat_CharLeather", (0.38, 0.21, 0.11), roughness=0.54, tex_set=tex_leather, uv_scale=1.8, normal_strength=0.75),
        "dark_leather": make_char_pbr_material("Mat_CharDarkLeather", (0.17, 0.11, 0.08), roughness=0.58, tex_set=tex_dark_leather, uv_scale=1.8, normal_strength=0.75),
        "chainmail": make_char_pbr_material("Mat_CharChainmail", (0.55, 0.58, 0.63), roughness=0.38, metallic=0.88, tex_set=tex_chainmail, uv_scale=2.2, normal_strength=1.05),
        "steel": make_char_pbr_material("Mat_CharSteel", (0.76, 0.80, 0.86), roughness=0.24, metallic=0.93, tex_set=tex_steel, uv_scale=1.5, normal_strength=0.65),
        "iron": make_char_pbr_material("Mat_CharIron", (0.39, 0.42, 0.47), roughness=0.32, metallic=0.89, tex_set=tex_iron, uv_scale=1.5, normal_strength=0.70),
        "gold_trim": make_char_pbr_material("Mat_CharGoldTrim", (0.93, 0.72, 0.18), roughness=0.20, metallic=0.95, tex_set=tex_gold, uv_scale=1.6, normal_strength=0.55),
        "archer_green": make_char_pbr_material("Mat_CharArcherGreen", (0.15, 0.36, 0.18), roughness=0.80, tex_set=tex_ranger, uv_scale=2.0, normal_strength=0.80),
        "straw": make_char_pbr_material("Mat_CharStraw", (0.82, 0.68, 0.32), roughness=0.88, tex_set=tex_straw, uv_scale=2.2, normal_strength=0.85),
        "wood": make_char_pbr_material("Mat_CharWood", (0.42, 0.25, 0.12), roughness=0.72, tex_set=tex_wood, uv_scale=2.0, normal_strength=0.75),
        "bowstring": make_char_pbr_material("Mat_CharBowstring", (0.86, 0.82, 0.72), roughness=0.75),
    }


# ==============================================================================
# HELPERS DE GEOMETRIA ORGÂNICA + WEIGHTS DE ESQUELETO (BMESH DEFORM LAYER)
# ==============================================================================

def _set_verts_weights(bm, deform_layer, verts, weights):
    if not weights:
        return
    if isinstance(weights, int):
        w_dict = {weights: 1.0}
    else:
        w_dict = weights
    for v in verts:
        if not v.is_valid:
            continue
        dv = v[deform_layer]
        for b_idx, w in w_dict.items():
            if w > 1e-4:
                dv[b_idx] = float(w)


def _apply_xform_mat_weights(bm, deform_layer, verts, mat_xform, mat_idx, weights=None):
    bmesh.ops.transform(bm, matrix=mat_xform, verts=verts)
    for v in verts:
        for f in v.link_faces:
            f.material_index = mat_idx
    _set_verts_weights(bm, deform_layer, verts, weights)


def add_loft(bm, deform_layer, rings, segments=16, mat_idx=0, weights_fn=None,
             cap_bottom=True, cap_top=True, phase_twist=0.0):
    """
    Cria malha loftada suave a partir de uma lista de anéis:
      ring = (z, rx, ry, cx, cy)  ou  (z, rx, ry, cx, cy, tilt_x, tilt_y)
    """
    all_rings = []
    all_verts = []
    for r_i, ring in enumerate(rings):
        if len(ring) == 5:
            z, rx, ry, cx, cy = ring
            tx, ty = 0.0, 0.0
        else:
            z, rx, ry, cx, cy, tx, ty = ring
        ring_verts = []
        rot_m = Euler((tx, ty, 0.0), "XYZ").to_matrix()
        for s in range(segments):
            ang = (2.0 * math.pi * s) / segments + phase_twist
            lx = math.cos(ang) * rx
            ly = math.sin(ang) * ry
            p = rot_m @ Vector((lx, ly, 0.0)) + Vector((cx, cy, z))
            v = bm.verts.new(p)
            ring_verts.append(v)
            all_verts.append(v)
        if weights_fn is not None:
            w = weights_fn(r_i, len(rings), z)
            _set_verts_weights(bm, deform_layer, ring_verts, w)
        all_rings.append(ring_verts)

    for i in range(len(all_rings) - 1):
        r0 = all_rings[i]
        r1 = all_rings[i + 1]
        for s in range(segments):
            ns = (s + 1) % segments
            f = bm.faces.new((r0[s], r0[ns], r1[ns], r1[s]))
            f.material_index = mat_idx

    if cap_bottom and len(all_rings) > 0:
        r0 = all_rings[0]
        cx = sum(v.co.x for v in r0) / len(r0)
        cy = sum(v.co.y for v in r0) / len(r0)
        cz = sum(v.co.z for v in r0) / len(r0)
        vc = bm.verts.new((cx, cy, cz))
        all_verts.append(vc)
        if weights_fn is not None:
            _set_verts_weights(bm, deform_layer, [vc], weights_fn(0, len(rings), cz))
        for s in range(segments):
            ns = (s + 1) % segments
            f = bm.faces.new((vc, r0[ns], r0[s]))
            f.material_index = mat_idx

    if cap_top and len(all_rings) > 0:
        rt = all_rings[-1]
        cx = sum(v.co.x for v in rt) / len(rt)
        cy = sum(v.co.y for v in rt) / len(rt)
        cz = sum(v.co.z for v in rt) / len(rt)
        vc = bm.verts.new((cx, cy, cz))
        all_verts.append(vc)
        if weights_fn is not None:
            _set_verts_weights(bm, deform_layer, [vc], weights_fn(len(rings) - 1, len(rings), cz))
        for s in range(segments):
            ns = (s + 1) % segments
            f = bm.faces.new((vc, rt[s], rt[ns]))
            f.material_index = mat_idx

    return all_verts


def add_limb_chain(bm, deform_layer, pts_radii, segments=14, mat_idx=0, weights_fn=None,
                   cap_bottom=True, cap_top=True):
    """
    Lofta ao longo de uma espinha 3D arbitrária (útil para braços inclinados, arcos, plumas, chifres).
    pts_radii = lista de (Vector(x,y,z), rx, ry)
    """
    n = len(pts_radii)
    all_rings = []
    all_verts = []
    prev_up = Vector((0, 1, 0))
    for i, (pt, rx, ry) in enumerate(pts_radii):
        if i == 0:
            tangent = (pts_radii[1][0] - pt).normalized()
        elif i == n - 1:
            tangent = (pt - pts_radii[i - 1][0]).normalized()
        else:
            tangent = (pts_radii[i + 1][0] - pts_radii[i - 1][0]).normalized()

        if abs(tangent.dot(prev_up)) > 0.96:
            ref = Vector((1, 0, 0))
        else:
            ref = prev_up
        side_x = ref.cross(tangent).normalized()
        side_y = tangent.cross(side_x).normalized()
        prev_up = side_y

        ring_verts = []
        for s in range(segments):
            ang = (2.0 * math.pi * s) / segments
            offset = side_x * (math.cos(ang) * rx) + side_y * (math.sin(ang) * ry)
            v = bm.verts.new(pt + offset)
            ring_verts.append(v)
            all_verts.append(v)
        if weights_fn is not None:
            _set_verts_weights(bm, deform_layer, ring_verts, weights_fn(i, n, pt))
        all_rings.append(ring_verts)

    for i in range(n - 1):
        r0 = all_rings[i]
        r1 = all_rings[i + 1]
        for s in range(segments):
            ns = (s + 1) % segments
            f = bm.faces.new((r0[s], r0[ns], r1[ns], r1[s]))
            f.material_index = mat_idx

    if cap_bottom:
        r0 = all_rings[0]
        vc = bm.verts.new(pts_radii[0][0])
        all_verts.append(vc)
        if weights_fn is not None:
            _set_verts_weights(bm, deform_layer, [vc], weights_fn(0, n, pts_radii[0][0]))
        for s in range(segments):
            ns = (s + 1) % segments
            f = bm.faces.new((vc, r0[ns], r0[s]))
            f.material_index = mat_idx

    if cap_top:
        rt = all_rings[-1]
        vc = bm.verts.new(pts_radii[-1][0])
        all_verts.append(vc)
        if weights_fn is not None:
            _set_verts_weights(bm, deform_layer, [vc], weights_fn(n - 1, n, pts_radii[-1][0]))
        for s in range(segments):
            ns = (s + 1) % segments
            f = bm.faces.new((vc, rt[s], rt[ns]))
            f.material_index = mat_idx

    return all_verts


def add_draped_sheet(bm, deform_layer, rows, cols, profile_fn, thickness=0.024,
                     mat_idx=0, border_mat_idx=None, weights_fn=None):
    """
    Cria tecido espesso com dobras suaves (capas, tabardos, lenços).
    profile_fn(u in [0..1], v in [0..1]) -> (pos_vec, normal_vec)
      v=0 topo (ombro/cinto), v=1 barra inferior.
    """
    front_grid = []
    back_grid = []
    all_verts = []
    for r in range(rows + 1):
        v_t = r / float(rows)
        f_row = []
        b_row = []
        for c in range(cols + 1):
            u_t = c / float(cols)
            pos, nrm = profile_fn(u_t, v_t)
            nrm = nrm.normalized()
            vf = bm.verts.new(pos + nrm * (thickness * 0.5))
            vb = bm.verts.new(pos - nrm * (thickness * 0.5))
            f_row.append(vf)
            b_row.append(vb)
            all_verts.extend([vf, vb])
            if weights_fn is not None:
                _set_verts_weights(bm, deform_layer, [vf, vb], weights_fn(u_t, v_t, pos))
        front_grid.append(f_row)
        back_grid.append(b_row)

    for r in range(rows):
        for c in range(cols):
            m_i = border_mat_idx if (border_mat_idx is not None and r == rows - 1) else mat_idx
            ff = bm.faces.new((front_grid[r][c], front_grid[r][c + 1], front_grid[r + 1][c + 1], front_grid[r + 1][c]))
            ff.material_index = m_i
            fb = bm.faces.new((back_grid[r][c + 1], back_grid[r][c], back_grid[r + 1][c], back_grid[r + 1][c + 1]))
            fb.material_index = m_i

    # Costura todas as bordas da espessura
    for c in range(cols):
        f_top = bm.faces.new((back_grid[0][c], back_grid[0][c + 1], front_grid[0][c + 1], front_grid[0][c]))
        f_top.material_index = mat_idx
        m_bot = border_mat_idx if border_mat_idx is not None else mat_idx
        f_bot = bm.faces.new((front_grid[rows][c], front_grid[rows][c + 1], back_grid[rows][c + 1], back_grid[rows][c]))
        f_bot.material_index = m_bot

    for r in range(rows):
        m_side = border_mat_idx if (border_mat_idx is not None and r == rows - 1) else mat_idx
        f_l = bm.faces.new((back_grid[r][0], front_grid[r][0], front_grid[r + 1][0], back_grid[r + 1][0]))
        f_l.material_index = m_side
        f_r = bm.faces.new((front_grid[r][cols], back_grid[r][cols], back_grid[r + 1][cols], front_grid[r + 1][cols]))
        f_r.material_index = m_side

    return all_verts


def add_beveled_box(bm, deform_layer, sx, sy, sz, center=(0, 0, 0), rot=(0, 0, 0),
                    bevel_amt=0.03, bevel_segs=2, mat_idx=0, weights=None):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal((sx, sy, sz, 1.0)), verts=verts)
    if bevel_amt > 0.0:
        edges = list({e for v in verts for e in v.link_edges})
        b_ret = bmesh.ops.bevel(
            bm, geom=edges, offset=min(bevel_amt, min(sx, sy, sz) * 0.24),
            segments=bevel_segs, profile=0.5, affect="EDGES"
        )
        verts = list({v for v in verts if v.is_valid} | {v for v in b_ret.get("verts", []) if v.is_valid})
    mat_rot = Euler(rot, "XYZ").to_matrix().to_4x4()
    mat_trans = Matrix.Translation(center)
    _apply_xform_mat_weights(bm, deform_layer, verts, mat_trans @ mat_rot, mat_idx, weights)
    return verts


def add_cylinder(bm, deform_layer, r1, r2, depth, segments=16, center=(0, 0, 0),
                 rot=(0, 0, 0), scale=(1, 1, 1), mat_idx=0, cap_ends=True, weights=None):
    ret = bmesh.ops.create_cone(
        bm, cap_ends=cap_ends, cap_tris=False, segments=segments,
        radius1=r1, radius2=r2, depth=depth
    )
    verts = ret["verts"]
    mat_scale = Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    mat_rot = Euler(rot, "XYZ").to_matrix().to_4x4()
    mat_trans = Matrix.Translation(center)
    _apply_xform_mat_weights(bm, deform_layer, verts, mat_trans @ mat_rot @ mat_scale, mat_idx, weights)
    return verts


def add_sphere(bm, deform_layer, radius, subdivisions=2, center=(0, 0, 0),
               scale=(1, 1, 1), rot=(0, 0, 0), mat_idx=0, weights=None):
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    verts = ret["verts"]
    mat_scale = Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    mat_rot = Euler(rot, "XYZ").to_matrix().to_4x4()
    mat_trans = Matrix.Translation(center)
    _apply_xform_mat_weights(bm, deform_layer, verts, mat_trans @ mat_rot @ mat_scale, mat_idx, weights)
    return verts


def add_curved_shield(bm, deform_layer, width, height, curve_depth, thickness,
                      center, rot, rim_mat, face_mat, emblem_mat, bone_idx, shape="heater"):
    """
    Escudo 3D curvo em espaço local (frente voltada para -X, altura em Z, largura em Y)
    transformado para a mão esquerda (Hand.L).
    """
    xform = Matrix.Translation(center) @ Euler(rot, "XYZ").to_matrix().to_4x4()
    rows = 10
    cols = 8
    f_grid = []
    b_grid = []
    all_verts = []

    def shield_half_w(t_v):
        # t_v: 0 topo -> 1 ponta inferior
        if shape == "kite":
            if t_v < 0.25:
                return width * 0.5 * (0.85 + 0.15 * math.sin((t_v / 0.25) * math.pi * 0.5))
            u = (t_v - 0.25) / 0.75
            return width * 0.5 * max(0.06, 1.0 - (u ** 1.35))
        else:  # heater
            if t_v < 0.42:
                return width * 0.5
            u = (t_v - 0.42) / 0.58
            return width * 0.5 * max(0.08, math.cos(u * math.pi * 0.48))

    for r in range(rows + 1):
        tv = r / float(rows)
        lz = (0.5 - tv) * height
        hw = shield_half_w(tv)
        f_row = []
        b_row = []
        for c in range(cols + 1):
            tu = (c / float(cols)) * 2.0 - 1.0  # -1..+1
            ly = tu * hw
            # Curva convexa voltada para -X
            curve_x = -curve_depth * (1.0 - tu * tu * 0.85)
            p_front = xform @ Vector((curve_x - thickness * 0.5, ly, lz))
            p_back = xform @ Vector((curve_x + thickness * 0.5, ly, lz))
            vf = bm.verts.new(p_front)
            vb = bm.verts.new(p_back)
            f_row.append(vf)
            b_row.append(vb)
            all_verts.extend([vf, vb])
        f_grid.append(f_row)
        b_grid.append(b_row)

    for r in range(rows):
        for c in range(cols):
            is_rim = (r == 0 or r == rows - 1 or c == 0 or c == cols - 1)
            m_f = rim_mat if is_rim else face_mat
            ff = bm.faces.new((f_grid[r][c], f_grid[r + 1][c], f_grid[r + 1][c + 1], f_grid[r][c + 1]))
            ff.material_index = m_f
            fb = bm.faces.new((b_grid[r][c + 1], b_grid[r + 1][c + 1], b_grid[r + 1][c], b_grid[r][c]))
            fb.material_index = rim_mat

    for c in range(cols):
        bm.faces.new((f_grid[0][c], f_grid[0][c + 1], b_grid[0][c + 1], b_grid[0][c])).material_index = rim_mat
        bm.faces.new((b_grid[rows][c], b_grid[rows][c + 1], f_grid[rows][c + 1], f_grid[rows][c])).material_index = rim_mat
    for r in range(rows):
        bm.faces.new((b_grid[r][0], b_grid[r + 1][0], f_grid[r + 1][0], f_grid[r][0])).material_index = rim_mat
        bm.faces.new((f_grid[r][cols], f_grid[r + 1][cols], b_grid[r + 1][cols], b_grid[r][cols])).material_index = rim_mat

    _set_verts_weights(bm, deform_layer, all_verts, bone_idx)

    # Bossa central e cruz heráldica em alto relevo na face externa (-X)
    boss_p = xform @ Vector((-curve_depth - thickness * 0.6, 0.0, height * 0.08))
    add_sphere(bm, deform_layer, width * 0.16, subdivisions=2, center=boss_p,
               scale=(0.55, 1.0, 1.0), rot=rot, mat_idx=emblem_mat, weights=bone_idx)
    bar_v = xform @ Vector((-curve_depth - thickness * 0.35, 0.0, 0.0))
    add_beveled_box(bm, deform_layer, 0.025, width * 0.13, height * 0.68, center=bar_v,
                    rot=rot, bevel_amt=0.008, mat_idx=emblem_mat, weights=bone_idx)
    bar_h = xform @ Vector((-curve_depth - thickness * 0.35, 0.0, height * 0.08))
    add_beveled_box(bm, deform_layer, 0.025, width * 0.62, width * 0.13, center=bar_h,
                    rot=rot, bevel_amt=0.008, mat_idx=emblem_mat, weights=bone_idx)


def add_sculpted_head(bm, deform_layer, center, scale, skin_mat, hair_mat, eye_mat,
                      bone_idx, with_beard=False, with_hair=True):
    """
    Cabeça estilizada heroica voltada para +Y, com mandíbula definida, nariz, orelhas e olhos.
    """
    cx, cy, cz = center
    sx, sy, sz = scale
    # Crânio + mandíbula esculpida via loft vertical
    rings = [
        (cz - 0.14 * sz, 0.08 * sx, 0.09 * sy, cx, cy + 0.015 * sy),
        (cz - 0.09 * sz, 0.125 * sx, 0.14 * sy, cx, cy + 0.020 * sy),
        (cz - 0.02 * sz, 0.145 * sx, 0.155 * sy, cx, cy + 0.010 * sy),
        (cz + 0.05 * sz, 0.150 * sx, 0.160 * sy, cx, cy),
        (cz + 0.12 * sz, 0.135 * sx, 0.145 * sy, cx, cy - 0.005 * sy),
        (cz + 0.17 * sz, 0.085 * sx, 0.095 * sy, cx, cy - 0.010 * sy),
    ]
    add_loft(bm, deform_layer, rings, segments=16, mat_idx=skin_mat,
             weights_fn=lambda *_: bone_idx)

    # Pescoço
    add_cylinder(bm, deform_layer, 0.082 * sx, 0.075 * sx, 0.16 * sz, segments=12,
                 center=(cx, cy - 0.01 * sy, cz - 0.15 * sz), mat_idx=skin_mat, weights=bone_idx)

    # Nariz esculpido (+Y)
    add_beveled_box(bm, deform_layer, 0.036 * sx, 0.055 * sy, 0.068 * sz,
                    center=(cx, cy + 0.155 * sy, cz + 0.01 * sz),
                    rot=(-0.22, 0.0, 0.0), bevel_amt=0.012, mat_idx=skin_mat, weights=bone_idx)

    # Sobrancelhas / Arcada
    add_beveled_box(bm, deform_layer, 0.16 * sx, 0.045 * sy, 0.026 * sz,
                    center=(cx, cy + 0.142 * sy, cz + 0.056 * sz),
                    bevel_amt=0.008, mat_idx=skin_mat, weights=bone_idx)

    # Olhos
    for ex in (-0.052 * sx, 0.052 * sx):
        add_sphere(bm, deform_layer, 0.021 * sx, subdivisions=1,
                   center=(cx + ex, cy + 0.144 * sy, cz + 0.032 * sz),
                   scale=(1.0, 0.7, 1.0), mat_idx=eye_mat, weights=bone_idx)
        # Orelhas
        add_sphere(bm, deform_layer, 0.032 * sx, subdivisions=1,
                   center=(cx + (ex / 0.052) * 0.145, cy - 0.005 * sy, cz + 0.01 * sz),
                   scale=(0.45, 0.85, 1.25), mat_idx=skin_mat, weights=bone_idx)

    if with_hair:
        # Cabelo traseiro e lateral
        add_sphere(bm, deform_layer, 0.152 * sx, subdivisions=2,
                   center=(cx, cy - 0.03 * sy, cz + 0.045 * sz),
                   scale=(1.02, 1.02, 0.96), mat_idx=hair_mat, weights=bone_idx)

    if with_beard:
        # Bigode e barba cheia de camponês
        add_beveled_box(bm, deform_layer, 0.15 * sx, 0.065 * sy, 0.042 * sz,
                        center=(cx, cy + 0.145 * sy, cz - 0.035 * sz),
                        rot=(0.15, 0.0, 0.0), bevel_amt=0.014, mat_idx=hair_mat, weights=bone_idx)
        beard_rings = [
            (cz - 0.18 * sz, 0.075 * sx, 0.070 * sy, cx, cy + 0.075 * sy),
            (cz - 0.11 * sz, 0.125 * sx, 0.105 * sy, cx, cy + 0.055 * sy),
            (cz - 0.04 * sz, 0.135 * sx, 0.110 * sy, cx, cy + 0.040 * sy),
        ]
        add_loft(bm, deform_layer, beard_rings, segments=12, mat_idx=hair_mat,
                 weights_fn=lambda *_: bone_idx)


def add_blade_diamond(bm, deform_layer, length, base_w, tip_w, thick, center, rot, mat_idx, bone_idx):
    """Lâmina de seção em diamante afilada até a ponta."""
    xform = Matrix.Translation(center) @ Euler(rot, "XYZ").to_matrix().to_4x4()
    hw0 = base_w * 0.5
    hw1 = tip_w * 0.5
    ht0 = thick * 0.5
    ht1 = thick * 0.25

    def ring(z, hw, ht):
        return [
            bm.verts.new(xform @ Vector((0.0, -hw, z))),
            bm.verts.new(xform @ Vector((ht, 0.0, z))),
            bm.verts.new(xform @ Vector((0.0, hw, z))),
            bm.verts.new(xform @ Vector((-ht, 0.0, z))),
        ]

    r0 = ring(0.0, hw0, ht0)
    r1 = ring(length * 0.72, hw0 * 0.78, ht0 * 0.85)
    r2 = ring(length * 0.92, hw1, ht1)
    tip = bm.verts.new(xform @ Vector((0.0, 0.0, length)))

    all_v = r0 + r1 + r2 + [tip]
    _set_verts_weights(bm, deform_layer, all_v, bone_idx)

    for ra, rb in ((r0, r1), (r1, r2)):
        for i in range(4):
            ni = (i + 1) % 4
            bm.faces.new((ra[i], ra[ni], rb[ni], rb[i])).material_index = mat_idx
    for i in range(4):
        ni = (i + 1) % 4
        bm.faces.new((r2[i], r2[ni], tip)).material_index = mat_idx
    bm.faces.new((r0[3], r0[2], r0[1], r0[0])).material_index = mat_idx
    return all_v


def add_pauldron_cup(bm, deform_layer, side, center, radius, mat_main, mat_trim, bone_idx):
    """Ombreira curva em camadas (aço + borda dourada)."""
    sx = -1.0 if side == "L" else 1.0
    tilt_y = -0.35 if side == "L" else 0.35
    add_sphere(bm, deform_layer, radius, subdivisions=2, center=center,
               scale=(0.85, 1.05, 0.78), rot=(0.0, tilt_y, 0.0),
               mat_idx=mat_main, weights=bone_idx)
    add_cylinder(bm, deform_layer, radius * 1.02, radius * 1.05, radius * 0.28, segments=16,
                 center=(center[0] + sx * radius * 0.14, center[1], center[2] - radius * 0.14),
                 rot=(0.0, tilt_y * 1.2, 0.0), scale=(0.85, 1.05, 1.0),
                 mat_idx=mat_trim, weights=bone_idx)


def add_boot_pair(bm, deform_layer, leg_x, foot_z, shin_r, mat_boot, mat_trim,
                  bone_foot_l, bone_foot_r, bone_shin_l, bone_shin_r, armored=False):
    for sx, b_foot, b_shin in ((-leg_x, bone_foot_l, bone_shin_l), (leg_x, bone_foot_r, bone_shin_r)):
        # Sola e calcanhar + biqueira voltada para +Y
        add_beveled_box(bm, deform_layer, shin_r * 1.45, 0.27, 0.11,
                        center=(sx, 0.055, 0.055), bevel_amt=0.025,
                        mat_idx=mat_boot, weights=b_foot)
        add_beveled_box(bm, deform_layer, shin_r * 1.20, 0.10, 0.075,
                        center=(sx, 0.18, 0.042), rot=(0.14, 0.0, 0.0), bevel_amt=0.02,
                        mat_idx=mat_boot, weights=b_foot)
        # Cano da bota / greva
        rings = [
            (0.08, shin_r * 0.92, shin_r * 0.98, sx, 0.0),
            (foot_z * 0.55, shin_r * 0.96, shin_r * 1.02, sx, 0.0),
            (foot_z, shin_r * 1.10, shin_r * 1.12, sx, 0.0),
        ]
        add_loft(bm, deform_layer, rings, segments=14, mat_idx=mat_boot,
                 weights_fn=lambda ri, _n, z: {b_foot: 0.75, b_shin: 0.25} if ri == 0 else b_shin)
        # Dobra do cano ou rebordo dourado
        add_cylinder(bm, deform_layer, shin_r * 1.16, shin_r * 1.22, 0.06, segments=14,
                     center=(sx, 0.0, foot_z + 0.01), mat_idx=mat_trim, weights=b_shin)
        if armored:
            # Joelheira (poleyn)
            add_sphere(bm, deform_layer, shin_r * 1.12, subdivisions=2,
                       center=(sx, 0.035, foot_z + 0.12), scale=(0.95, 0.85, 1.05),
                       mat_idx=mat_trim, weights=b_shin)


def add_leg_tubes(bm, deform_layer, leg_x, ankle_z, knee_z, hip_z, r_shin, r_thigh,
                  mat_shin, mat_thigh, b_shin_l, b_thigh_l, b_shin_r, b_thigh_r, hips_idx):
    for sx, b_shin, b_thigh in ((-leg_x, b_shin_l, b_thigh_l), (leg_x, b_shin_r, b_thigh_r)):
        shin_rings = [
            (ankle_z, r_shin * 0.92, r_shin * 0.95, sx, 0.0),
            ((ankle_z + knee_z) * 0.5, r_shin * 1.05, r_shin * 1.10, sx, -0.01),
            (knee_z + 0.03, r_shin * 1.08, r_shin * 1.08, sx, 0.0),
        ]
        add_loft(bm, deform_layer, shin_rings, segments=14, mat_idx=mat_shin,
                 weights_fn=lambda ri, _n, z: {b_shin: 0.85, b_thigh: 0.15} if ri == 2 else b_shin)

        thigh_rings = [
            (knee_z - 0.02, r_thigh * 0.88, r_thigh * 0.90, sx, 0.0),
            ((knee_z + hip_z) * 0.5, r_thigh * 1.02, r_thigh * 1.04, sx, 0.005),
            (hip_z + 0.03, r_thigh * 1.08, r_thigh * 1.06, sx, 0.0),
        ]
        add_loft(bm, deform_layer, thigh_rings, segments=14, mat_idx=mat_thigh,
                 weights_fn=lambda ri, _n, z: {b_thigh: 0.65, hips_idx: 0.35} if ri == 2 else b_thigh)


def add_arm_pair(bm, deform_layer, sh_pt_l, elb_pt_l, hand_pt_l, r_up, r_fore,
                 mat_sleeve, mat_cuff, mat_hand):
    for side_sign, sh_pt, elb_pt, hand_pt, b_up, b_fore, b_hand in (
        (-1, sh_pt_l, elb_pt_l, hand_pt_l, BONE_IDX["UpperArm.L"], BONE_IDX["Forearm.L"], BONE_IDX["Hand.L"]),
        (1, Vector((-sh_pt_l.x, sh_pt_l.y, sh_pt_l.z)),
            Vector((-elb_pt_l.x, elb_pt_l.y, elb_pt_l.z)),
            Vector((-hand_pt_l.x, hand_pt_l.y, hand_pt_l.z)),
            BONE_IDX["UpperArm.R"], BONE_IDX["Forearm.R"], BONE_IDX["Hand.R"]),
    ):
        mid_up = sh_pt.lerp(elb_pt, 0.5)
        add_limb_chain(
            bm, deform_layer,
            [(sh_pt, r_up * 1.05, r_up * 1.05), (mid_up, r_up, r_up), (elb_pt, r_up * 0.88, r_up * 0.88)],
            segments=12, mat_idx=mat_sleeve,
            weights_fn=lambda i, _n, _p: {b_up: 0.75, b_fore: 0.25} if i == 2 else b_up
        )
        mid_fo = elb_pt.lerp(hand_pt, 0.55)
        wrist = elb_pt.lerp(hand_pt, 0.92)
        add_limb_chain(
            bm, deform_layer,
            [(elb_pt, r_fore * 1.02, r_fore * 1.02), (mid_fo, r_fore * 0.96, r_fore * 0.96), (wrist, r_fore * 0.82, r_fore * 0.82)],
            segments=12, mat_idx=mat_cuff,
            weights_fn=lambda i, _n, _p: {b_fore: 0.75, b_hand: 0.25} if i == 2 else ({b_up: 0.25, b_fore: 0.75} if i == 0 else b_fore)
        )
        # Mão fechada estilizada
        add_sphere(bm, deform_layer, r_fore * 0.98, subdivisions=2, center=hand_pt,
                   scale=(0.88, 1.05, 1.15), mat_idx=mat_hand, weights=b_hand)


def add_tabard_panel(bm, deform_layer, width_top, width_bot, z_top, z_bot, y_offset,
                     is_front, mat_idx, border_mat_idx, thickness=0.025):
    sign_y = 1.0 if is_front else -1.0

    def profile(u, v):
        x = (u - 0.5) * (width_top * (1.0 - v) + width_bot * v)
        z = z_top * (1.0 - v) + z_bot * v
        pleat = math.sin((u - 0.5) * math.pi * 4.0) * 0.012 * v
        flare = sign_y * (0.045 * (v ** 1.3))
        y = y_offset + flare + sign_y * pleat
        return Vector((x, y, z)), Vector((0.0, sign_y, 0.0))

    def weights(u, v, pos):
        if pos.z > (z_top * 0.65 + z_bot * 0.35):
            return {BONE_IDX["Hips"]: 0.55, BONE_IDX["Spine"]: 0.45}
        return BONE_IDX["Hips"]

    add_draped_sheet(bm, deform_layer, 6, 6, profile, thickness=thickness,
                     mat_idx=mat_idx, border_mat_idx=border_mat_idx, weights_fn=weights)


def add_flowing_cape(bm, deform_layer, width_top, width_bot, z_top, z_bot, y_top, flare_back,
                     mat_idx, border_mat_idx=None):
    def profile(u, v):
        w = width_top * (1.0 - v) + width_bot * v
        x = (u - 0.5) * w
        z = z_top * (1.0 - v) + z_bot * v
        # Curvatura envolvendo os ombros no topo e pregas amplas na barra
        shoulder_wrap = (1.0 - v) * 0.08 * ((u - 0.5) * 2.0) ** 2
        pleat = math.sin((u - 0.5) * math.pi * 5.0) * (0.016 + 0.032 * v)
        y = y_top - flare_back * (v ** 1.25) + shoulder_wrap + pleat
        return Vector((x, y, z)), Vector((0.0, -1.0, 0.08))

    def weights(u, v, pos):
        if v < 0.22:
            t = v / 0.22
            return {BONE_IDX["Chest"]: 1.0 - t, BONE_IDX["Cape.1"]: t}
        elif v < 0.60:
            t = (v - 0.22) / 0.38
            return {BONE_IDX["Cape.1"]: 1.0 - t, BONE_IDX["Cape.2"]: t}
        return BONE_IDX["Cape.2"]

    add_draped_sheet(bm, deform_layer, 10, 10, profile, thickness=0.026,
                     mat_idx=mat_idx, border_mat_idx=border_mat_idx, weights_fn=weights)


def finalize_rigged_mesh(name, bm, mat_list, collection, arm_obj, split_angle_deg=52.0):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)

    # UVs limpas projetadas por box-mapping
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                loop[uv_layer].uv = (co.x * 1.4, co.y * 1.4)
            elif ax >= ay and ax >= az:
                loop[uv_layer].uv = (co.y * 1.4, co.z * 1.4)
            else:
                loop[uv_layer].uv = (co.x * 1.4, co.z * 1.4)

    if split_angle_deg < 179.0:
        rad_thresh = math.radians(split_angle_deg)
        sharp_edges = [
            e for e in bm.edges
            if len(e.link_faces) == 2 and e.link_faces[0].normal.angle(e.link_faces[1].normal, 0.0) > rad_thresh
        ]
        if sharp_edges:
            bmesh.ops.split_edges(bm, edges=sharp_edges)

    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    for p in mesh.polygons:
        p.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    for mat in mat_list:
        obj.data.materials.append(mat)

    for b_name in BONE_NAMES:
        obj.vertex_groups.new(name=b_name)

    obj.parent = arm_obj
    mod = obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    mod.use_vertex_groups = True
    return obj


# ==============================================================================
# CONSTRUÇÃO DO ESQUELETO HUMANOIDE + ANIMAÇÕES NLA
# ==============================================================================

def create_character_armature(name, spec, collection):
    """
    Cria Armature humanoide com eixos consistentes para animação.
    spec contém posições das juntas (hips_z, spine_z, chest_z, neck_z, head_top_z,
    sh_pt_l, elb_pt_l, hand_pt_l, hip_x, knee_z, ankle_z, cape_y, cape_top_z, cape_mid_z, cape_bot_z).
    """
    arm_data = bpy.data.armatures.new(name + "_ArmatureData")
    arm_obj = bpy.data.objects.new(name + "_Rig", arm_data)
    collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="EDIT")

    eb = arm_data.edit_bones

    def add_bone(bname, head, tail, parent=None, roll_vec=(0, 1, 0), connect=False):
        b = eb.new(bname)
        b.head = Vector(head)
        b.tail = Vector(tail)
        b.align_roll(Vector(roll_vec))
        if parent is not None:
            b.parent = parent
            b.use_connect = connect
        return b

    hips_z = spec["hips_z"]
    spine_z = spec["spine_z"]
    chest_z = spec["chest_z"]
    neck_z = spec["neck_z"]
    head_top_z = spec["head_top_z"]
    sh = spec["sh_pt_l"]
    elb = spec["elb_pt_l"]
    hand = spec["hand_pt_l"]
    leg_x = spec["leg_x"]
    knee_z = spec["knee_z"]
    ankle_z = spec["ankle_z"]

    b_root = add_bone("Root", (0, 0, 0), (0, 0, 0.25), roll_vec=(0, -1, 0))
    b_hips = add_bone("Hips", (0, 0, hips_z), (0, 0, spine_z), parent=b_root, roll_vec=(0, -1, 0))
    b_spine = add_bone("Spine", (0, 0, spine_z), (0, 0, chest_z), parent=b_hips, roll_vec=(0, -1, 0), connect=True)
    b_chest = add_bone("Chest", (0, 0, chest_z), (0, 0, neck_z), parent=b_spine, roll_vec=(0, -1, 0), connect=True)
    add_bone("Head", (0, 0, neck_z), (0, 0, head_top_z), parent=b_chest, roll_vec=(0, -1, 0), connect=True)

    # Braço Esquerdo (-X)
    b_sh_l = add_bone("Shoulder.L", (-0.06, 0.0, sh.z - 0.02), sh, parent=b_chest, roll_vec=(0, 1, 0))
    b_up_l = add_bone("UpperArm.L", sh, elb, parent=b_sh_l, roll_vec=(0, 1, 0), connect=True)
    b_fo_l = add_bone("Forearm.L", elb, hand, parent=b_up_l, roll_vec=(0, 1, 0), connect=True)
    add_bone("Hand.L", hand, (hand.x - 0.02, hand.y + 0.03, hand.z - 0.11), parent=b_fo_l, roll_vec=(0, 1, 0), connect=True)

    # Braço Direito (+X)
    sh_r = Vector((-sh.x, sh.y, sh.z))
    elb_r = Vector((-elb.x, elb.y, elb.z))
    hand_r = Vector((-hand.x, hand.y, hand.z))
    b_sh_r = add_bone("Shoulder.R", (0.06, 0.0, sh.z - 0.02), sh_r, parent=b_chest, roll_vec=(0, 1, 0))
    b_up_r = add_bone("UpperArm.R", sh_r, elb_r, parent=b_sh_r, roll_vec=(0, 1, 0), connect=True)
    b_fo_r = add_bone("Forearm.R", elb_r, hand_r, parent=b_up_r, roll_vec=(0, 1, 0), connect=True)
    add_bone("Hand.R", hand_r, (hand_r.x + 0.02, hand_r.y + 0.03, hand_r.z - 0.11), parent=b_fo_r, roll_vec=(0, 1, 0), connect=True)

    # Capa traseira
    cy = spec["cape_y"]
    b_c1 = add_bone("Cape.1", (0, cy, spec["cape_top_z"]), (0, cy - 0.06, spec["cape_mid_z"]), parent=b_chest, roll_vec=(0, 1, 0))
    add_bone("Cape.2", (0, cy - 0.06, spec["cape_mid_z"]), (0, cy - 0.12, spec["cape_bot_z"]), parent=b_c1, roll_vec=(0, 1, 0), connect=True)

    # Pernas
    for suffix, sx in ((".L", -leg_x), (".R", leg_x)):
        b_th = add_bone("Thigh" + suffix, (sx, 0.0, hips_z), (sx, 0.0, knee_z), parent=b_hips, roll_vec=(0, 1, 0))
        b_sn = add_bone("Shin" + suffix, (sx, 0.0, knee_z), (sx, 0.0, ankle_z), parent=b_th, roll_vec=(0, 1, 0), connect=True)
        add_bone("Foot" + suffix, (sx, 0.0, ankle_z), (sx, 0.16, ankle_z), parent=b_sn, roll_vec=(0, 0, 1), connect=True)

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def _reset_pose(arm_obj):
    for pb in arm_obj.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)


def _key_pose(arm_obj, frame, pose_rots, hips_loc=(0.0, 0.0, 0.0)):
    pb_hips = arm_obj.pose.bones["Hips"]
    pb_hips.location = hips_loc
    pb_hips.keyframe_insert("location", frame=frame)
    for bname in BONE_NAMES:
        pb = arm_obj.pose.bones[bname]
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = pose_rots.get(bname, (0.0, 0.0, 0.0))
        pb.keyframe_insert("rotation_euler", frame=frame)


def build_unit_animations(arm_obj, unit_kind, spec):
    """
    Cria Actions em Blender 5.2 e publica em NLA Tracks para exportação GLB:
      - Idle   (frames 1..60, loop)
      - Walk   (frames 1..24, loop)
      - Attack (frames 1..24, one-shot)
      - Death  (frames 1..26, one-shot)
      - Gather (frames 1..28, loop, somente worker)
    """
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    if arm_obj.animation_data is None:
        arm_obj.animation_data_create()

    # Pose base de guarda pronta específica por classe
    if unit_kind == "worker":
        base_idle = {
            "UpperArm.L": (0.12, 0.0, 0.08),
            "Forearm.L": (0.28, 0.0, 0.0),
            "UpperArm.R": (0.22, 0.0, -0.10),
            "Forearm.R": (0.45, 0.0, 0.0),
        }
    elif unit_kind == "archer":
        base_idle = {
            "Spine": (-0.04, 0.14, 0.0),
            "Chest": (0.0, 0.10, 0.0),
            "Head": (0.0, -0.22, 0.0),
            "UpperArm.L": (0.28, 0.0, 0.10),
            "Forearm.L": (0.35, 0.0, 0.0),
            "Hand.L": (-0.35, 0.0, 0.0),
            "UpperArm.R": (0.12, 0.0, -0.12),
            "Forearm.R": (0.40, 0.0, 0.0),
            "Cape.1": (-0.12, 0.0, 0.0),
            "Cape.2": (-0.08, 0.0, 0.0),
        }
    else:  # soldier & knight
        base_idle = {
            "UpperArm.L": (0.26, 0.12, 0.06),
            "Forearm.L": (0.55, 0.25, 0.0),
            "UpperArm.R": (0.18, 0.0, -0.08),
            "Forearm.R": (0.42, 0.0, 0.0),
            "Cape.1": (-0.10, 0.0, 0.0),
            "Cape.2": (-0.06, 0.0, 0.0),
        }

    def merge(extra):
        d = dict(base_idle)
        for k, v in extra.items():
            if k in d:
                d[k] = (d[k][0] + v[0], d[k][1] + v[1], d[k][2] + v[2])
            else:
                d[k] = v
        return d

    clips = {}

    # 1. IDLE (respiração suave + leve balanço de guarda e capa)
    clips["Idle"] = (60, [
        (1, merge({}), (0.0, 0.0, 0.0)),
        (16, merge({"Spine": (-0.02, 0.0, 0.0), "Chest": (0.03, 0.0, 0.0), "Head": (-0.02, 0.02, 0.0),
                    "UpperArm.L": (0.03, 0.0, 0.02), "UpperArm.R": (0.03, 0.0, -0.02),
                    "Cape.1": (-0.05, 0.0, 0.0), "Cape.2": (-0.05, 0.0, 0.0)}), (0.0, 0.0, -0.01)),
        (31, merge({"Chest": (0.04, 0.0, 0.0), "Head": (0.0, -0.02, 0.0),
                    "Cape.1": (-0.08, 0.0, 0.0), "Cape.2": (-0.09, 0.0, 0.0)}), (0.0, 0.0, 0.008)),
        (46, merge({"Spine": (-0.01, 0.0, 0.0), "Chest": (0.02, 0.0, 0.0),
                    "UpperArm.L": (-0.02, 0.0, 0.0), "UpperArm.R": (-0.02, 0.0, 0.0),
                    "Cape.1": (-0.03, 0.0, 0.0)}), (0.0, 0.0, -0.005)),
        (60, merge({}), (0.0, 0.0, 0.0)),
    ])

    # 2. WALK (ciclo de marcha firme, joelho dobra para trás: Shin.x < 0, Thigh.x > 0 frente)
    stride = 0.56 if unit_kind != "knight" else 0.46
    w_arm_l = 0.18 if unit_kind in ("soldier", "knight", "archer") else 0.42
    w_arm_r = 0.28 if unit_kind in ("soldier", "knight") else 0.42
    clips["Walk"] = (24, [
        (1, {
            "Spine": (-0.08, 0.06, 0.0), "Chest": (-0.05, 0.08, 0.0), "Head": (0.10, -0.10, 0.0),
            "Thigh.L": (stride, 0.0, 0.0), "Shin.L": (-0.18, 0.0, 0.0), "Foot.L": (0.12, 0.0, 0.0),
            "Thigh.R": (-stride * 0.85, 0.0, 0.0), "Shin.R": (-0.36, 0.0, 0.0), "Foot.R": (-0.16, 0.0, 0.0),
            "UpperArm.L": (-w_arm_l, 0.0, 0.08), "Forearm.L": (0.45, 0.15 if unit_kind in ("soldier", "knight") else 0.0, 0.0),
            "UpperArm.R": (w_arm_r, 0.0, -0.08), "Forearm.R": (0.48, 0.0, 0.0),
            "Cape.1": (-0.28, 0.0, 0.0), "Cape.2": (-0.22, 0.0, 0.0),
        }, (0.0, 0.0, -0.04)),
        (7, {
            "Spine": (-0.06, 0.0, 0.0), "Chest": (-0.04, 0.0, 0.0), "Head": (0.08, 0.0, 0.0),
            "Thigh.L": (0.10, 0.0, 0.0), "Shin.L": (-0.12, 0.0, 0.0), "Foot.L": (0.0, 0.0, 0.0),
            "Thigh.R": (0.24, 0.0, 0.0), "Shin.R": (-0.75, 0.0, 0.0), "Foot.R": (-0.18, 0.0, 0.0),
            "UpperArm.L": (0.05, 0.0, 0.08), "Forearm.L": (0.42, 0.15 if unit_kind in ("soldier", "knight") else 0.0, 0.0),
            "UpperArm.R": (0.08, 0.0, -0.08), "Forearm.R": (0.42, 0.0, 0.0),
            "Cape.1": (-0.34, 0.0, 0.0), "Cape.2": (-0.28, 0.0, 0.0),
        }, (0.0, 0.0, 0.04)),
        (13, {
            "Spine": (-0.08, -0.06, 0.0), "Chest": (-0.05, -0.08, 0.0), "Head": (0.10, 0.10, 0.0),
            "Thigh.L": (-stride * 0.85, 0.0, 0.0), "Shin.L": (-0.36, 0.0, 0.0), "Foot.L": (-0.16, 0.0, 0.0),
            "Thigh.R": (stride, 0.0, 0.0), "Shin.R": (-0.18, 0.0, 0.0), "Foot.R": (0.12, 0.0, 0.0),
            "UpperArm.L": (w_arm_l + 0.18, 0.0, 0.08), "Forearm.L": (0.48, 0.15 if unit_kind in ("soldier", "knight") else 0.0, 0.0),
            "UpperArm.R": (-w_arm_r * 0.65, 0.0, -0.08), "Forearm.R": (0.40, 0.0, 0.0),
            "Cape.1": (-0.28, 0.0, 0.0), "Cape.2": (-0.22, 0.0, 0.0),
        }, (0.0, 0.0, -0.04)),
        (19, {
            "Spine": (-0.06, 0.0, 0.0), "Chest": (-0.04, 0.0, 0.0), "Head": (0.08, 0.0, 0.0),
            "Thigh.L": (0.24, 0.0, 0.0), "Shin.L": (-0.75, 0.0, 0.0), "Foot.L": (-0.18, 0.0, 0.0),
            "Thigh.R": (0.10, 0.0, 0.0), "Shin.R": (-0.12, 0.0, 0.0), "Foot.R": (0.0, 0.0, 0.0),
            "UpperArm.L": (0.05, 0.0, 0.08), "Forearm.L": (0.42, 0.15 if unit_kind in ("soldier", "knight") else 0.0, 0.0),
            "UpperArm.R": (0.08, 0.0, -0.08), "Forearm.R": (0.42, 0.0, 0.0),
            "Cape.1": (-0.34, 0.0, 0.0), "Cape.2": (-0.28, 0.0, 0.0),
        }, (0.0, 0.0, 0.04)),
        (24, {
            "Spine": (-0.08, 0.06, 0.0), "Chest": (-0.05, 0.08, 0.0), "Head": (0.10, -0.10, 0.0),
            "Thigh.L": (stride, 0.0, 0.0), "Shin.L": (-0.18, 0.0, 0.0), "Foot.L": (0.12, 0.0, 0.0),
            "Thigh.R": (-stride * 0.85, 0.0, 0.0), "Shin.R": (-0.36, 0.0, 0.0), "Foot.R": (-0.16, 0.0, 0.0),
            "UpperArm.L": (-w_arm_l, 0.0, 0.08), "Forearm.L": (0.45, 0.15 if unit_kind in ("soldier", "knight") else 0.0, 0.0),
            "UpperArm.R": (w_arm_r, 0.0, -0.08), "Forearm.R": (0.48, 0.0, 0.0),
            "Cape.1": (-0.28, 0.0, 0.0), "Cape.2": (-0.22, 0.0, 0.0),
        }, (0.0, 0.0, -0.04)),
    ])

    # 3. ATTACK (específico para arqueiro vs corpo a corpo)
    if unit_kind == "archer":
        clips["Attack"] = (24, [
            (1, merge({}), (0.0, 0.0, 0.0)),
            (8, {
                "Spine": (0.0, 0.42, 0.0), "Chest": (0.04, 0.25, 0.0), "Head": (0.0, -0.58, 0.0),
                "UpperArm.L": (1.18, 0.0, 0.35), "Forearm.L": (0.18, 0.0, 0.0), "Hand.L": (-1.30, 0.0, 0.0),
                "UpperArm.R": (0.98, 0.0, -0.35), "Forearm.R": (1.30, 0.0, 0.20), "Hand.R": (-0.35, 0.0, 0.0),
                "Thigh.L": (0.18, 0.0, 0.0), "Shin.L": (-0.18, 0.0, 0.0),
                "Thigh.R": (-0.18, 0.0, 0.0), "Shin.R": (-0.12, 0.0, 0.0),
                "Cape.1": (-0.18, 0.0, 0.0), "Cape.2": (-0.16, 0.0, 0.0),
            }, (0.0, 0.0, -0.03)),
            (13, {
                "Spine": (0.0, 0.46, 0.0), "Chest": (0.06, 0.28, 0.0), "Head": (0.0, -0.62, 0.0),
                "UpperArm.L": (1.22, 0.0, 0.35), "Forearm.L": (0.16, 0.0, 0.0), "Hand.L": (-1.32, 0.0, 0.0),
                "UpperArm.R": (0.88, 0.0, -0.32), "Forearm.R": (1.38, 0.0, 0.25), "Hand.R": (-0.35, 0.0, 0.0),
                "Thigh.L": (0.18, 0.0, 0.0), "Shin.L": (-0.18, 0.0, 0.0),
                "Thigh.R": (-0.18, 0.0, 0.0), "Shin.R": (-0.12, 0.0, 0.0),
                "Cape.1": (-0.20, 0.0, 0.0), "Cape.2": (-0.18, 0.0, 0.0),
            }, (0.0, 0.0, -0.03)),
            (17, {
                "Spine": (-0.02, 0.35, 0.0), "Chest": (0.02, 0.20, 0.0), "Head": (0.0, -0.48, 0.0),
                "UpperArm.L": (1.26, 0.0, 0.35), "Forearm.L": (0.14, 0.0, 0.0), "Hand.L": (-1.34, 0.0, 0.0),
                "UpperArm.R": (0.35, 0.0, -0.45), "Forearm.R": (0.95, 0.0, 0.0),
                "Thigh.L": (0.14, 0.0, 0.0), "Shin.L": (-0.12, 0.0, 0.0),
                "Cape.1": (-0.25, 0.0, 0.0), "Cape.2": (-0.22, 0.0, 0.0),
            }, (0.0, 0.0, -0.02)),
            (24, merge({}), (0.0, 0.0, 0.0)),
        ])
    else:
        atk_hand_strike = -1.25 if unit_kind == "knight" else -0.45
        atk_hand_follow = -0.85 if unit_kind == "knight" else -0.22
        clips["Attack"] = (24, [
            (1, merge({}), (0.0, 0.0, 0.0)),
            (7, {
                # Preparação / erguer arma para golpe
                "Spine": (0.10, -0.35, 0.0), "Chest": (0.12, -0.32, 0.0), "Head": (-0.14, 0.45, 0.0),
                "UpperArm.R": (1.65, -0.20, -0.30), "Forearm.R": (0.70, 0.0, 0.0), "Hand.R": (0.25, 0.0, 0.0),
                "UpperArm.L": (0.45, 0.25, 0.22), "Forearm.L": (0.65, 0.30, 0.0),
                "Thigh.L": (0.22, 0.0, 0.0), "Shin.L": (-0.22, 0.0, 0.0),
                "Thigh.R": (-0.20, 0.0, 0.0), "Shin.R": (-0.15, 0.0, 0.0),
                "Cape.1": (-0.22, 0.0, 0.0), "Cape.2": (-0.18, 0.0, 0.0),
            }, (0.0, -0.04, -0.03)),
            (13, {
                # Golpe descendente forte para frente
                "Spine": (-0.28, 0.40, 0.0), "Chest": (-0.20, 0.34, 0.0), "Head": (0.28, -0.45, 0.0),
                "UpperArm.R": (0.78, 0.25, -0.10), "Forearm.R": (0.22, 0.0, 0.0), "Hand.R": (atk_hand_strike, 0.0, 0.0),
                "UpperArm.L": (0.20, -0.10, 0.25), "Forearm.L": (0.52, 0.25, 0.0),
                "Thigh.L": (0.34, 0.0, 0.0), "Shin.L": (-0.34, 0.0, 0.0),
                "Thigh.R": (-0.30, 0.0, 0.0), "Shin.R": (-0.18, 0.0, 0.0),
                "Cape.1": (-0.42, 0.0, 0.0), "Cape.2": (-0.34, 0.0, 0.0),
            }, (0.0, 0.08, -0.07)),
            (18, {
                "Spine": (-0.18, 0.25, 0.0), "Chest": (-0.12, 0.20, 0.0), "Head": (0.18, -0.30, 0.0),
                "UpperArm.R": (0.55, 0.15, -0.10), "Forearm.R": (0.32, 0.0, 0.0), "Hand.R": (atk_hand_follow, 0.0, 0.0),
                "UpperArm.L": (0.24, 0.08, 0.14), "Forearm.L": (0.55, 0.25, 0.0),
                "Cape.1": (-0.28, 0.0, 0.0), "Cape.2": (-0.24, 0.0, 0.0),
            }, (0.0, 0.03, -0.03)),
            (24, merge({}), (0.0, 0.0, 0.0)),
        ])

    # 4. GATHER (somente worker — batida rítmica de picareta)
    if unit_kind == "worker":
        clips["Gather"] = (28, [
            (1, merge({}), (0.0, 0.0, 0.0)),
            (9, {
                "Spine": (0.14, -0.12, 0.0), "Chest": (0.10, -0.12, 0.0), "Head": (-0.12, 0.15, 0.0),
                "UpperArm.R": (1.75, 0.0, -0.15), "Forearm.R": (0.55, 0.0, 0.0), "Hand.R": (0.18, 0.0, 0.0),
                "UpperArm.L": (0.85, 0.0, -0.15), "Forearm.L": (0.65, 0.0, 0.0),
                "Thigh.L": (0.14, 0.0, 0.0), "Shin.L": (-0.16, 0.0, 0.0),
                "Thigh.R": (-0.14, 0.0, 0.0), "Shin.R": (-0.10, 0.0, 0.0),
            }, (0.0, 0.0, -0.02)),
            (16, {
                "Spine": (-0.36, 0.14, 0.0), "Chest": (-0.22, 0.10, 0.0), "Head": (0.24, -0.12, 0.0),
                "UpperArm.R": (0.68, 0.0, -0.08), "Forearm.R": (0.25, 0.0, 0.0), "Hand.R": (-0.38, 0.0, 0.0),
                "UpperArm.L": (0.48, 0.0, 0.05), "Forearm.L": (0.45, 0.0, 0.0),
                "Thigh.L": (0.24, 0.0, 0.0), "Shin.L": (-0.26, 0.0, 0.0),
                "Thigh.R": (-0.22, 0.0, 0.0), "Shin.R": (-0.18, 0.0, 0.0),
            }, (0.0, 0.04, -0.06)),
            (28, merge({}), (0.0, 0.0, 0.0)),
        ])

    # 5. DEATH (queda de joelhos e tombo de costas no chão)
    drop_z = -(spec["hips_z"] - 0.19)
    clips["Death"] = (26, [
        (1, merge({}), (0.0, 0.0, 0.0)),
        (8, {
            "Spine": (-0.32, 0.10, 0.0), "Chest": (-0.25, 0.0, 0.0), "Head": (0.25, 0.0, 0.0),
            "Thigh.L": (0.85, 0.0, 0.12), "Shin.L": (-1.45, 0.0, 0.0),
            "Thigh.R": (0.65, 0.0, -0.12), "Shin.R": (-1.35, 0.0, 0.0),
            "UpperArm.L": (0.35, 0.0, 0.35), "Forearm.L": (0.45, 0.0, 0.0),
            "UpperArm.R": (0.25, 0.0, -0.35), "Forearm.R": (0.45, 0.0, 0.0),
            "Cape.1": (-0.30, 0.0, 0.0),
        }, (0.0, -0.05, drop_z * 0.42)),
        (18, {
            "Hips": (1.28, 0.0, 0.08), "Spine": (0.12, 0.0, 0.0), "Chest": (0.08, 0.0, 0.0), "Head": (0.12, 0.12, 0.0),
            "Thigh.L": (0.15, 0.0, 0.14), "Shin.L": (-0.30, 0.0, 0.0),
            "Thigh.R": (0.12, 0.0, -0.14), "Shin.R": (-0.25, 0.0, 0.0),
            "UpperArm.L": (0.18, 0.0, 0.65), "Forearm.L": (0.35, 0.0, 0.0),
            "UpperArm.R": (0.15, 0.0, -0.65), "Forearm.R": (0.30, 0.0, 0.0),
            "Cape.1": (0.12, 0.0, 0.0),
        }, (0.0, -0.25, drop_z * 0.94)),
        (26, {
            "Hips": (1.46, 0.0, 0.10), "Spine": (0.06, 0.0, 0.0), "Chest": (0.04, 0.0, 0.0), "Head": (0.06, 0.18, 0.0),
            "Thigh.L": (0.06, 0.0, 0.16), "Shin.L": (-0.10, 0.0, 0.0),
            "Thigh.R": (0.04, 0.0, -0.16), "Shin.R": (-0.08, 0.0, 0.0),
            "UpperArm.L": (0.10, 0.0, 0.85), "Forearm.L": (0.25, 0.0, 0.0),
            "UpperArm.R": (0.08, 0.0, -0.82), "Forearm.R": (0.22, 0.0, 0.0),
            "Cape.1": (0.05, 0.0, 0.0),
        }, (0.0, -0.32, drop_z)),
    ])

    for anim_name, (end_frame, keyframes) in clips.items():
        _reset_pose(arm_obj)
        act = bpy.data.actions.new(anim_name)
        arm_obj.animation_data.action = act
        for frame, rots, hloc in keyframes:
            _key_pose(arm_obj, frame, rots, hips_loc=hloc)
        track = arm_obj.animation_data.nla_tracks.new()
        track.name = anim_name
        track.mute = False
        strip = track.strips.new(anim_name, 1, act)
        strip.name = anim_name
        strip.action_frame_start = 1
        strip.action_frame_end = end_frame

    arm_obj.animation_data.action = None
    _reset_pose(arm_obj)
    bpy.ops.object.mode_set(mode="OBJECT")


# ==============================================================================
# BUILDERS DOS 4 PERSONAGENS
# ==============================================================================

def _torso_weights_fn(hips_z, spine_z, chest_z, neck_z):
    def fn(_ri, _n, z):
        if z <= spine_z:
            t = max(0.0, min(1.0, (z - hips_z) / max(0.01, spine_z - hips_z)))
            return {BONE_IDX["Hips"]: 1.0 - t * 0.45, BONE_IDX["Spine"]: t * 0.45}
        elif z <= chest_z:
            t = max(0.0, min(1.0, (z - spine_z) / max(0.01, chest_z - spine_z)))
            return {BONE_IDX["Spine"]: 1.0 - t, BONE_IDX["Chest"]: t}
        else:
            return BONE_IDX["Chest"]
    return fn


def build_unit_worker(mats, col):
    spec = {
        "hips_z": 0.72, "spine_z": 0.88, "chest_z": 1.06, "neck_z": 1.24, "head_top_z": 1.56,
        "sh_pt_l": Vector((-0.24, 0.0, 1.18)),
        "elb_pt_l": Vector((-0.34, 0.02, 0.94)),
        "hand_pt_l": Vector((-0.37, 0.08, 0.72)),
        "leg_x": 0.13, "knee_z": 0.42, "ankle_z": 0.12,
        "cape_y": -0.18, "cape_top_z": 1.18, "cape_mid_z": 0.90, "cape_bot_z": 0.62,
    }
    arm_obj = create_character_armature("unit_worker", spec, col)
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()

    mlist = [
        mats["skin"],          # 0
        mats["hair"],          # 1
        mats["eye"],           # 2
        mats["tunic_cloth"],   # 3
        mats["trousers"],      # 4
        mats["leather"],       # 5
        mats["dark_leather"],  # 6
        mats["wood"],          # 7
        mats["steel"],         # 8
        mats["gold_trim"],     # 9
        mats["straw"],         # 10
        mats["team_primary"],  # 11
        mats["team_accent"],   # 12
    ]

    # Botas resistentes & calças arregaçadas
    add_boot_pair(bm, deform, spec["leg_x"], 0.30, 0.095, 6, 5,
                  BONE_IDX["Foot.L"], BONE_IDX["Foot.R"], BONE_IDX["Shin.L"], BONE_IDX["Shin.R"])
    add_leg_tubes(bm, deform, spec["leg_x"], spec["ankle_z"] + 0.14, spec["knee_z"], spec["hips_z"],
                  0.09, 0.115, 4, 4,
                  BONE_IDX["Shin.L"], BONE_IDX["Thigh.L"], BONE_IDX["Shin.R"], BONE_IDX["Thigh.R"], BONE_IDX["Hips"])

    # Túnica de linho rústico + avental de couro
    tw = _torso_weights_fn(spec["hips_z"], spec["spine_z"], spec["chest_z"], spec["neck_z"])
    tunic_rings = [
        (0.56, 0.25, 0.20, 0.0, 0.0),
        (0.72, 0.24, 0.19, 0.0, 0.0),
        (0.88, 0.22, 0.175, 0.0, 0.0),
        (1.06, 0.26, 0.195, 0.0, 0.0),
        (1.22, 0.24, 0.17, 0.0, 0.0),
        (1.27, 0.13, 0.12, 0.0, 0.0),
    ]
    add_loft(bm, deform, tunic_rings, segments=18, mat_idx=3, weights_fn=tw)

    # Colete/Avental de couro sobre o torso (folga limpa para evitar z-fighting)
    vest_rings = [
        (0.75, 0.258, 0.212, 0.0, 0.0),
        (0.88, 0.242, 0.198, 0.0, 0.0),
        (1.06, 0.278, 0.218, 0.0, 0.0),
        (1.18, 0.262, 0.200, 0.0, 0.0),
    ]
    add_loft(bm, deform, vest_rings, segments=16, mat_idx=5, weights_fn=tw, cap_bottom=True, cap_top=True)

    # Cinto + fivela latão + faixa do time + alforje + corda
    add_cylinder(bm, deform, 0.245, 0.245, 0.085, segments=18, center=(0.0, 0.0, 0.74),
                 scale=(1.02, 0.84, 1.0), mat_idx=6, weights=BONE_IDX["Hips"])
    add_beveled_box(bm, deform, 0.09, 0.04, 0.095, center=(0.0, 0.205, 0.74),
                    bevel_amt=0.015, mat_idx=9, weights=BONE_IDX["Hips"])
    # Faixa lateral de time pendendo da cintura
    add_tabard_panel(bm, deform, 0.14, 0.17, 0.74, 0.44, 0.16, True, 11, 12, thickness=0.020)

    # Lenço largo de time nos ombros (Mat_TeamPrimary)
    scarf_rings = [
        (1.14, 0.22, 0.19, 0.0, 0.0),
        (1.24, 0.16, 0.15, 0.0, 0.01),
        (1.29, 0.125, 0.125, 0.0, 0.01),
    ]
    add_loft(bm, deform, scarf_rings, segments=16, mat_idx=11, weights_fn=lambda *_: BONE_IDX["Chest"])
    add_beveled_box(bm, deform, 0.12, 0.05, 0.18, center=(0.05, 0.17, 1.12),
                    rot=(0.15, 0.0, -0.18), bevel_amt=0.015, mat_idx=11, weights=BONE_IDX["Chest"])

    # Bolsa de couro (quadril esquerdo) e rolo de corda (quadril direito)
    add_beveled_box(bm, deform, 0.11, 0.20, 0.20, center=(-0.25, -0.02, 0.64),
                    rot=(0.0, 0.12, 0.0), bevel_amt=0.025, mat_idx=5, weights=BONE_IDX["Hips"])
    add_cylinder(bm, deform, 0.08, 0.08, 0.06, segments=12, center=(0.24, -0.02, 0.66),
                 rot=(0.0, math.pi * 0.5, 0.15), mat_idx=10, weights=BONE_IDX["Hips"])

    # Braços e mãos
    add_arm_pair(bm, deform, spec["sh_pt_l"], spec["elb_pt_l"], spec["hand_pt_l"],
                 0.082, 0.070, 3, 0, 0)
    # Mangas arregaçadas no cotovelo
    for sx, b_up in ((-1.0, BONE_IDX["UpperArm.L"]), (1.0, BONE_IDX["UpperArm.R"])):
        add_cylinder(bm, deform, 0.085, 0.085, 0.05, segments=12,
                     center=(sx * 0.32, 0.015, 0.96), rot=(0.0, sx * -0.35, 0.0),
                     mat_idx=3, weights=b_up)

    # Cabeça estilizada com barba + chapéu de palha inclinado com faixa de time
    add_sculpted_head(bm, deform, (0.0, 0.01, 1.38), (0.98, 1.0, 1.04),
                      skin_mat=0, hair_mat=1, eye_mat=2, bone_idx=BONE_IDX["Head"], with_beard=True)

    # Chapéu de palha com aba dupla espessa (sem backface culling)
    hat_rot = (-0.20, 0.04, 0.0)
    hat_xform = Matrix.Translation((0.0, -0.02, 1.48)) @ Euler(hat_rot, "XYZ").to_matrix().to_4x4()
    top_rings = []
    bot_rings = []
    for rad, h_off in ((0.16, 0.0), (0.28, -0.01), (0.37, -0.035)):
        tr_v = []
        br_v = []
        for s in range(20):
            ang = (2.0 * math.pi * s) / 20
            wave = math.sin(ang * 2.0) * 0.015 * (rad / 0.37)
            px = math.cos(ang) * rad
            py = math.sin(ang) * rad
            vt = bm.verts.new(hat_xform @ Vector((px, py, h_off + wave + 0.008)))
            vb = bm.verts.new(hat_xform @ Vector((px, py, h_off + wave - 0.008)))
            tr_v.append(vt)
            br_v.append(vb)
        _set_verts_weights(bm, deform, tr_v + br_v, BONE_IDX["Head"])
        top_rings.append(tr_v)
        bot_rings.append(br_v)
    for i in range(len(top_rings) - 1):
        for s in range(20):
            ns = (s + 1) % 20
            bm.faces.new((top_rings[i][s], top_rings[i][ns], top_rings[i + 1][ns], top_rings[i + 1][s])).material_index = 10
            bm.faces.new((bot_rings[i][ns], bot_rings[i][s], bot_rings[i + 1][s], bot_rings[i + 1][ns])).material_index = 10
    for s in range(20):
        ns = (s + 1) % 20
        bm.faces.new((top_rings[-1][s], top_rings[-1][ns], bot_rings[-1][ns], bot_rings[-1][s])).material_index = 10
    # Copa do chapéu
    crown_center = hat_xform @ Vector((0.0, 0.0, 0.08))
    add_cylinder(bm, deform, 0.175, 0.125, 0.18, segments=20, center=crown_center, rot=hat_rot,
                 mat_idx=10, weights=BONE_IDX["Head"])
    # Faixa do time em volta da copa
    band_center = hat_xform @ Vector((0.0, 0.0, 0.025))
    add_cylinder(bm, deform, 0.178, 0.166, 0.055, segments=20, center=band_center, rot=hat_rot,
                 mat_idx=11, weights=BONE_IDX["Head"])
    # Laço/emblema na lateral da faixa
    knot_pos = hat_xform @ Vector((-0.175, 0.04, 0.025))
    add_sphere(bm, deform, 0.036, subdivisions=1, center=knot_pos, scale=(0.6, 1.2, 1.0),
               mat_idx=12, weights=BONE_IDX["Head"])

    # Picareta de ferro forjado na mão direita (Hand.R, apontando para frente +Y e cima +Z)
    hr = Vector((-spec["hand_pt_l"].x, spec["hand_pt_l"].y, spec["hand_pt_l"].z))
    pick_rot = (-1.05, 0.0, 0.0)
    pick_xform = Matrix.Translation(hr) @ Euler(pick_rot, "XYZ").to_matrix().to_4x4()
    handle_c = pick_xform @ Vector((0.0, 0.0, 0.28))
    add_cylinder(bm, deform, 0.026, 0.028, 0.88, segments=10, center=handle_c, rot=pick_rot,
                 mat_idx=7, weights=BONE_IDX["Hand.R"])
    # Cabeça metálica curva da picareta no topo do cabo
    head_p = pick_xform @ Vector((0.0, 0.0, 0.64))
    add_beveled_box(bm, deform, 0.075, 0.085, 0.095, center=head_p, rot=pick_rot,
                    bevel_amt=0.015, mat_idx=8, weights=BONE_IDX["Hand.R"])
    pick_pts = [
        (pick_xform @ Vector((0.0, -0.26, 0.59)), 0.014, 0.018),
        (pick_xform @ Vector((0.0, -0.14, 0.635)), 0.028, 0.036),
        (pick_xform @ Vector((0.0, 0.0, 0.645)), 0.034, 0.042),
        (pick_xform @ Vector((0.0, 0.15, 0.635)), 0.028, 0.036),
        (pick_xform @ Vector((0.0, 0.28, 0.58)), 0.010, 0.014),
    ]
    add_limb_chain(bm, deform, pick_pts, segments=8, mat_idx=8,
                   weights_fn=lambda *_: BONE_IDX["Hand.R"])

    mesh_obj = finalize_rigged_mesh("unit_worker", bm, mlist, col, arm_obj, split_angle_deg=54.0)
    build_unit_animations(arm_obj, "worker", spec)
    return arm_obj, mesh_obj


def build_unit_soldier(mats, col):
    spec = {
        "hips_z": 0.76, "spine_z": 0.94, "chest_z": 1.14, "neck_z": 1.33, "head_top_z": 1.72,
        "sh_pt_l": Vector((-0.27, 0.0, 1.26)),
        "elb_pt_l": Vector((-0.37, 0.04, 1.00)),
        "hand_pt_l": Vector((-0.40, 0.14, 0.78)),
        "leg_x": 0.14, "knee_z": 0.44, "ankle_z": 0.12,
        "cape_y": -0.20, "cape_top_z": 1.24, "cape_mid_z": 0.92, "cape_bot_z": 0.58,
    }
    arm_obj = create_character_armature("unit_soldier", spec, col)
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()

    mlist = [
        mats["skin"],          # 0
        mats["visor_dark"],    # 1
        mats["eye"],           # 2
        mats["chainmail"],     # 3
        mats["steel"],         # 4
        mats["iron"],          # 5
        mats["leather"],       # 6
        mats["dark_leather"],  # 7
        mats["gold_trim"],     # 8
        mats["team_primary"],  # 9
        mats["team_accent"],   # 10
    ]

    # Grevas de aço com joelheiras + coxas em cota de malha
    add_boot_pair(bm, deform, spec["leg_x"], 0.34, 0.102, 5, 4,
                  BONE_IDX["Foot.L"], BONE_IDX["Foot.R"], BONE_IDX["Shin.L"], BONE_IDX["Shin.R"], armored=True)
    add_leg_tubes(bm, deform, spec["leg_x"], spec["ankle_z"] + 0.16, spec["knee_z"], spec["hips_z"],
                  0.098, 0.125, 4, 3,
                  BONE_IDX["Shin.L"], BONE_IDX["Thigh.L"], BONE_IDX["Shin.R"], BONE_IDX["Thigh.R"], BONE_IDX["Hips"])

    # Peitoral de aço esculpido + gorjal
    tw = _torso_weights_fn(spec["hips_z"], spec["spine_z"], spec["chest_z"], spec["neck_z"])
    chest_rings = [
        (0.68, 0.25, 0.19, 0.0, 0.0),
        (0.84, 0.24, 0.18, 0.0, 0.0),
        (1.04, 0.29, 0.22, 0.0, 0.015),
        (1.22, 0.30, 0.22, 0.0, 0.010),
        (1.32, 0.16, 0.14, 0.0, 0.0),
    ]
    add_loft(bm, deform, chest_rings, segments=18, mat_idx=4, weights_fn=tw)
    # Cota de malha na saia inferior
    add_cylinder(bm, deform, 0.28, 0.25, 0.24, segments=18, center=(0.0, 0.0, 0.66),
                 scale=(1.02, 0.84, 1.0), mat_idx=3, weights=BONE_IDX["Hips"])

    # Tabardo heráldico frontal e traseiro com barra dourada
    add_tabard_panel(bm, deform, 0.25, 0.31, 1.24, 0.44, 0.195, True, 9, 8, thickness=0.024)
    add_tabard_panel(bm, deform, 0.25, 0.31, 1.24, 0.44, -0.195, False, 9, 8, thickness=0.024)

    # Cinturão de couro + fivela + bainha no quadril esquerdo
    add_cylinder(bm, deform, 0.255, 0.255, 0.09, segments=18, center=(0.0, 0.0, 0.78),
                 scale=(1.04, 0.86, 1.0), mat_idx=7, weights=BONE_IDX["Hips"])
    add_beveled_box(bm, deform, 0.09, 0.04, 0.10, center=(0.0, 0.225, 0.78),
                    bevel_amt=0.015, mat_idx=8, weights=BONE_IDX["Hips"])
    add_cylinder(bm, deform, 0.028, 0.018, 0.68, segments=8, center=(-0.27, -0.12, 0.56),
                 rot=(-0.65, 0.15, 0.0), mat_idx=7, weights=BONE_IDX["Hips"])

    # Braços com malha + braçadeiras de aço + ombreiras curvas
    add_arm_pair(bm, deform, spec["sh_pt_l"], spec["elb_pt_l"], spec["hand_pt_l"],
                 0.088, 0.078, 3, 4, 5)
    add_pauldron_cup(bm, deform, "L", (-0.30, 0.0, 1.24), 0.155, 4, 8, BONE_IDX["UpperArm.L"])
    add_pauldron_cup(bm, deform, "R", (0.30, 0.0, 1.24), 0.155, 4, 8, BONE_IDX["UpperArm.R"])

    # Cabeça + Elmo Barbuta / Sallet elegante com viseira estreita, banda dourada e penacho
    add_sculpted_head(bm, deform, (0.0, 0.01, 1.46), (0.94, 0.96, 1.0),
                      skin_mat=0, hair_mat=1, eye_mat=2, bone_idx=BONE_IDX["Head"], with_hair=False)
    # Calota arredondada + protetor facial e nuca do elmo
    helm_rings = [
        (1.36, 0.172, 0.184, 0.0, -0.022),
        (1.48, 0.184, 0.194, 0.0, -0.012),
        (1.57, 0.174, 0.185, 0.0, 0.0),
        (1.65, 0.130, 0.140, 0.0, 0.0),
        (1.70, 0.055, 0.065, 0.0, 0.0),
    ]
    add_loft(bm, deform, helm_rings, segments=18, mat_idx=4, weights_fn=lambda *_: BONE_IDX["Head"])
    # Aba frontal da viseira (forma uma fenda T elegante em vez de retângulos quadrados)
    add_beveled_box(bm, deform, 0.21, 0.055, 0.048, center=(0.0, 0.165, 1.54),
                    rot=(-0.15, 0.0, 0.0), bevel_amt=0.012, mat_idx=4, weights=BONE_IDX["Head"])
    add_cylinder(bm, deform, 0.188, 0.184, 0.036, segments=18, center=(0.0, 0.0, 1.55),
                 mat_idx=8, weights=BONE_IDX["Head"])
    add_beveled_box(bm, deform, 0.036, 0.048, 0.13, center=(0.0, 0.178, 1.46),
                    bevel_amt=0.01, mat_idx=4, weights=BONE_IDX["Head"])
    # Fenda escura estreita dos olhos sob a viseira
    add_beveled_box(bm, deform, 0.165, 0.035, 0.028, center=(0.0, 0.168, 1.49),
                    bevel_amt=0.006, mat_idx=1, weights=BONE_IDX["Head"])

    # Crista e penacho arqueado do time (Mat_TeamAccent)
    add_beveled_box(bm, deform, 0.042, 0.22, 0.055, center=(0.0, 0.0, 1.69),
                    bevel_amt=0.012, mat_idx=8, weights=BONE_IDX["Head"])
    plume_pts = [
        (Vector((0.0, 0.09, 1.71)), 0.044, 0.044),
        (Vector((0.0, 0.01, 1.81)), 0.062, 0.072),
        (Vector((0.0, -0.11, 1.80)), 0.058, 0.065),
        (Vector((0.0, -0.23, 1.68)), 0.042, 0.048),
        (Vector((0.0, -0.29, 1.52)), 0.020, 0.024),
    ]
    add_limb_chain(bm, deform, plume_pts, segments=10, mat_idx=10,
                   weights_fn=lambda *_: BONE_IDX["Head"])

    # Escudo Heater 3D curvo na mão esquerda (Hand.L)
    add_curved_shield(
        bm, deform, width=0.52, height=0.66, curve_depth=0.09, thickness=0.036,
        center=(spec["hand_pt_l"].x - 0.12, spec["hand_pt_l"].y + 0.04, spec["hand_pt_l"].z + 0.04),
        rot=(0.05, 0.08, -0.45),
        rim_mat=4, face_mat=9, emblem_mat=8, bone_idx=BONE_IDX["Hand.L"], shape="heater"
    )

    # Espada Larga Medieval na mão direita (Hand.R, apontando para frente +Y e cima +Z)
    hr = Vector((-spec["hand_pt_l"].x, spec["hand_pt_l"].y, spec["hand_pt_l"].z))
    sword_rot = (-1.05, 0.0, 0.0)
    sword_xform = Matrix.Translation(hr) @ Euler(sword_rot, "XYZ").to_matrix().to_4x4()
    # Punho + pomo dourado + guarda-mão arqueada
    add_cylinder(bm, deform, 0.024, 0.022, 0.20, segments=10,
                 center=sword_xform @ Vector((0.0, 0.0, 0.02)), rot=sword_rot,
                 mat_idx=7, weights=BONE_IDX["Hand.R"])
    add_sphere(bm, deform, 0.042, subdivisions=2,
               center=sword_xform @ Vector((0.0, 0.0, -0.10)), scale=(1.0, 1.0, 0.8),
               mat_idx=8, weights=BONE_IDX["Hand.R"])
    add_beveled_box(bm, deform, 0.036, 0.24, 0.038,
                    center=sword_xform @ Vector((0.0, 0.0, 0.13)), rot=sword_rot,
                    bevel_amt=0.01, mat_idx=8, weights=BONE_IDX["Hand.R"])
    # Lâmina de seção diamante
    add_blade_diamond(bm, deform, length=0.78, base_w=0.075, tip_w=0.032, thick=0.026,
                      center=sword_xform @ Vector((0.0, 0.0, 0.15)), rot=sword_rot,
                      mat_idx=4, bone_idx=BONE_IDX["Hand.R"])

    mesh_obj = finalize_rigged_mesh("unit_soldier", bm, mlist, col, arm_obj, split_angle_deg=52.0)
    build_unit_animations(arm_obj, "soldier", spec)
    return arm_obj, mesh_obj


def build_unit_archer(mats, col):
    spec = {
        "hips_z": 0.74, "spine_z": 0.92, "chest_z": 1.11, "neck_z": 1.29, "head_top_z": 1.64,
        "sh_pt_l": Vector((-0.23, 0.0, 1.23)),
        "elb_pt_l": Vector((-0.31, 0.04, 0.98)),
        "hand_pt_l": Vector((-0.34, 0.14, 0.76)),
        "leg_x": 0.125, "knee_z": 0.43, "ankle_z": 0.12,
        "cape_y": -0.17, "cape_top_z": 1.24, "cape_mid_z": 0.86, "cape_bot_z": 0.42,
    }
    arm_obj = create_character_armature("unit_archer", spec, col)
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()

    mlist = [
        mats["skin"],          # 0
        mats["hair"],          # 1
        mats["eye"],           # 2
        mats["archer_green"],  # 3
        mats["leather"],       # 4
        mats["dark_leather"],  # 5
        mats["wood"],          # 6
        mats["steel"],         # 7
        mats["gold_trim"],     # 8
        mats["bowstring"],     # 9
        mats["team_primary"],  # 10
        mats["team_cape"],     # 11
        mats["team_accent"],   # 12
    ]

    # Botas de caçador e calças justas
    add_boot_pair(bm, deform, spec["leg_x"], 0.32, 0.088, 5, 4,
                  BONE_IDX["Foot.L"], BONE_IDX["Foot.R"], BONE_IDX["Shin.L"], BONE_IDX["Shin.R"])
    add_leg_tubes(bm, deform, spec["leg_x"], spec["ankle_z"] + 0.15, spec["knee_z"], spec["hips_z"],
                  0.084, 0.106, 5, 5,
                  BONE_IDX["Shin.L"], BONE_IDX["Thigh.L"], BONE_IDX["Shin.R"], BONE_IDX["Thigh.R"], BONE_IDX["Hips"])

    # Gibão acolchoado verde-floresta + saia da túnica
    tw = _torso_weights_fn(spec["hips_z"], spec["spine_z"], spec["chest_z"], spec["neck_z"])
    jerkin_rings = [
        (0.54, 0.24, 0.19, 0.0, 0.0),
        (0.74, 0.21, 0.165, 0.0, 0.0),
        (0.92, 0.20, 0.155, 0.0, 0.0),
        (1.12, 0.245, 0.185, 0.0, 0.01),
        (1.26, 0.215, 0.160, 0.0, 0.0),
        (1.31, 0.125, 0.120, 0.0, 0.0),
    ]
    add_loft(bm, deform, jerkin_rings, segments=18, mat_idx=3, weights_fn=tw)

    # Cinto, bolsa de munição e faixa lateral de time
    add_cylinder(bm, deform, 0.22, 0.22, 0.08, segments=18, center=(0.0, 0.0, 0.75),
                 scale=(1.02, 0.84, 1.0), mat_idx=4, weights=BONE_IDX["Hips"])
    add_beveled_box(bm, deform, 0.08, 0.04, 0.085, center=(0.0, 0.19, 0.75),
                    bevel_amt=0.012, mat_idx=8, weights=BONE_IDX["Hips"])
    add_beveled_box(bm, deform, 0.09, 0.16, 0.16, center=(0.22, 0.0, 0.67),
                    bevel_amt=0.02, mat_idx=4, weights=BONE_IDX["Hips"])
    add_tabard_panel(bm, deform, 0.18, 0.22, 0.75, 0.44, 0.16, True, 10, 8, thickness=0.020)

    # Talabarte diagonal de couro + manto nos ombros (Mat_TeamPrimary)
    add_cylinder(bm, deform, 0.04, 0.04, 0.56, segments=10, center=(0.0, 0.0, 1.03),
                 rot=(0.0, 0.62, 0.0), scale=(1.0, 4.7, 1.0), mat_idx=4, weights=BONE_IDX["Chest"])
    mantle_rings = [
        (1.16, 0.245, 0.195, 0.0, 0.0),
        (1.26, 0.175, 0.165, 0.0, 0.0),
        (1.31, 0.135, 0.135, 0.0, 0.0),
    ]
    add_loft(bm, deform, mantle_rings, segments=18, mat_idx=10, weights_fn=lambda *_: BONE_IDX["Chest"])

    # Capa longa fluida do patrulheiro (Mat_TeamCape)
    add_flowing_cape(bm, deform, 0.44, 0.66, 1.24, 0.36, -0.17, 0.24, 11, border_mat_idx=10)

    # Aljava inclinada nas costas com 5 flechas empenadas (Mat_TeamAccent)
    quiv_rot = (0.20, 0.38, 0.0)
    quiv_xform = Matrix.Translation((-0.09, -0.22, 0.98)) @ Euler(quiv_rot, "XYZ").to_matrix().to_4x4()
    add_cylinder(bm, deform, 0.068, 0.052, 0.48, segments=12,
                 center=quiv_xform @ Vector((0, 0, 0)), rot=quiv_rot,
                 mat_idx=4, weights=BONE_IDX["Chest"])
    add_cylinder(bm, deform, 0.074, 0.074, 0.04, segments=12,
                 center=quiv_xform @ Vector((0, 0, 0.23)), rot=quiv_rot,
                 mat_idx=8, weights=BONE_IDX["Chest"])
    for ax, ay in ((-0.025, 0.0), (0.025, 0.0), (0.0, 0.025), (-0.015, -0.022), (0.018, -0.020)):
        shaft_p = quiv_xform @ Vector((ax, ay, 0.26))
        fletch_p = quiv_xform @ Vector((ax, ay, 0.35))
        add_cylinder(bm, deform, 0.011, 0.011, 0.24, segments=6, center=shaft_p, rot=quiv_rot,
                     mat_idx=6, weights=BONE_IDX["Chest"])
        add_beveled_box(bm, deform, 0.036, 0.012, 0.075, center=fletch_p, rot=quiv_rot,
                        bevel_amt=0.003, mat_idx=12, weights=BONE_IDX["Chest"])

    # Braços, braçadeira esquerda e luva direita
    add_arm_pair(bm, deform, spec["sh_pt_l"], spec["elb_pt_l"], spec["hand_pt_l"],
                 0.076, 0.066, 3, 4, 0)
    # Braçadeira esquerda reforçada
    bracer_c = spec["elb_pt_l"].lerp(spec["hand_pt_l"], 0.55)
    add_cylinder(bm, deform, 0.072, 0.064, 0.20, segments=12, center=bracer_c,
                 rot=(-0.38, 0.14, 0.0), mat_idx=5, weights=BONE_IDX["Forearm.L"])

    # Cabeça + Capuz drapaedo de Arqueiro com aba colorida do time
    add_sculpted_head(bm, deform, (0.0, 0.01, 1.43), (0.94, 0.96, 1.0),
                      skin_mat=0, hair_mat=1, eye_mat=2, bone_idx=BONE_IDX["Head"], with_hair=False)
    # Capuz envolvido ao redor da cabeça com bico traseiro e borda limpa do time
    hood_rings = [
        (1.30, 0.168, 0.180, 0.0, -0.03),
        (1.44, 0.188, 0.200, 0.0, -0.03),
        (1.59, 0.184, 0.212, 0.0, -0.025),
        (1.66, 0.135, 0.195, 0.0, -0.065),
        (1.61, 0.045, 0.075, 0.0, -0.22),
    ]
    add_loft(bm, deform, hood_rings, segments=16, mat_idx=3, weights_fn=lambda *_: BONE_IDX["Head"])
    # Arco frontal colorido abraçando a abertura do capuz sem vazar atrás
    cowl_pts = [
        (Vector((-0.145, 0.075, 1.35)), 0.024, 0.024),
        (Vector((-0.155, 0.095, 1.48)), 0.026, 0.026),
        (Vector((-0.095, 0.135, 1.565)), 0.028, 0.028),
        (Vector((0.0, 0.155, 1.585)), 0.030, 0.030),
        (Vector((0.095, 0.135, 1.565)), 0.028, 0.028),
        (Vector((0.155, 0.095, 1.48)), 0.026, 0.026),
        (Vector((0.145, 0.075, 1.35)), 0.024, 0.024),
    ]
    add_limb_chain(bm, deform, cowl_pts, segments=10, mat_idx=10,
                   weights_fn=lambda *_: BONE_IDX["Head"])

    # Arco Longo Recurvo na mão esquerda (Hand.L) + corda + flecha encaixada
    hl = spec["hand_pt_l"]
    bow_pts = [
        (hl + Vector((0.0, -0.14, -0.58)), 0.015, 0.014),
        (hl + Vector((0.0, -0.03, -0.42)), 0.020, 0.018),
        (hl + Vector((0.0, 0.03, -0.18)), 0.025, 0.022),
        (hl + Vector((0.0, 0.04, 0.0)), 0.028, 0.025),
        (hl + Vector((0.0, 0.03, 0.18)), 0.025, 0.022),
        (hl + Vector((0.0, -0.03, 0.42)), 0.020, 0.018),
        (hl + Vector((0.0, -0.14, 0.58)), 0.015, 0.014),
    ]
    add_limb_chain(bm, deform, bow_pts, segments=10, mat_idx=6, weights_fn=lambda *_: BONE_IDX["Hand.L"])
    # Empunhadura em couro + pontas de chifre dourado
    add_cylinder(bm, deform, 0.031, 0.031, 0.14, segments=10,
                 center=hl + Vector((0.0, 0.04, 0.0)), mat_idx=4, weights=BONE_IDX["Hand.L"])
    for tz in (-0.58, 0.58):
        add_sphere(bm, deform, 0.022, subdivisions=1,
                   center=hl + Vector((0.0, -0.14, tz)), mat_idx=8, weights=BONE_IDX["Hand.L"])
    # Corda do arco
    add_cylinder(bm, deform, 0.005, 0.005, 1.15, segments=6,
                 center=hl + Vector((0.0, -0.14, 0.0)), mat_idx=9, weights=BONE_IDX["Hand.L"])
    # Flecha posicionada no arco
    arr_c = hl + Vector((0.025, 0.06, 0.02))
    add_cylinder(bm, deform, 0.011, 0.011, 0.56, segments=6, center=arr_c,
                 rot=(math.pi * 0.5, 0.0, 0.0), mat_idx=6, weights=BONE_IDX["Hand.L"])
    add_cylinder(bm, deform, 0.022, 0.003, 0.08, segments=6,
                 center=arr_c + Vector((0.0, 0.30, 0.0)), rot=(-math.pi * 0.5, 0.0, 0.0),
                 mat_idx=7, weights=BONE_IDX["Hand.L"])
    add_beveled_box(bm, deform, 0.034, 0.075, 0.012,
                    center=arr_c + Vector((0.0, -0.22, 0.0)), bevel_amt=0.002,
                    mat_idx=12, weights=BONE_IDX["Hand.L"])

    mesh_obj = finalize_rigged_mesh("unit_archer", bm, mlist, col, arm_obj, split_angle_deg=54.0)
    build_unit_animations(arm_obj, "archer", spec)
    return arm_obj, mesh_obj


def build_unit_knight(mats, col):
    spec = {
        "hips_z": 0.84, "spine_z": 1.04, "chest_z": 1.26, "neck_z": 1.49, "head_top_z": 1.94,
        "sh_pt_l": Vector((-0.32, 0.0, 1.42)),
        "elb_pt_l": Vector((-0.44, 0.04, 1.12)),
        "hand_pt_l": Vector((-0.47, 0.16, 0.86)),
        "leg_x": 0.16, "knee_z": 0.48, "ankle_z": 0.14,
        "cape_y": -0.24, "cape_top_z": 1.40, "cape_mid_z": 0.94, "cape_bot_z": 0.36,
    }
    arm_obj = create_character_armature("unit_knight", spec, col)
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()

    mlist = [
        mats["visor_dark"],    # 0
        mats["steel"],         # 1
        mats["iron"],          # 2
        mats["chainmail"],     # 3
        mats["gold_trim"],     # 4
        mats["dark_leather"],  # 5
        mats["wood"],          # 6
        mats["team_primary"],  # 7
        mats["team_cape"],     # 8
        mats["team_accent"],   # 9
    ]

    # Grevas pesadas + escarpins + joelheiras aladas + coxotes sobre malha
    add_boot_pair(bm, deform, spec["leg_x"], 0.38, 0.116, 1, 4,
                  BONE_IDX["Foot.L"], BONE_IDX["Foot.R"], BONE_IDX["Shin.L"], BONE_IDX["Shin.R"], armored=True)
    add_leg_tubes(bm, deform, spec["leg_x"], spec["ankle_z"] + 0.18, spec["knee_z"], spec["hips_z"],
                  0.112, 0.142, 1, 1,
                  BONE_IDX["Shin.L"], BONE_IDX["Thigh.L"], BONE_IDX["Shin.R"], BONE_IDX["Thigh.R"], BONE_IDX["Hips"])

    # Saia de malha + escarcelas (tassets) segmentadas com borda dourada
    add_cylinder(bm, deform, 0.32, 0.28, 0.26, segments=20, center=(0.0, 0.0, 0.74),
                 scale=(1.04, 0.86, 1.0), mat_idx=3, weights=BONE_IDX["Hips"])
    for sx in (-0.23, 0.23):
        add_beveled_box(bm, deform, 0.14, 0.22, 0.21, center=(sx, 0.02, 0.77),
                        rot=(0.0, -0.18 if sx < 0 else 0.18, 0.0), bevel_amt=0.025,
                        mat_idx=1, weights=BONE_IDX["Hips"])
        add_beveled_box(bm, deform, 0.15, 0.23, 0.045, center=(sx, 0.02, 0.67),
                        rot=(0.0, -0.18 if sx < 0 else 0.18, 0.0), bevel_amt=0.015,
                        mat_idx=4, weights=BONE_IDX["Hips"])

    # Couraça real imponente + emblema solar dourado no peito
    tw = _torso_weights_fn(spec["hips_z"], spec["spine_z"], spec["chest_z"], spec["neck_z"])
    cuirass_rings = [
        (0.76, 0.28, 0.22, 0.0, 0.0),
        (0.94, 0.27, 0.21, 0.0, 0.0),
        (1.18, 0.34, 0.26, 0.0, 0.02),
        (1.38, 0.35, 0.25, 0.0, 0.015),
        (1.48, 0.19, 0.16, 0.0, 0.0),
    ]
    add_loft(bm, deform, cuirass_rings, segments=20, mat_idx=1, weights_fn=tw)
    # Gorjal dourado e medalhão peitoral
    add_cylinder(bm, deform, 0.20, 0.17, 0.09, segments=18, center=(0.0, 0.0, 1.46),
                 mat_idx=4, weights=BONE_IDX["Chest"])
    add_sphere(bm, deform, 0.08, subdivisions=2, center=(0.0, 0.24, 1.24),
               scale=(1.0, 0.45, 1.2), mat_idx=4, weights=BONE_IDX["Chest"])

    # Tabardo Real longo com barra dourada + cinto real
    add_tabard_panel(bm, deform, 0.27, 0.35, 1.32, 0.44, 0.23, True, 7, 4, thickness=0.026)
    add_tabard_panel(bm, deform, 0.27, 0.35, 1.32, 0.44, -0.22, False, 7, 4, thickness=0.026)
    add_cylinder(bm, deform, 0.29, 0.29, 0.10, segments=20, center=(0.0, 0.0, 0.87),
                 scale=(1.04, 0.86, 1.0), mat_idx=5, weights=BONE_IDX["Hips"])
    add_beveled_box(bm, deform, 0.11, 0.05, 0.11, center=(0.0, 0.255, 0.87),
                    bevel_amt=0.018, mat_idx=4, weights=BONE_IDX["Hips"])

    # Grande Capa Real fluida presa por broches dourados nos ombros
    add_flowing_cape(bm, deform, 0.54, 0.84, 1.40, 0.32, -0.23, 0.30, 8, border_mat_idx=4)
    for sx in (-0.21, 0.21):
        add_sphere(bm, deform, 0.065, subdivisions=2, center=(sx, 0.13, 1.40),
                   scale=(1.0, 0.6, 1.0), mat_idx=4, weights=BONE_IDX["Chest"])

    # Braços pesadamente blindados + Ombreiras Aladas Reais
    add_arm_pair(bm, deform, spec["sh_pt_l"], spec["elb_pt_l"], spec["hand_pt_l"],
                 0.102, 0.090, 2, 1, 1)
    for side, sx, b_arm in (("L", -1.0, BONE_IDX["UpperArm.L"]), ("R", 1.0, BONE_IDX["UpperArm.R"])):
        pc = (sx * 0.36, 0.0, 1.40)
        add_pauldron_cup(bm, deform, side, pc, 0.20, 1, 4, b_arm)
        # Asa/crista heráldica dourada + faixa do time na ombreira
        add_beveled_box(bm, deform, 0.05, 0.22, 0.16, center=(sx * 0.43, 0.0, 1.52),
                        rot=(0.0, sx * 0.32, 0.0), bevel_amt=0.015, mat_idx=4, weights=b_arm)
        add_beveled_box(bm, deform, 0.12, 0.24, 0.07, center=(sx * 0.38, 0.0, 1.41),
                        rot=(0.0, sx * 0.35, 0.0), bevel_amt=0.015, mat_idx=7, weights=b_arm)

    # Grande Elmo Sugarloaf Coroado + Coroa Real de 6 Pontas + Grande Penacho
    ghelm_rings = [
        (1.48, 0.195, 0.210, 0.0, -0.01),
        (1.62, 0.198, 0.215, 0.0, 0.005),
        (1.74, 0.185, 0.198, 0.0, 0.0),
        (1.83, 0.140, 0.150, 0.0, -0.01),
        (1.89, 0.070, 0.080, 0.0, -0.01),
    ]
    add_loft(bm, deform, ghelm_rings, segments=18, mat_idx=1, weights_fn=lambda *_: BONE_IDX["Head"])
    # Fenda estreita dos olhos + reforço em cruz dourada frontal
    add_beveled_box(bm, deform, 0.21, 0.035, 0.028, center=(0.0, 0.198, 1.66),
                    bevel_amt=0.006, mat_idx=0, weights=BONE_IDX["Head"])
    add_beveled_box(bm, deform, 0.045, 0.045, 0.23, center=(0.0, 0.205, 1.63),
                    bevel_amt=0.01, mat_idx=4, weights=BONE_IDX["Head"])
    add_beveled_box(bm, deform, 0.23, 0.040, 0.040, center=(0.0, 0.200, 1.62),
                    bevel_amt=0.01, mat_idx=4, weights=BONE_IDX["Head"])
    # Aro da Coroa Real + 6 pontas douradas
    add_cylinder(bm, deform, 0.192, 0.202, 0.068, segments=18, center=(0.0, 0.0, 1.77),
                 mat_idx=4, weights=BONE_IDX["Head"])
    for p_i in range(6):
        ang = (2.0 * math.pi * p_i) / 6.0 + math.pi / 6.0
        px = math.cos(ang) * 0.190
        py = math.sin(ang) * 0.190
        add_cylinder(bm, deform, 0.042, 0.006, 0.105, segments=6,
                     center=(px, py, 1.85), mat_idx=4, weights=BONE_IDX["Head"])
    # Grande penacho real esvoaçante (Mat_TeamAccent)
    k_plume = [
        (Vector((0.0, 0.07, 1.87)), 0.055, 0.055),
        (Vector((0.0, -0.02, 2.02)), 0.078, 0.088),
        (Vector((0.0, -0.18, 2.00)), 0.072, 0.082),
        (Vector((0.0, -0.32, 1.85)), 0.052, 0.060),
        (Vector((0.0, -0.40, 1.62)), 0.022, 0.028),
    ]
    add_limb_chain(bm, deform, k_plume, segments=12, mat_idx=9, weights_fn=lambda *_: BONE_IDX["Head"])

    # Grande Escudo Pipa Real (Kite Shield) na mão esquerda (Hand.L)
    add_curved_shield(
        bm, deform, width=0.58, height=0.86, curve_depth=0.10, thickness=0.042,
        center=(spec["hand_pt_l"].x - 0.14, spec["hand_pt_l"].y + 0.04, spec["hand_pt_l"].z + 0.06),
        rot=(0.04, 0.08, -0.46),
        rim_mat=4, face_mat=7, emblem_mat=4, bone_idx=BONE_IDX["Hand.L"], shape="kite"
    )

    # Grande Alabarda Real na mão direita (Hand.R) com lâmina crescente esculpida
    hr = Vector((-spec["hand_pt_l"].x, spec["hand_pt_l"].y, spec["hand_pt_l"].z))
    halb_rot = (-0.28, 0.0, 0.0)
    hx = Matrix.Translation(hr) @ Euler(halb_rot, "XYZ").to_matrix().to_4x4()
    add_cylinder(bm, deform, 0.030, 0.030, 1.92, segments=12,
                 center=hx @ Vector((0.0, 0.0, 0.34)), rot=halb_rot,
                 mat_idx=6, weights=BONE_IDX["Hand.R"])
    # Ponteira inferior e colar dourado superior
    add_cylinder(bm, deform, 0.036, 0.008, 0.14, segments=8,
                 center=hx @ Vector((0.0, 0.0, -0.66)), rot=(halb_rot[0] + math.pi, 0.0, 0.0),
                 mat_idx=2, weights=BONE_IDX["Hand.R"])
    add_cylinder(bm, deform, 0.046, 0.046, 0.14, segments=12,
                 center=hx @ Vector((0.0, 0.0, 1.18)), rot=halb_rot,
                 mat_idx=4, weights=BONE_IDX["Hand.R"])
    # Ponta de lança superior em diamante
    add_blade_diamond(bm, deform, length=0.44, base_w=0.085, tip_w=0.03, thick=0.030,
                      center=hx @ Vector((0.0, 0.0, 1.24)), rot=halb_rot,
                      mat_idx=1, bone_idx=BONE_IDX["Hand.R"])
    # Lâmina crescente curva de alabarda (+Y) com gume chanfrado e guarnição dourada
    crescent_pts = [
        (0.03, 1.24), (0.14, 1.29), (0.25, 1.35),
        (0.28, 1.24), (0.29, 1.12), (0.26, 1.00),
        (0.16, 1.04), (0.03, 1.09),
    ]
    axe_f = []
    axe_b = []
    for cy_o, cz_o in crescent_pts:
        is_edge = (cy_o >= 0.24)
        ht = 0.004 if is_edge else 0.015
        vf = bm.verts.new(hx @ Vector((ht, cy_o, cz_o)))
        vb = bm.verts.new(hx @ Vector((-ht, cy_o, cz_o)))
        axe_f.append(vf)
        axe_b.append(vb)
    _set_verts_weights(bm, deform, axe_f + axe_b, BONE_IDX["Hand.R"])
    # Centro interno para formar leque limpo sem polígonos côncavos
    cf = bm.verts.new(hx @ Vector((0.018, 0.15, 1.15)))
    cb = bm.verts.new(hx @ Vector((-0.018, 0.15, 1.15)))
    _set_verts_weights(bm, deform, [cf, cb], BONE_IDX["Hand.R"])
    n_cp = len(crescent_pts)
    for i in range(n_cp):
        ni = (i + 1) % n_cp
        bm.faces.new((cf, axe_f[i], axe_f[ni])).material_index = 1
        bm.faces.new((cb, axe_b[ni], axe_b[i])).material_index = 1
        bm.faces.new((axe_f[i], axe_b[i], axe_b[ni], axe_f[ni])).material_index = 4 if (i in (2, 3, 4)) else 1
    # Espigão traseiro (-Y)
    add_cylinder(bm, deform, 0.036, 0.006, 0.24, segments=6,
                 center=hx @ Vector((0.0, -0.15, 1.15)), rot=(halb_rot[0] - math.pi * 0.5, 0.0, 0.0),
                 mat_idx=4, weights=BONE_IDX["Hand.R"])

    mesh_obj = finalize_rigged_mesh("unit_knight", bm, mlist, col, arm_obj, split_angle_deg=52.0)
    build_unit_animations(arm_obj, "knight", spec)
    return arm_obj, mesh_obj


# ==============================================================================
# EXPORTAÇÃO GLB E SHOWCASE DE VERIFICAÇÃO VISUAL (FRENTE, COSTAS, POSES)
# ==============================================================================

def export_unit_glb(arm_obj, mesh_obj, filepath):
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.select_all(action="DESELECT")
    arm_obj.select_set(True)
    mesh_obj.select_set(True)
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_skins=True,
        export_animations=True,
        export_animation_mode="NLA_TRACKS",
        export_nla_strips=True,
        export_anim_slide_to_zero=True,
        export_optimize_animation_size=False,
    )
    print(f"[BlenderUnits] Exported rigged GLB: {filepath}")


def _set_eevee_engine(scene):
    for candidate in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            scene.render.engine = candidate
            return
        except TypeError:
            continue


def _tint_preview_team_materials(mats, primary=(0.06, 0.24, 0.78), cape=(0.04, 0.14, 0.48), accent=(0.10, 0.42, 0.96)):
    """
    Aplica tinta azul real nos materiais neutros apenas para os renders de preview do Blender
    (SEM alterar os GLBs já exportados!).
    """
    mapping = [
        (mats["team_primary"], primary),
        (mats["team_cape"], cape),
        (mats["team_accent"], accent),
    ]
    for mat, col in mapping:
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            continue
        tex_alb = next((n for n in nt.nodes if n.type == "TEX_IMAGE" and n.image and "Albedo" in n.image.name), None)
        if tex_alb is not None:
            mix = nt.nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            mix.inputs[7].default_value = (col[0], col[1], col[2], 1.0)
            nt.links.new(tex_alb.outputs["Color"], mix.inputs[6])
            nt.links.new(mix.outputs[2], bsdf.inputs["Base Color"])


def _evaluate_nla_pose(arm_obj, anim_name, frame):
    """Força o esqueleto a assumir um frame específico de uma NLA track para render."""
    if arm_obj.animation_data is None:
        return
    for tr in arm_obj.animation_data.nla_tracks:
        if tr.name == anim_name and len(tr.strips) > 0:
            act = tr.strips[0].action
            arm_obj.animation_data.action = act
            if getattr(act, "slots", None) and len(act.slots) > 0:
                arm_obj.animation_data.action_slot = act.slots[0]
            bpy.context.scene.frame_set(frame)
            return


def render_verification_sheets(units, mats):
    """
    Gera 3 renders de inspeção no Blender:
      1. units_lineup_front.png
      2. units_lineup_back.png
      3. units_poses_check.png (Walk, Attack, Death lado a lado)
    """
    _tint_preview_team_materials(mats)

    col = get_or_create_collection("UnitShowcase")
    bm = bmesh.new()
    deform = bm.verts.layers.deform.verify()
    add_beveled_box(bm, deform, 18.0, 14.0, 0.4, center=(0.0, 0.0, -0.2), bevel_amt=0.05, mat_idx=0)
    floor_mat = make_char_pbr_material("Mat_UnitFloor", (0.20, 0.25, 0.22), roughness=0.86)
    mesh = bpy.data.meshes.new("Floor_Mesh")
    bm.to_mesh(mesh)
    bm.free()
    floor_obj = bpy.data.objects.new("Showcase_Floor", mesh)
    floor_obj.data.materials.append(floor_mat)
    col.objects.link(floor_obj)

    world = bpy.data.worlds.new("UnitShowcaseWorld")
    bpy.context.scene.world = world
    world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs[0].default_value = (0.36, 0.48, 0.66, 1.0)
        bg.inputs[1].default_value = 1.05

    sun_data = bpy.data.lights.new("SunKey", type="SUN")
    sun_data.energy = 3.2
    sun_obj = bpy.data.objects.new("SunKey", sun_data)
    sun_obj.rotation_euler = Euler((math.radians(42), math.radians(15), math.radians(-30)), "XYZ")
    col.objects.link(sun_obj)

    fill_data = bpy.data.lights.new("FillLight", type="AREA")
    fill_data.energy = 140.0
    fill_data.size = 9.0
    fill_obj = bpy.data.objects.new("FillLight", fill_data)
    fill_obj.location = (0.0, 7.5, 4.5)
    fill_obj.rotation_euler = Euler((math.radians(-62), 0.0, math.radians(180)), "XYZ")
    col.objects.link(fill_obj)

    cam_data = bpy.data.cameras.new("PreviewCam")
    cam_data.lens = 42.0
    cam_obj = bpy.data.objects.new("PreviewCam", cam_data)
    col.objects.link(cam_obj)

    scene = bpy.context.scene
    scene.camera = cam_obj
    _set_eevee_engine(scene)
    scene.render.resolution_x = 1600
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100

    # Posiciona os 4 personagens em linha no Idle (frame 15)
    xs = [-2.55, -0.85, 0.85, 2.55]
    for (arm_obj, _mesh_obj), px in zip(units, xs):
        arm_obj.location = (px, 0.0, 0.0)
        _evaluate_nla_pose(arm_obj, "Idle", 15)

    # 1. Frente 3/4 (+Y é a frente!)
    cam_obj.location = (0.7, 7.6, 2.35)
    cam_obj.rotation_euler = (Vector((0.0, 0.0, 1.05)) - cam_obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(BLENDER_DIR, "units_lineup_front.png")
    bpy.ops.render.render(write_still=True)

    # 2. Costas 3/4 (-Y são as costas!)
    cam_obj.location = (-0.7, -7.6, 2.40)
    cam_obj.rotation_euler = (Vector((0.0, 0.0, 1.05)) - cam_obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(BLENDER_DIR, "units_lineup_back.png")
    bpy.ops.render.render(write_still=True)

    # 3. Verificação de Poses (Walk, Attack, Death)
    # Cria 2 cópias extras de cada boneco? Melhor: posiciona em 3 filas usando duplicate linked!
    pose_rows = [
        ("Walk", 1, -2.2),
        ("Attack", 13, 0.4),
        ("Death", 26, 3.0),
    ]
    row_clones = []
    # Reutiliza os originais na fila Walk e duplica para Attack e Death
    for idx, (arm_obj, mesh_obj) in enumerate(units):
        px = xs[idx] * 1.15
        arm_obj.location = (px, pose_rows[0][2], 0.0)
        _evaluate_nla_pose(arm_obj, pose_rows[0][0], pose_rows[0][1])

        for anim_name, fr, py in pose_rows[1:]:
            arm_c = arm_obj.copy()
            arm_c.data = arm_obj.data.copy()
            arm_c.animation_data_clear()
            mesh_c = mesh_obj.copy()
            mesh_c.data = mesh_obj.data
            mesh_c.parent = arm_c
            for m in mesh_c.modifiers:
                if m.type == "ARMATURE":
                    m.object = arm_c
            col.objects.link(arm_c)
            col.objects.link(mesh_c)
            arm_c.location = (px, py, 0.0)
            # Aplica pose exata do Strip
            for tr in arm_obj.animation_data.nla_tracks:
                if tr.name == anim_name:
                    act = tr.strips[0].action
                    arm_c.animation_data_create()
                    arm_c.animation_data.action = act
                    if getattr(act, "slots", None) and len(act.slots) > 0:
                        arm_c.animation_data.action_slot = act.slots[0]
                    break
            row_clones.append((arm_c, fr))

    # Força avaliação de cada ação no frame correspondente convertendo em pose
    bpy.context.view_layer.update()
    for arm_c, fr in row_clones:
        scene.frame_set(fr)
        bpy.context.view_layer.update()
        # Congela pose atual antes de mudar de frame para outro clone!
        saved = {pb.name: (pb.rotation_euler.copy(), pb.location.copy()) for pb in arm_c.pose.bones}
        arm_c.animation_data_clear()
        for bname, (rot_e, loc_v) in saved.items():
            pb = arm_c.pose.bones[bname]
            pb.rotation_mode = "XYZ"
            pb.rotation_euler = rot_e
            pb.location = loc_v

    # Também congela originais no frame 1 de Walk
    scene.frame_set(1)
    bpy.context.view_layer.update()

    cam_obj.location = (6.2, 8.2, 6.0)
    cam_obj.rotation_euler = (Vector((0.0, 0.4, 0.75)) - cam_obj.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(BLENDER_DIR, "units_poses_check.png")
    bpy.ops.render.render(write_still=True)

    blend_path = os.path.join(BLENDER_DIR, "units_showcase.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print("[BlenderUnits] Rendered verification sheets successfully.")


def main():
    clear_scene()
    mats = create_character_materials()
    col = get_or_create_collection("RTS_Units")

    builders = [
        ("unit_worker", build_unit_worker),
        ("unit_soldier", build_unit_soldier),
        ("unit_archer", build_unit_archer),
        ("unit_knight", build_unit_knight),
    ]

    units = []
    for unit_name, fn in builders:
        arm_obj, mesh_obj = fn(mats, col)
        glb_path = os.path.join(MODELS_DIR, f"{unit_name}.glb")
        export_unit_glb(arm_obj, mesh_obj, glb_path)
        units.append((arm_obj, mesh_obj))

    render_verification_sheets(units, mats)
    print("[BlenderUnits] ALL 4 RIGGED & ANIMATED UNITS GENERATED SUCCESSFULLY.")


if __name__ == "__main__":
    main()
