"""
Gerador procedural de assets 3D de alta fidelidade (PBR + Texturas Empacotadas + Geometria Suavizada)
para o RTS 'Coroa de Ferro: Crônicas da Fronteira'.
Executado em Blender 5.2+ em modo headless (-b -P).
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
# GERADOR DE TEXTURAS PBR PROCEDURAIS (ALBEDO + NORMAL + ROUGHNESS) VIA NUMPY
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
    # Smoothstep
    yf = yf * yf * (3.0 - 2.0 * yf)
    xf = xf * xf * (3.0 - 2.0 * xf)
    v00 = grid[yi[:, None], xi[None, :]]
    v10 = grid[yi[:, None], xi1[None, :]]
    v01 = grid[yi1[:, None], xi[None, :]]
    v11 = grid[yi1[:, None], xi1[None, :]]
    top = v00 * (1.0 - xf) + v10 * xf
    bot = v01 * (1.0 - xf) + v11 * xf
    return top * (1.0 - yf) + bot * yf


def _fbm_2d(size, octaves=(4, 8, 16, 32), seed=1):
    acc = np.zeros((size, size), dtype=np.float32)
    amp = 1.0
    total = 0.0
    for idx, sc in enumerate(octaves):
        acc += _value_noise_2d(size, size, sc, seed=seed + idx * 17) * amp
        total += amp
        amp *= 0.5
    return acc / total


def _height_to_normal_rgba(height, strength=3.2):
    dx = np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)
    dy = np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(height)
    inv_len = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-8)
    nx = nx * inv_len * 0.5 + 0.5
    ny = ny * inv_len * 0.5 + 0.5
    nz = nz * inv_len * 0.5 + 0.5
    rgba = np.stack([nx, ny, nz, np.ones_like(height)], axis=-1)
    return rgba


def _array_to_packed_image(name, rgba_float, non_color=False):
    h, w, _ = rgba_float.shape
    img = bpy.data.images.new(name=name, width=w, height=h, alpha=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    buf = np.ascontiguousarray(np.clip(rgba_float, 0.0, 1.0), dtype=np.float32).ravel()
    img.pixels.foreach_set(buf)
    img.pack()
    return img


def generate_pbr_texture_set(prefix, kind, base_rgb, sec_rgb, size=256, seed=10):
    fbm = _fbm_2d(size, octaves=(4, 8, 16, 32, 64), seed=seed)
    yy, xx = np.mgrid[0:size, 0:size]
    u = xx / float(size)
    v = yy / float(size)

    if kind == "stone":
        rows = 6.0
        cols = 4.0
        row_idx = np.floor(v * rows)
        u_shift = np.mod(u * cols + (np.mod(row_idx, 2.0) * 0.5), 1.0)
        v_cell = np.mod(v * rows, 1.0)
        # Mortar gaps
        mx = np.minimum(u_shift, 1.0 - u_shift)
        my = np.minimum(v_cell, 1.0 - v_cell)
        edge = np.minimum(mx * 1.4, my)
        mortar = np.clip((edge - 0.04) / 0.08, 0.0, 1.0)
        block_id = np.mod(np.floor(u * cols + np.mod(row_idx, 2.0) * 0.5) * 13.7 + row_idx * 7.3, 1.0)
        height = mortar * (0.45 + 0.35 * fbm + 0.2 * block_id)
        mix_t = np.clip(0.15 + 0.55 * fbm + 0.2 * block_id, 0.0, 1.0) * mortar
        rough = np.clip(0.95 - mortar * 0.16 + (fbm - 0.5) * 0.12, 0.55, 0.98)
    elif kind == "tiles":
        rows = 8.0
        cols = 6.0
        row_idx = np.floor(v * rows)
        u_shift = np.mod(u * cols + np.mod(row_idx, 2.0) * 0.5, 1.0)
        v_cell = np.mod(v * rows, 1.0)
        tile_curve = np.sin(u_shift * math.pi) * 0.55 + (1.0 - v_cell) * 0.45
        seam = np.clip(np.minimum(u_shift, 1.0 - u_shift) * 14.0, 0.0, 1.0) * np.clip(v_cell * 10.0, 0.0, 1.0)
        height = np.clip(tile_curve * seam + fbm * 0.2, 0.0, 1.0)
        mix_t = np.clip(0.2 + 0.5 * fbm + 0.3 * (1.0 - seam), 0.0, 1.0)
        rough = np.clip(0.76 - 0.15 * seam + 0.14 * fbm, 0.45, 0.92)
    elif kind == "wood":
        planks = 5.0
        p_cell = np.mod(u * planks, 1.0)
        p_id = np.floor(u * planks) / planks
        grain = 0.5 + 0.5 * np.sin((v * 18.0 + fbm * 9.0 + p_id * 11.0) * math.pi)
        seam = np.clip(np.minimum(p_cell, 1.0 - p_cell) * 16.0, 0.0, 1.0)
        height = seam * (0.4 + 0.35 * grain + 0.25 * fbm)
        mix_t = np.clip(0.25 + 0.45 * grain + 0.3 * fbm, 0.0, 1.0) * seam
        rough = np.clip(0.82 - 0.12 * grain + 0.1 * (1.0 - seam), 0.5, 0.95)
    elif kind == "metal":
        scratches = _fbm_2d(size, octaves=(8, 24, 48), seed=seed + 3)
        hammer = 0.5 + 0.5 * np.sin(fbm * 16.0)
        height = 0.5 * hammer + 0.5 * scratches
        mix_t = np.clip(0.35 * fbm + 0.5 * scratches, 0.0, 1.0)
        rough = np.clip(0.22 + 0.24 * scratches, 0.14, 0.52)
    else:  # foliage / rock
        height = fbm
        mix_t = np.clip(fbm * 1.15 - 0.05, 0.0, 1.0)
        rough = np.clip(0.72 + 0.2 * fbm, 0.55, 0.95)

    c0 = np.array(base_rgb, dtype=np.float32)[None, None, :]
    c1 = np.array(sec_rgb, dtype=np.float32)[None, None, :]
    rgb = c0 * (1.0 - mix_t[..., None]) + c1 * mix_t[..., None]
    albedo_rgba = np.concatenate([rgb, np.ones((size, size, 1), dtype=np.float32)], axis=-1)
    normal_rgba = _height_to_normal_rgba(height, strength=3.0 if kind != "metal" else 1.4)
    rough_rgba = np.stack([rough, rough, rough, np.ones_like(rough)], axis=-1)

    return {
        "albedo": _array_to_packed_image(f"{prefix}_Albedo", albedo_rgba, non_color=False),
        "normal": _array_to_packed_image(f"{prefix}_Normal", normal_rgba, non_color=True),
        "roughness": _array_to_packed_image(f"{prefix}_Roughness", rough_rgba, non_color=True),
    }


def make_pbr_material(name, color, roughness=0.72, metallic=0.0, tex_set=None,
                      uv_scale=1.0, emission_color=None, emission_strength=0.0):
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
        nrm_node.inputs["Strength"].default_value = 0.85
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


def create_materials():
    tex_stone = generate_pbr_texture_set("StoneLight", "stone", (0.58, 0.57, 0.54), (0.38, 0.37, 0.35), seed=11)
    tex_stone_dark = generate_pbr_texture_set("StoneDark", "stone", (0.36, 0.37, 0.40), (0.22, 0.23, 0.25), seed=22)
    tex_plaster = generate_pbr_texture_set("Plaster", "foliage", (0.88, 0.83, 0.72), (0.76, 0.70, 0.58), seed=33)
    tex_wood = generate_pbr_texture_set("OakWood", "wood", (0.48, 0.29, 0.14), (0.28, 0.16, 0.08), seed=44)
    tex_wood_dark = generate_pbr_texture_set("DarkOak", "wood", (0.26, 0.15, 0.08), (0.14, 0.08, 0.04), seed=55)
    tex_slate = generate_pbr_texture_set("SlateTiles", "tiles", (0.20, 0.27, 0.39), (0.12, 0.16, 0.24), seed=66)
    tex_terra = generate_pbr_texture_set("TerraTiles", "tiles", (0.66, 0.28, 0.17), (0.45, 0.17, 0.10), seed=77)
    tex_steel = generate_pbr_texture_set("ForgedSteel", "metal", (0.76, 0.80, 0.85), (0.52, 0.56, 0.62), seed=88)
    tex_iron = generate_pbr_texture_set("DarkIron", "metal", (0.42, 0.45, 0.50), (0.26, 0.28, 0.32), seed=99)
    tex_leaf1 = generate_pbr_texture_set("LeafCanopy1", "foliage", (0.13, 0.39, 0.14), (0.07, 0.24, 0.08), seed=101)
    tex_leaf2 = generate_pbr_texture_set("LeafCanopy2", "foliage", (0.18, 0.48, 0.17), (0.11, 0.32, 0.10), seed=102)
    tex_leaf3 = generate_pbr_texture_set("LeafCanopy3", "foliage", (0.25, 0.56, 0.20), (0.15, 0.39, 0.13), seed=103)
    tex_rock = generate_pbr_texture_set("CliffRock", "foliage", (0.39, 0.38, 0.37), (0.24, 0.23, 0.22), seed=104)

    return {
        "skin": make_pbr_material("Mat_Skin", (0.87, 0.67, 0.53), roughness=0.65),
        "tunic_cloth": make_pbr_material("Mat_TunicCloth", (0.78, 0.72, 0.60), roughness=0.85),
        "leather": make_pbr_material("Mat_Leather", (0.36, 0.21, 0.11), roughness=0.58),
        "dark_leather": make_pbr_material("Mat_DarkLeather", (0.18, 0.11, 0.07), roughness=0.62),
        "wood": make_pbr_material("Mat_Wood", (0.46, 0.28, 0.14), tex_set=tex_wood, uv_scale=0.55),
        "wood_dark": make_pbr_material("Mat_WoodDark", (0.25, 0.15, 0.08), tex_set=tex_wood_dark, uv_scale=0.55),
        "stone": make_pbr_material("Mat_Stone", (0.54, 0.53, 0.51), tex_set=tex_stone, uv_scale=0.35),
        "stone_dark": make_pbr_material("Mat_StoneDark", (0.32, 0.33, 0.36), tex_set=tex_stone_dark, uv_scale=0.38),
        "rock": make_pbr_material("Mat_Rock", (0.36, 0.35, 0.34), tex_set=tex_rock, uv_scale=0.45),
        "plaster": make_pbr_material("Mat_Plaster", (0.86, 0.81, 0.70), tex_set=tex_plaster, uv_scale=0.45),
        "roof_slate": make_pbr_material("Mat_RoofSlate", (0.19, 0.26, 0.38), tex_set=tex_slate, uv_scale=0.50),
        "roof_terracotta": make_pbr_material("Mat_RoofTerracotta", (0.64, 0.26, 0.17), tex_set=tex_terra, uv_scale=0.50),
        "iron": make_pbr_material("Mat_Iron", (0.40, 0.43, 0.48), metallic=0.88, tex_set=tex_iron, uv_scale=0.6),
        "steel": make_pbr_material("Mat_Steel", (0.74, 0.78, 0.84), metallic=0.94, tex_set=tex_steel, uv_scale=0.7),
        "gold": make_pbr_material("Mat_Gold", (0.98, 0.77, 0.16), roughness=0.16, metallic=0.96,
                                emission_color=(0.98, 0.74, 0.14), emission_strength=0.45),
        "gold_trim": make_pbr_material("Mat_GoldTrim", (0.90, 0.70, 0.22), roughness=0.24, metallic=0.92),
        "archer_green": make_pbr_material("Mat_ArcherGreen", (0.16, 0.40, 0.21), roughness=0.78),
        "foliage_1": make_pbr_material("Mat_Foliage1", (0.12, 0.37, 0.13), tex_set=tex_leaf1, uv_scale=0.6),
        "foliage_2": make_pbr_material("Mat_Foliage2", (0.17, 0.46, 0.16), tex_set=tex_leaf2, uv_scale=0.6),
        "foliage_3": make_pbr_material("Mat_Foliage3", (0.24, 0.55, 0.20), tex_set=tex_leaf3, uv_scale=0.6),
        "banner_neutral": make_pbr_material("Mat_BannerNeutral", (0.88, 0.78, 0.52), roughness=0.68),
        "straw": make_pbr_material("Mat_Straw", (0.80, 0.67, 0.32), roughness=0.90),
        "feather": make_pbr_material("Mat_Feather", (0.90, 0.26, 0.20), roughness=0.65),
        "window_glow": make_pbr_material("Mat_WindowGlow", (1.0, 0.72, 0.26), roughness=0.25,
                                       emission_color=(1.0, 0.68, 0.20), emission_strength=2.8),
        "ember_glow": make_pbr_material("Mat_EmberGlow", (1.0, 0.42, 0.08), roughness=0.40,
                                      emission_color=(1.0, 0.36, 0.05), emission_strength=3.6),
    }


# ==============================================================================
# HELPERS DE GEOMETRIA SUAVE E CHANFRADA (BMESH)
# ==============================================================================

def _apply_xform_and_mat(bm, verts, mat_xform, mat_idx):
    bmesh.ops.transform(bm, matrix=mat_xform, verts=verts)
    for v in verts:
        for f in v.link_faces:
            f.material_index = mat_idx


def add_beveled_box(bm, sx, sy, sz, center=(0, 0, 0), rot=(0, 0, 0), bevel_amt=0.04, bevel_segs=2, mat_idx=0):
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    bmesh.ops.transform(bm, matrix=Matrix.Diagonal((sx, sy, sz, 1.0)), verts=verts)
    if bevel_amt > 0.0:
        edges = list({e for v in verts for e in v.link_edges})
        b_ret = bmesh.ops.bevel(
            bm, geom=edges, offset=min(bevel_amt, min(sx, sy, sz) * 0.22),
            segments=bevel_segs, profile=0.5, affect="EDGES"
        )
        verts = list({v for v in verts if v.is_valid} | {v for v in b_ret.get("verts", []) if v.is_valid})
    mat_rot = Euler(rot, "XYZ").to_matrix().to_4x4()
    mat_trans = Matrix.Translation(center)
    bmesh.ops.transform(bm, matrix=mat_trans @ mat_rot, verts=verts)
    for v in verts:
        for f in v.link_faces:
            f.material_index = mat_idx
    return verts


def add_cylinder(bm, r1, r2, depth, segments=20, center=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1), mat_idx=0, cap_ends=True):
    ret = bmesh.ops.create_cone(
        bm, cap_ends=cap_ends, cap_tris=False, segments=segments,
        radius1=r1, radius2=r2, depth=depth
    )
    verts = ret["verts"]
    mat_scale = Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    mat_rot = Euler(rot, "XYZ").to_matrix().to_4x4()
    mat_trans = Matrix.Translation(center)
    _apply_xform_and_mat(bm, verts, mat_trans @ mat_rot @ mat_scale, mat_idx)
    return verts


def add_sphere(bm, radius, subdivisions=2, center=(0, 0, 0), scale=(1, 1, 1), rot=(0, 0, 0), mat_idx=0, noise_amp=0.0, seed=0):
    ret = bmesh.ops.create_icosphere(bm, subdivisions=subdivisions, radius=radius)
    verts = ret["verts"]
    if noise_amp > 0.0:
        for v in verts:
            n = math.sin(v.co.x * 3.1 + seed) * math.cos(v.co.y * 2.7 - seed) * math.sin(v.co.z * 3.5 + seed * 0.5)
            v.co *= (1.0 + n * noise_amp)
    mat_scale = Matrix.Diagonal((scale[0], scale[1], scale[2], 1.0))
    mat_rot = Euler(rot, "XYZ").to_matrix().to_4x4()
    mat_trans = Matrix.Translation(center)
    _apply_xform_and_mat(bm, verts, mat_trans @ mat_rot @ mat_scale, mat_idx)
    return verts


def add_pitched_roof(bm, width, length, height, center=(0, 0, 0), overhang=0.25, mat_idx=0, ridge_mat_idx=None):
    hw = width * 0.5 + overhang
    hl = length * 0.5 + overhang
    cx, cy, cz = center
    v0 = bm.verts.new((cx - hw, cy - hl, cz))
    v1 = bm.verts.new((cx + hw, cy - hl, cz))
    v2 = bm.verts.new((cx + hw, cy + hl, cz))
    v3 = bm.verts.new((cx - hw, cy + hl, cz))
    v4 = bm.verts.new((cx, cy - hl, cz + height))
    v5 = bm.verts.new((cx, cy + hl, cz + height))
    faces = [
        (v0, v1, v4),
        (v2, v3, v5),
        (v1, v2, v5, v4),
        (v3, v0, v4, v5),
        (v3, v2, v1, v0),
    ]
    for fv in faces:
        f = bm.faces.new(fv)
        f.material_index = mat_idx
    if ridge_mat_idx is not None:
        add_beveled_box(bm, 0.24, length + overhang * 2.1, 0.22, center=(cx, cy, cz + height), bevel_amt=0.04, mat_idx=ridge_mat_idx)


def assign_box_uvs(bm):
    uv_layer = bm.loops.layers.uv.verify()
    for face in bm.faces:
        n = face.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in face.loops:
            co = loop.vert.co
            if az >= ax and az >= ay:
                loop[uv_layer].uv = (co.x, co.y)
            elif ax >= ay and ax >= az:
                loop[uv_layer].uv = (co.y, co.z)
            else:
                loop[uv_layer].uv = (co.x, co.z)


def finalize_mesh(name, bm, mat_list, collection, split_angle_deg=44.0):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    assign_box_uvs(bm)

    # Split sharp architectural edges while keeping curved cylinders & organic shapes smooth!
    if split_angle_deg < 179.0:
        rad_thresh = math.radians(split_angle_deg)
        sharp_edges = []
        for e in bm.edges:
            if len(e.link_faces) == 2:
                ang = e.link_faces[0].normal.angle(e.link_faces[1].normal, 0.0)
                if ang > rad_thresh:
                    sharp_edges.append(e)
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

    min_z = min(v.co.z for v in obj.data.vertices)
    if abs(min_z) > 1e-5:
        for v in obj.data.vertices:
            v.co.z -= min_z
        obj.data.update()
    return obj


# ==============================================================================
# BUILDERS DE ALTA FIDELIDADE (UNIDADES, PRÉDIOS, RECURSOS)
# ==============================================================================

def build_unit_worker(mats, col):
    bm = bmesh.new()
    mlist = [mats["skin"], mats["tunic_cloth"], mats["leather"], mats["wood"], mats["steel"], mats["gold_trim"]]
    # Boots & rounded legs
    for sx in (-0.13, 0.13):
        add_cylinder(bm, 0.10, 0.08, 0.22, segments=14, center=(sx, 0.02, 0.11), mat_idx=2)
        add_cylinder(bm, 0.085, 0.095, 0.34, segments=14, center=(sx, 0.0, 0.34), mat_idx=1)
    # Sculpted Tunic Torso + Vest
    add_cylinder(bm, 0.26, 0.22, 0.58, segments=18, center=(0.0, 0.0, 0.74), mat_idx=1)
    add_cylinder(bm, 0.25, 0.24, 0.12, segments=18, center=(0.0, 0.0, 0.56), mat_idx=2)
    add_beveled_box(bm, 0.10, 0.10, 0.08, center=(0.0, 0.25, 0.56), bevel_amt=0.02, mat_idx=5)
    # Satchel
    add_beveled_box(bm, 0.12, 0.22, 0.22, center=(-0.27, -0.04, 0.50), bevel_amt=0.03, mat_idx=2)
    # Rounded Arms & Hands
    add_cylinder(bm, 0.075, 0.065, 0.42, segments=12, center=(-0.30, 0.04, 0.76), rot=(0.22, 0.15, 0), mat_idx=1)
    add_cylinder(bm, 0.075, 0.065, 0.42, segments=12, center=(0.30, 0.08, 0.76), rot=(-0.5, -0.15, 0), mat_idx=1)
    add_sphere(bm, 0.07, subdivisions=2, center=(-0.33, 0.12, 0.54), mat_idx=0)
    add_sphere(bm, 0.07, subdivisions=2, center=(0.33, 0.24, 0.60), mat_idx=0)
    # Sculpted Head & Hood/Hat
    add_sphere(bm, 0.18, subdivisions=2, center=(0.0, 0.0, 1.18), scale=(0.95, 1.0, 1.08), mat_idx=0)
    add_cylinder(bm, 0.34, 0.26, 0.06, segments=18, center=(0.0, -0.02, 1.32), rot=(-0.08, 0, 0), mat_idx=2)
    add_cylinder(bm, 0.21, 0.14, 0.22, segments=18, center=(0.0, -0.02, 1.44), rot=(-0.08, 0, 0), mat_idx=2)
    # Pickaxe with beveled steel blade
    add_cylinder(bm, 0.03, 0.03, 0.90, segments=10, center=(0.35, 0.35, 0.80), rot=(0.55, 0, 0), mat_idx=3)
    add_beveled_box(bm, 0.08, 0.46, 0.09, center=(0.35, 0.58, 1.15), rot=(0.55, 0, 0), bevel_amt=0.02, mat_idx=4)
    return finalize_mesh("unit_worker", bm, mlist, col, split_angle_deg=55.0)


def build_unit_soldier(mats, col):
    bm = bmesh.new()
    mlist = [mats["skin"], mats["iron"], mats["steel"], mats["leather"], mats["gold_trim"]]
    for sx in (-0.14, 0.14):
        add_cylinder(bm, 0.105, 0.095, 0.48, segments=14, center=(sx, 0.0, 0.24), mat_idx=1)
    # Rounded armored breastplate & belt
    add_cylinder(bm, 0.26, 0.29, 0.58, segments=18, center=(0.0, 0.0, 0.76), scale=(1.05, 0.78, 1.0), mat_idx=2)
    add_cylinder(bm, 0.27, 0.27, 0.10, segments=18, center=(0.0, 0.0, 0.54), scale=(1.05, 0.78, 1.0), mat_idx=3)
    # Curved shoulder pauldrons
    add_sphere(bm, 0.16, subdivisions=2, center=(-0.33, 0.0, 0.98), scale=(1.0, 0.95, 0.75), mat_idx=2)
    add_sphere(bm, 0.16, subdivisions=2, center=(0.33, 0.0, 0.98), scale=(1.0, 0.95, 0.75), mat_idx=2)
    # Arms
    add_cylinder(bm, 0.08, 0.07, 0.42, segments=12, center=(-0.34, 0.08, 0.76), rot=(-0.4, 0, 0), mat_idx=1)
    add_cylinder(bm, 0.08, 0.07, 0.42, segments=12, center=(0.34, 0.10, 0.76), rot=(-0.55, 0, 0), mat_idx=1)
    # Helmeted Head
    add_sphere(bm, 0.17, subdivisions=2, center=(0.0, 0.0, 1.22), mat_idx=0)
    add_cylinder(bm, 0.22, 0.17, 0.24, segments=18, center=(0.0, 0.0, 1.36), mat_idx=2)
    add_sphere(bm, 0.17, subdivisions=2, center=(0.0, 0.0, 1.46), scale=(1.0, 1.0, 0.65), mat_idx=2)
    add_beveled_box(bm, 0.06, 0.26, 0.11, center=(0.0, 0.0, 1.56), bevel_amt=0.02, mat_idx=4)
    # Curved Heater Shield
    add_cylinder(bm, 0.28, 0.24, 0.08, segments=16, center=(-0.44, 0.20, 0.78), rot=(0, math.pi * 0.5, 0.15), scale=(1.15, 0.88, 1.0), mat_idx=1)
    add_sphere(bm, 0.10, subdivisions=2, center=(-0.49, 0.20, 0.78), scale=(0.45, 1.0, 1.0), mat_idx=4)
    # Broadsword
    add_cylinder(bm, 0.03, 0.03, 0.22, segments=10, center=(0.37, 0.24, 0.62), rot=(0.7, 0, 0), mat_idx=3)
    add_beveled_box(bm, 0.22, 0.06, 0.05, center=(0.37, 0.30, 0.68), rot=(0.7, 0, 0), bevel_amt=0.015, mat_idx=4)
    add_beveled_box(bm, 0.06, 0.03, 0.74, center=(0.37, 0.52, 0.96), rot=(0.7, 0, 0), bevel_amt=0.01, mat_idx=2)
    return finalize_mesh("unit_soldier", bm, mlist, col, split_angle_deg=55.0)


def build_unit_archer(mats, col):
    bm = bmesh.new()
    mlist = [mats["skin"], mats["archer_green"], mats["leather"], mats["wood"], mats["feather"], mats["steel"]]
    for sx in (-0.12, 0.12):
        add_cylinder(bm, 0.09, 0.08, 0.44, segments=14, center=(sx, 0.0, 0.22), mat_idx=2)
    # Slim Ranger Tunic & Flowing Cloak
    add_cylinder(bm, 0.23, 0.24, 0.58, segments=18, center=(0.0, 0.0, 0.72), scale=(1.0, 0.75, 1.0), mat_idx=1)
    add_cylinder(bm, 0.28, 0.18, 0.76, segments=14, center=(0.0, -0.18, 0.64), rot=(0.18, 0, 0), scale=(1.05, 0.32, 1.0), mat_idx=1)
    # Quiver with feathered arrows
    add_cylinder(bm, 0.08, 0.06, 0.48, segments=12, center=(-0.12, -0.24, 0.88), rot=(0.25, 0.32, 0), mat_idx=2)
    for ox in (-0.16, -0.20):
        add_cylinder(bm, 0.025, 0.025, 0.18, segments=8, center=(ox, -0.28, 1.15), rot=(0.25, 0.32, 0), mat_idx=4)
    # Arms
    add_cylinder(bm, 0.07, 0.06, 0.42, segments=12, center=(-0.29, 0.14, 0.78), rot=(-0.85, 0, 0), mat_idx=1)
    add_cylinder(bm, 0.07, 0.06, 0.42, segments=12, center=(0.29, 0.08, 0.76), rot=(-0.45, 0, 0), mat_idx=1)
    # Head & Hood
    add_sphere(bm, 0.16, subdivisions=2, center=(0.0, 0.0, 1.16), mat_idx=0)
    add_cylinder(bm, 0.23, 0.05, 0.34, segments=16, center=(0.0, -0.02, 1.32), rot=(-0.22, 0, 0), mat_idx=1)
    # Curved Longbow
    add_cylinder(bm, 0.028, 0.025, 0.44, segments=10, center=(-0.31, 0.38, 0.82), mat_idx=3)
    add_cylinder(bm, 0.025, 0.018, 0.42, segments=10, center=(-0.31, 0.30, 1.18), rot=(-0.45, 0, 0), mat_idx=3)
    add_cylinder(bm, 0.025, 0.018, 0.42, segments=10, center=(-0.31, 0.30, 0.46), rot=(0.45, 0, 0), mat_idx=3)
    return finalize_mesh("unit_archer", bm, mlist, col, split_angle_deg=55.0)


def build_unit_knight(mats, col):
    bm = bmesh.new()
    mlist = [mats["steel"], mats["gold_trim"], mats["banner_neutral"], mats["leather"], mats["iron"]]
    for sx in (-0.16, 0.16):
        add_cylinder(bm, 0.12, 0.105, 0.52, segments=16, center=(sx, 0.0, 0.26), mat_idx=0)
    # Heavy Plate Cuirass & Tassets
    add_cylinder(bm, 0.29, 0.33, 0.66, segments=20, center=(0.0, 0.0, 0.84), scale=(1.08, 0.82, 1.0), mat_idx=0)
    add_cylinder(bm, 0.31, 0.27, 0.22, segments=20, center=(0.0, 0.0, 0.54), scale=(1.08, 0.82, 1.0), mat_idx=1)
    # Flowing Royal Cape
    add_cylinder(bm, 0.36, 0.22, 0.96, segments=14, center=(0.0, -0.25, 0.68), rot=(0.20, 0, 0), scale=(1.1, 0.26, 1.0), mat_idx=2)
    # Winged Pauldrons
    add_sphere(bm, 0.20, subdivisions=2, center=(-0.41, 0.0, 1.08), scale=(1.05, 0.95, 0.8), mat_idx=1)
    add_sphere(bm, 0.20, subdivisions=2, center=(0.41, 0.0, 1.08), scale=(1.05, 0.95, 0.8), mat_idx=1)
    # Arms
    add_cylinder(bm, 0.09, 0.08, 0.46, segments=12, center=(-0.40, 0.08, 0.82), rot=(-0.3, 0, 0), mat_idx=0)
    add_cylinder(bm, 0.09, 0.08, 0.46, segments=12, center=(0.40, 0.12, 0.84), rot=(-0.5, 0, 0), mat_idx=0)
    # Crowned Great Helm & Crest
    add_cylinder(bm, 0.22, 0.20, 0.34, segments=18, center=(0.0, 0.0, 1.36), mat_idx=0)
    add_sphere(bm, 0.20, subdivisions=2, center=(0.0, 0.0, 1.52), scale=(1.0, 1.0, 0.55), mat_idx=0)
    add_cylinder(bm, 0.22, 0.24, 0.10, segments=18, center=(0.0, 0.0, 1.60), mat_idx=1)
    add_beveled_box(bm, 0.08, 0.34, 0.16, center=(0.0, -0.02, 1.72), bevel_amt=0.03, mat_idx=2)
    # Heavy Kite Shield
    add_cylinder(bm, 0.34, 0.26, 0.09, segments=18, center=(-0.52, 0.20, 0.84), rot=(0, math.pi * 0.5, 0.12), scale=(1.3, 0.88, 1.0), mat_idx=0)
    add_sphere(bm, 0.13, subdivisions=2, center=(-0.57, 0.20, 0.84), scale=(0.45, 1.0, 1.0), mat_idx=1)
    # Ornate Great Halberd
    add_cylinder(bm, 0.035, 0.035, 1.70, segments=12, center=(0.45, 0.24, 1.05), rot=(0.24, 0, 0), mat_idx=4)
    add_beveled_box(bm, 0.05, 0.28, 0.46, center=(0.45, 0.44, 1.74), rot=(0.24, 0, 0), bevel_amt=0.015, mat_idx=1)
    return finalize_mesh("unit_knight", bm, mlist, col, split_angle_deg=55.0)


def build_building_town_center(mats, col):
    bm = bmesh.new()
    mlist = [
        mats["stone"], mats["stone_dark"], mats["wood"], mats["plaster"],
        mats["roof_slate"], mats["gold_trim"], mats["banner_neutral"],
        mats["window_glow"], mats["ember_glow"], mats["iron"]
    ]
    # Stepped beveled stone courtyard plinth
    add_beveled_box(bm, 7.2, 7.2, 0.40, center=(0, 0, 0.20), bevel_amt=0.08, mat_idx=1)
    add_beveled_box(bm, 6.4, 6.4, 0.35, center=(0, 0, 0.55), bevel_amt=0.07, mat_idx=0)
    # Grand front staircase (+Y)
    for st in range(4):
        add_beveled_box(bm, 2.3 - st * 0.12, 0.45, 0.18, center=(0, 3.6 - st * 0.35, 0.09 + st * 0.18), bevel_amt=0.03, mat_idx=1)
    # Main Keep Walls with Stone Buttresses
    add_beveled_box(bm, 4.7, 4.7, 2.75, center=(0, 0, 2.10), bevel_amt=0.06, mat_idx=0)
    for pos in [(-1.3, 2.38), (1.3, 2.38), (-1.3, -2.38), (1.3, -2.38), (2.38, -1.2), (2.38, 1.2), (-2.38, -1.2), (-2.38, 1.2)]:
        add_beveled_box(bm, 0.48, 0.48, 2.75, center=(pos[0], pos[1], 2.05), bevel_amt=0.05, mat_idx=1)
    # Gothic Entrance Portal + Iron Portcullis
    add_beveled_box(bm, 1.85, 0.55, 2.20, center=(0, 2.38, 1.80), bevel_amt=0.06, mat_idx=1)
    add_cylinder(bm, 0.72, 0.72, 0.58, segments=18, center=(0, 2.38, 2.25), rot=(math.pi * 0.5, 0, 0), mat_idx=2)
    add_beveled_box(bm, 1.25, 0.60, 1.55, center=(0, 2.38, 1.48), bevel_amt=0.03, mat_idx=2)
    for gx in (-0.42, -0.14, 0.14, 0.42):
        add_cylinder(bm, 0.03, 0.03, 1.45, segments=8, center=(gx, 2.66, 1.48), mat_idx=9)
    # Flanking Entrance Braziers with Glowing Embers
    for sx in (-1.55, 1.55):
        add_cylinder(bm, 0.24, 0.32, 0.75, segments=12, center=(sx, 3.25, 1.05), mat_idx=1)
        add_sphere(bm, 0.24, subdivisions=2, center=(sx, 3.25, 1.48), scale=(1.0, 1.0, 0.7), mat_idx=8)
    # 4 Round 24-segment Corner Watch Towers with Stone Rings & Conical Roofs
    for sx in (-2.45, 2.45):
        for sy in (-2.45, 2.45):
            add_cylinder(bm, 0.86, 0.80, 4.4, segments=24, center=(sx, sy, 2.85), mat_idx=0)
            add_cylinder(bm, 0.94, 0.94, 0.22, segments=24, center=(sx, sy, 1.85), mat_idx=1)
            add_cylinder(bm, 0.96, 0.96, 0.35, segments=24, center=(sx, sy, 4.90), mat_idx=1)
            add_cylinder(bm, 1.12, 0.04, 1.55, segments=24, center=(sx, sy, 5.82), mat_idx=4)
            add_sphere(bm, 0.10, subdivisions=1, center=(sx, sy, 6.62), mat_idx=5)
            # Glowing tower window
            add_beveled_box(bm, 0.24, 0.24, 0.55, center=(sx * 1.18, sy * 1.18, 3.5), bevel_amt=0.03, mat_idx=7)
    # Upper Timber & Plaster Royal Hall
    add_beveled_box(bm, 3.65, 3.65, 1.75, center=(0, 0, 4.25), bevel_amt=0.05, mat_idx=3)
    for tx in (-1.84, -0.6, 0.6, 1.84):
        add_beveled_box(bm, 0.18, 3.75, 1.78, center=(tx, 0, 4.25), bevel_amt=0.02, mat_idx=2)
    # Illuminated Royal Hall Windows
    for wx in (-0.95, 0.95):
        add_beveled_box(bm, 0.45, 3.82, 0.72, center=(wx, 0, 4.30), bevel_amt=0.03, mat_idx=7)
    for wy in (-0.95, 0.95):
        add_beveled_box(bm, 3.82, 0.45, 0.72, center=(0, wy, 4.30), bevel_amt=0.03, mat_idx=7)
    # Grand Slate Pitched Roof + Gold Spire + Flag
    add_pitched_roof(bm, 3.9, 3.9, 2.0, center=(0, 0, 5.10), overhang=0.35, mat_idx=4, ridge_mat_idx=5)
    add_cylinder(bm, 0.08, 0.05, 1.75, segments=12, center=(0, 0, 7.35), mat_idx=5)
    add_beveled_box(bm, 0.08, 1.25, 0.68, center=(0, 0.65, 7.75), bevel_amt=0.02, mat_idx=6)
    return finalize_mesh("building_town_center", bm, mlist, col, split_angle_deg=44.0)


def build_building_barracks(mats, col):
    bm = bmesh.new()
    mlist = [mats["stone_dark"], mats["stone"], mats["wood"], mats["wood_dark"], mats["roof_terracotta"], mats["steel"], mats["window_glow"], mats["ember_glow"]]
    # Cobble Foundation
    add_beveled_box(bm, 5.6, 5.2, 0.42, center=(0, 0, 0.21), bevel_amt=0.08, mat_idx=0)
    # Main Barracks Stone Lower Floor
    add_beveled_box(bm, 4.6, 3.2, 1.65, center=(0, -0.5, 1.25), bevel_amt=0.05, mat_idx=1)
    # Upper Timber Framing + Plaster
    add_beveled_box(bm, 4.8, 3.4, 1.15, center=(0, -0.5, 2.60), bevel_amt=0.04, mat_idx=1)
    for sx in (-2.38, -0.8, 0.8, 2.38):
        add_beveled_box(bm, 0.22, 3.55, 2.35, center=(sx, -0.5, 2.0), bevel_amt=0.03, mat_idx=3)
    # Glowing Barracks Windows
    for wx in (-1.55, 1.55):
        add_beveled_box(bm, 0.46, 3.58, 0.56, center=(wx, -0.5, 2.62), bevel_amt=0.02, mat_idx=6)
    # Detailed Terracotta Roof with Ridge
    add_pitched_roof(bm, 4.8, 3.4, 1.75, center=(0, -0.5, 3.16), overhang=0.35, mat_idx=4, ridge_mat_idx=0)
    # Stone Chimney & Side Forge Hearth
    add_beveled_box(bm, 0.72, 0.72, 2.55, center=(-1.7, -1.6, 3.85), bevel_amt=0.06, mat_idx=0)
    add_cylinder(bm, 0.48, 0.42, 0.65, segments=14, center=(-1.95, 1.35, 0.75), mat_idx=0)
    add_sphere(bm, 0.34, subdivisions=2, center=(-1.95, 1.35, 1.08), scale=(1.0, 1.0, 0.6), mat_idx=7)
    # Anvil next to Forge
    add_beveled_box(bm, 0.42, 0.24, 0.36, center=(-1.25, 1.72, 0.60), bevel_amt=0.04, mat_idx=5)
    # Timber Porch & Support Pillars
    add_beveled_box(bm, 4.2, 1.45, 0.16, center=(0, 1.62, 2.18), rot=(0.24, 0, 0), bevel_amt=0.03, mat_idx=2)
    for px in (-1.85, 1.85):
        add_cylinder(bm, 0.12, 0.12, 1.85, segments=12, center=(px, 2.15, 1.18), mat_idx=3)
    # Weapon Rack & Archery Target
    add_beveled_box(bm, 1.3, 0.28, 0.85, center=(1.35, 1.75, 0.85), bevel_amt=0.03, mat_idx=2)
    for sx in (1.0, 1.35, 1.7):
        add_cylinder(bm, 0.035, 0.02, 1.35, segments=8, center=(sx, 1.75, 1.15), mat_idx=5)
    # Double Oak Doors
    add_beveled_box(bm, 1.35, 0.22, 1.68, center=(-0.35, 1.15, 1.24), bevel_amt=0.04, mat_idx=3)
    return finalize_mesh("building_barracks", bm, mlist, col, split_angle_deg=44.0)


def build_building_tower(mats, col):
    bm = bmesh.new()
    mlist = [mats["stone"], mats["stone_dark"], mats["wood"], mats["roof_slate"], mats["gold_trim"], mats["window_glow"]]
    # Stepped Octagonal Base Plinth
    add_cylinder(bm, 1.95, 1.75, 0.65, segments=24, center=(0, 0, 0.325), mat_idx=1)
    add_cylinder(bm, 1.58, 1.35, 4.45, segments=24, center=(0, 0, 2.80), mat_idx=0)
    # Decorative Stone Banding Rings
    for hz in (1.45, 3.25, 4.85):
        r = 1.62 if hz < 2.0 else (1.50 if hz < 4.0 else 1.42)
        add_cylinder(bm, r, r, 0.20, segments=24, center=(0, 0, hz), mat_idx=1)
    # Glowing Arrow Slit Windows
    for ang_deg in (0, 90, 180, 270):
        rad = math.radians(ang_deg)
        add_beveled_box(bm, 0.20, 0.20, 0.65, center=(math.cos(rad) * 1.46, math.sin(rad) * 1.46, 3.0), bevel_amt=0.02, mat_idx=5)
    # Timber Hoarding Gallery & Corbels
    add_cylinder(bm, 1.68, 1.75, 0.95, segments=16, center=(0, 0, 5.45), mat_idx=2)
    for ang_deg in range(0, 360, 45):
        rad = math.radians(ang_deg)
        add_beveled_box(bm, 0.22, 0.55, 0.45, center=(math.cos(rad) * 1.45, math.sin(rad) * 1.45, 4.95), rot=(0, 0, rad + math.pi * 0.5), bevel_amt=0.03, mat_idx=2)
    # Battlements & Conical Slate Roof
    add_cylinder(bm, 2.15, 0.05, 2.25, segments=24, center=(0, 0, 7.02), mat_idx=3)
    add_cylinder(bm, 0.06, 0.04, 0.85, segments=10, center=(0, 0, 8.40), mat_idx=4)
    add_sphere(bm, 0.12, subdivisions=2, center=(0, 0, 8.20), mat_idx=4)
    return finalize_mesh("building_tower", bm, mlist, col, split_angle_deg=44.0)


def build_building_house(mats, col):
    bm = bmesh.new()
    mlist = [mats["stone_dark"], mats["plaster"], mats["wood_dark"], mats["roof_terracotta"], mats["straw"], mats["window_glow"], mats["wood"]]
    # Cobble Base
    add_beveled_box(bm, 3.6, 3.4, 0.48, center=(0, 0, 0.24), bevel_amt=0.08, mat_idx=0)
    # Plaster Cottage Walls
    add_beveled_box(bm, 3.2, 2.9, 1.70, center=(0, 0, 1.32), bevel_amt=0.04, mat_idx=1)
    # Timber Frame Beams
    for sx in (-1.62, 0.0, 1.62):
        add_beveled_box(bm, 0.16, 3.02, 1.72, center=(sx, 0, 1.32), bevel_amt=0.02, mat_idx=2)
    add_beveled_box(bm, 3.36, 3.06, 0.16, center=(0, 0, 2.10), bevel_amt=0.02, mat_idx=2)
    # Glowing Windows
    for wx in (-0.82, 0.82):
        add_beveled_box(bm, 0.44, 3.04, 0.52, center=(wx, 0, 1.38), bevel_amt=0.02, mat_idx=5)
    # Stone Chimney
    add_beveled_box(bm, 0.58, 0.58, 2.3, center=(-1.15, -0.9, 2.75), bevel_amt=0.05, mat_idx=0)
    # Front Oak Door
    add_beveled_box(bm, 0.72, 0.20, 1.25, center=(0, 1.48, 1.08), bevel_amt=0.03, mat_idx=2)
    # Overhanging Terracotta Roof
    add_pitched_roof(bm, 3.35, 3.05, 1.58, center=(0, 0, 2.18), overhang=0.35, mat_idx=3, ridge_mat_idx=0)
    # Oak Barrels & Hay Stack
    add_cylinder(bm, 0.24, 0.22, 0.58, segments=14, center=(1.95, 0.75, 0.29), mat_idx=6)
    add_cylinder(bm, 0.24, 0.22, 0.58, segments=14, center=(1.92, 0.15, 0.29), mat_idx=6)
    add_sphere(bm, 0.62, subdivisions=2, center=(2.05, -0.65, 0.42), scale=(1.0, 1.0, 0.85), mat_idx=4, noise_amp=0.14, seed=9)
    return finalize_mesh("building_house", bm, mlist, col, split_angle_deg=44.0)


def build_resource_tree(mats, col):
    bm = bmesh.new()
    mlist = [mats["wood_dark"], mats["foliage_1"], mats["foliage_2"], mats["foliage_3"]]
    # Gnarled organic trunk & flared roots
    add_cylinder(bm, 0.44, 0.26, 1.0, segments=12, center=(0, 0, 0.5), mat_idx=0)
    add_cylinder(bm, 0.26, 0.15, 1.4, segments=12, center=(0.06, 0.04, 1.65), rot=(0.06, -0.05, 0), mat_idx=0)
    for ang_deg in range(0, 360, 72):
        rad = math.radians(ang_deg)
        add_cylinder(bm, 0.15, 0.06, 0.75, segments=8, center=(math.cos(rad) * 0.35, math.sin(rad) * 0.35, 0.22), rot=(math.sin(rad) * 0.7, -math.cos(rad) * 0.7, 0), mat_idx=0)
    # Lush Organic Canopy Clusters (Multi-tiered overlapping icospheres with noise displacement)
    clusters = [
        ((0.0, 0.0, 2.55), 1.25, (1.15, 1.15, 0.82), 1, 1),
        ((-0.85, 0.45, 2.35), 0.88, (1.05, 1.0, 0.85), 1, 2),
        ((0.85, -0.35, 2.40), 0.90, (1.0, 1.08, 0.82), 1, 3),
        ((0.25, 0.85, 2.50), 0.85, (1.05, 1.0, 0.85), 2, 4),
        ((-0.35, -0.82, 2.45), 0.85, (1.0, 1.05, 0.85), 2, 5),
        ((0.0, 0.0, 3.45), 1.05, (1.05, 1.05, 0.88), 2, 6),
        ((-0.52, -0.30, 3.35), 0.72, (1.0, 1.0, 0.88), 2, 7),
        ((0.55, 0.35, 3.40), 0.75, (1.0, 1.0, 0.88), 3, 8),
        ((0.05, -0.05, 4.25), 0.72, (0.95, 0.95, 0.95), 3, 9),
    ]
    for pos, rad, sc, m_i, sd in clusters:
        add_sphere(bm, rad, subdivisions=2, center=pos, scale=sc, mat_idx=m_i, noise_amp=0.16, seed=sd)
    return finalize_mesh("resource_tree", bm, mlist, col, split_angle_deg=120.0)


def build_resource_gold_mine(mats, col):
    bm = bmesh.new()
    granite_dark = make_pbr_material("Mat_GraniteDark", (0.25, 0.25, 0.26), roughness=0.88)
    mlist = [mats["rock"], granite_dark, mats["wood_dark"], mats["gold"], mats["steel"], mats["ember_glow"], mats["stone_dark"]]
    # Sculpted Craggy Rock Formations (Subdivision 2 + Natural Granite without masonry)
    add_sphere(bm, 2.10, subdivisions=2, center=(0.0, -0.15, 0.92), scale=(1.18, 1.05, 0.72), mat_idx=0, noise_amp=0.22, seed=15)
    add_sphere(bm, 1.35, subdivisions=2, center=(-0.85, -0.45, 1.32), scale=(1.02, 0.96, 0.86), mat_idx=1, noise_amp=0.24, seed=25)
    add_sphere(bm, 1.25, subdivisions=2, center=(0.88, -0.38, 1.18), scale=(0.95, 1.02, 0.82), mat_idx=0, noise_amp=0.22, seed=35)
    # Tunnel Timber Frame & Recessed Dark Mine Shaft
    for sx in (-0.78, 0.78):
        add_beveled_box(bm, 0.24, 0.26, 1.58, center=(sx, 1.48, 0.79), bevel_amt=0.03, mat_idx=2)
    add_beveled_box(bm, 1.92, 0.30, 0.26, center=(0.0, 1.48, 1.62), bevel_amt=0.03, mat_idx=2)
    add_beveled_box(bm, 1.28, 0.55, 1.38, center=(0.0, 1.20, 0.72), bevel_amt=0.03, mat_idx=6)
    # Steel Minecart Rails emerging from tunnel
    for rx in (-0.36, 0.36):
        add_beveled_box(bm, 0.06, 1.45, 0.06, center=(rx, 2.05, 0.05), bevel_amt=0.01, mat_idx=4)
    for ty in (1.55, 1.90, 2.25, 2.60):
        add_beveled_box(bm, 0.98, 0.10, 0.05, center=(0.0, ty, 0.03), bevel_amt=0.01, mat_idx=2)
    # Glowing Warm Miner's Lantern hanging at entrance
    add_sphere(bm, 0.14, subdivisions=2, center=(0.56, 1.68, 1.32), scale=(0.85, 0.85, 1.25), mat_idx=5)
    # Rich Faceted Gold Crystal Clusters (protruding clearly out of rock fissures)
    crystals = [
        ((-1.45, 0.75, 1.35), (0.35, 0.55, 0.2), 0.72),
        ((1.45, 0.65, 1.25), (-0.25, -0.60, 0.1), 0.76),
        ((0.15, 0.05, 2.22), (0.20, 0.15, 0.3), 0.80),
        ((-0.65, 0.95, 1.90), (0.45, -0.25, 0.0), 0.65),
        ((0.75, -0.45, 1.85), (-0.35, 0.35, 0.2), 0.68),
        ((-1.60, -0.30, 0.85), (0.15, 0.75, -0.2), 0.64),
        ((1.10, 1.38, 0.68), (-0.50, 0.35, 0.2), 0.56),
        ((-0.20, -1.10, 1.75), (-0.45, -0.15, 0.1), 0.62),
    ]
    for pos, rot, sc in crystals:
        add_cylinder(bm, sc * 0.44, sc * 0.05, sc * 1.95, segments=6, center=pos, rot=rot, mat_idx=3)
    return finalize_mesh("resource_gold_mine", bm, mlist, col, split_angle_deg=45.0)


def build_prop_cliff_rock(mats, col):
    bm = bmesh.new()
    granite_dark = make_pbr_material("Mat_GraniteDark", (0.25, 0.25, 0.26), roughness=0.88)
    mlist = [mats["rock"], granite_dark, mats["foliage_1"], mats["foliage_2"]]
    # Aglomerado escultural de rochas facetadas/chanfradas com cobertura de musgo (subdivisions=2 para silhueta orgânica)
    add_sphere(bm, 1.35, subdivisions=2, center=(-0.35, 0.15, 0.85), scale=(1.25, 0.95, 0.82), rot=(0.1, 0.2, 0.4), mat_idx=0, noise_amp=0.26, seed=41)
    add_sphere(bm, 1.05, subdivisions=2, center=(0.85, -0.25, 0.65), scale=(1.10, 0.90, 0.72), rot=(-0.2, 0.1, -0.5), mat_idx=1, noise_amp=0.25, seed=42)
    add_sphere(bm, 0.85, subdivisions=2, center=(0.15, 0.75, 0.55), scale=(1.15, 0.85, 0.68), rot=(0.2, -0.1, 0.8), mat_idx=0, noise_amp=0.22, seed=43)
    add_sphere(bm, 0.92, subdivisions=2, center=(-0.45, -0.35, 1.45), scale=(0.95, 0.85, 0.72), rot=(0.15, 0.15, -0.2), mat_idx=1, noise_amp=0.24, seed=44)
    # Camadas superiores de musgo verde-floresta
    add_sphere(bm, 0.78, subdivisions=2, center=(-0.38, 0.10, 1.72), scale=(1.1, 0.9, 0.28), mat_idx=2, noise_amp=0.18, seed=45)
    add_sphere(bm, 0.62, subdivisions=2, center=(0.82, -0.22, 1.18), scale=(1.0, 0.85, 0.25), mat_idx=3, noise_amp=0.16, seed=46)
    return finalize_mesh("prop_cliff_rock", bm, mlist, col, split_angle_deg=48.0)


def build_prop_shrub_cluster(mats, col):
    bm = bmesh.new()
    mlist = [mats["wood_dark"], mats["foliage_1"], mats["foliage_2"], mats["foliage_3"], mats["gold"], mats["feather"]]
    # Caules internos
    for ang in (0.0, 2.1, 4.2):
        add_cylinder(bm, 0.06, 0.03, 0.38, segments=6, center=(math.cos(ang) * 0.25, math.sin(ang) * 0.25, 0.18), mat_idx=0)
    # Folhagem densa em 3 tons de verde (subdivisions=2 para silhueta cheia e arredondada)
    clusters = [
        ((0.0, 0.0, 0.42), 0.52, (1.15, 1.08, 0.78), 1, 51),
        ((-0.48, 0.26, 0.32), 0.38, (1.05, 1.0, 0.75), 2, 52),
        ((0.46, -0.22, 0.34), 0.40, (1.0, 1.1, 0.76), 2, 53),
        ((0.22, 0.48, 0.28), 0.34, (1.05, 0.95, 0.72), 3, 54),
        ((-0.24, -0.45, 0.30), 0.35, (1.0, 1.05, 0.72), 3, 55),
    ]
    for pos, rad, sc, m_i, sd in clusters:
        add_sphere(bm, rad, subdivisions=2, center=pos, scale=sc, mat_idx=m_i, noise_amp=0.18, seed=sd)
    # Pequenas flores campestres no arbusto
    for fx, fy, fz, fm in [(-0.2, 0.15, 0.76, 4), (0.35, -0.1, 0.58, 5), (-0.42, 0.32, 0.54, 4), (0.12, 0.42, 0.52, 4)]:
        add_sphere(bm, 0.08, subdivisions=1, center=(fx, fy, fz), mat_idx=fm)
    return finalize_mesh("prop_shrub_cluster", bm, mlist, col, split_angle_deg=120.0)


def build_prop_ruins_arch(mats, col):
    bm = bmesh.new()
    mlist = [mats["stone"], mats["stone_dark"], mats["foliage_1"], mats["gold_trim"], mats["ember_glow"]]
    # Base de lajotas antigas quebradas
    add_beveled_box(bm, 4.1, 3.2, 0.24, center=(0.0, 0.0, 0.12), bevel_amt=0.05, mat_idx=1)
    add_beveled_box(bm, 2.8, 2.2, 0.18, center=(-0.3, 0.2, 0.28), rot=(0, 0, 0.08), bevel_amt=0.04, mat_idx=0)
    # Coluna esquerda inteira canelada + capitel + meio arco gótico
    add_beveled_box(bm, 0.92, 0.92, 0.36, center=(-1.35, 0.0, 0.42), bevel_amt=0.05, mat_idx=1)
    add_cylinder(bm, 0.34, 0.30, 2.45, segments=14, center=(-1.35, 0.0, 1.82), mat_idx=0)
    add_beveled_box(bm, 0.88, 0.88, 0.32, center=(-1.35, 0.0, 3.15), bevel_amt=0.04, mat_idx=1)
    # Segmentos curvos do arco quebrado no topo
    add_beveled_box(bm, 1.05, 0.64, 0.48, center=(-0.78, 0.0, 3.48), rot=(0, -0.22, 0), bevel_amt=0.04, mat_idx=0)
    add_beveled_box(bm, 0.82, 0.58, 0.44, center=(-0.08, 0.0, 3.68), rot=(0, -0.05, 0), bevel_amt=0.04, mat_idx=1)
    # Coluna direita quebrada + segmento tombado no chão
    add_beveled_box(bm, 0.92, 0.92, 0.36, center=(1.35, 0.0, 0.42), bevel_amt=0.05, mat_idx=1)
    add_cylinder(bm, 0.34, 0.32, 1.05, segments=14, center=(1.35, 0.0, 1.12), mat_idx=0)
    add_cylinder(bm, 0.31, 0.30, 1.15, segments=14, center=(1.65, 0.95, 0.38), rot=(1.42, 0.25, 0.5), mat_idx=0)
    # Pedestal rúnico central com braseiro dourado iluminado
    add_beveled_box(bm, 0.82, 0.82, 0.95, center=(0.0, 0.0, 0.72), bevel_amt=0.05, mat_idx=1)
    add_cylinder(bm, 0.36, 0.46, 0.28, segments=14, center=(0.0, 0.0, 1.32), mat_idx=3)
    add_sphere(bm, 0.24, subdivisions=2, center=(0.0, 0.0, 1.56), scale=(1.0, 1.0, 1.25), mat_idx=4)
    # Musgo crescendo sobre as ruínas
    add_sphere(bm, 0.55, subdivisions=2, center=(-1.35, 0.15, 3.38), scale=(1.0, 0.8, 0.32), mat_idx=2, noise_amp=0.18, seed=61)
    add_sphere(bm, 0.48, subdivisions=2, center=(1.35, -0.1, 1.68), scale=(0.95, 0.85, 0.30), mat_idx=2, noise_amp=0.18, seed=62)
    return finalize_mesh("prop_ruins_arch", bm, mlist, col, split_angle_deg=44.0)


def export_glb(obj, filepath):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
    )
    print(f"[Blender] Exported: {filepath}")


def set_eevee_engine(scene):
    for candidate in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "CYCLES"):
        try:
            scene.render.engine = candidate
            return
        except TypeError:
            continue


def setup_showcase_and_render(objects, mats):
    positions = [
        (-9.5, 5.5, 0.0),   # worker
        (-6.2, 5.5, 0.0),   # soldier
        (-2.8, 5.5, 0.0),   # archer
        (0.5, 5.5, 0.0),    # knight
        (4.5, 5.5, 0.0),    # tree
        (9.2, 5.5, 0.0),    # gold mine
        (13.8, 5.5, 0.0),   # cliff rock
        (-10.5, -3.8, 0.0), # house
        (-3.8, -3.8, 0.0),  # barracks
        (2.8, -3.8, 0.0),   # tower
        (9.8, -3.8, 0.0),   # town center
        (-14.0, 1.0, 0.0),  # shrub
        (15.5, -3.2, 0.0),  # ruins arch
    ]
    for obj, pos in zip(objects, positions):
        obj.location = pos
        obj.rotation_euler = Euler((0.0, 0.0, math.pi), "XYZ")

    col = get_or_create_collection("Showcase")
    bm = bmesh.new()
    add_beveled_box(bm, 34.0, 22.0, 0.5, center=(1.5, 0.5, -0.25), bevel_amt=0.05, mat_idx=0)
    floor_mat = make_pbr_material("Mat_Pedestal", (0.14, 0.22, 0.13), roughness=0.88)
    finalize_mesh("Showcase_Pedestal", bm, [floor_mat], col)

    world = bpy.data.worlds.new("ShowcaseWorld")
    bpy.context.scene.world = world
    if hasattr(world, "use_nodes"):
        world.use_nodes = True
    bg = next((n for n in world.node_tree.nodes if n.type == "BACKGROUND"), None)
    if bg:
        bg.inputs[0].default_value = (0.34, 0.50, 0.74, 1.0)
        bg.inputs[1].default_value = 0.95

    sun_data = bpy.data.lights.new("SunKey", type="SUN")
    sun_data.energy = 3.2
    sun_obj = bpy.data.objects.new("SunKey", sun_data)
    sun_obj.rotation_euler = Euler((math.radians(46), math.radians(15), math.radians(-35)), "XYZ")
    col.objects.link(sun_obj)

    fill_data = bpy.data.lights.new("RimLight", type="AREA")
    fill_data.energy = 300.0
    fill_data.size = 14.0
    fill_obj = bpy.data.objects.new("RimLight", fill_data)
    fill_obj.location = (-10.0, -16.0, 13.0)
    fill_obj.rotation_euler = Euler((math.radians(55), 0.0, math.radians(-25)), "XYZ")
    col.objects.link(fill_obj)

    cam_data = bpy.data.cameras.new("ShowcaseCam")
    cam_data.lens = 35.0
    cam_obj = bpy.data.objects.new("ShowcaseCam", cam_data)
    col.objects.link(cam_obj)
    cam_obj.location = (1.5, -27.0, 15.5)
    direction = Vector((1.5, 0.6, 1.8)) - cam_obj.location
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()

    scene = bpy.context.scene
    scene.camera = cam_obj
    set_eevee_engine(scene)
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.filepath = os.path.join(BLENDER_DIR, "assets_preview.png")

    blend_path = os.path.join(BLENDER_DIR, "coroa_de_ferro_assets.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    bpy.ops.render.render(write_still=True)
    print(f"[Blender] Rendered preview: {scene.render.filepath}")


def main():
    clear_scene()
    mats = create_materials()
    col = get_or_create_collection("RTS_Assets")

    import sys
    if SCRIPT_DIR not in sys.path:
        sys.path.insert(0, SCRIPT_DIR)
    import generate_unit_assets
    unit_mats = generate_unit_assets.create_character_materials()
    unit_builders = [
        ("unit_worker", generate_unit_assets.build_unit_worker),
        ("unit_soldier", generate_unit_assets.build_unit_soldier),
        ("unit_archer", generate_unit_assets.build_unit_archer),
        ("unit_knight", generate_unit_assets.build_unit_knight),
    ]

    builders = [
        ("resource_tree", build_resource_tree),
        ("resource_gold_mine", build_resource_gold_mine),
        ("building_house", build_building_house),
        ("building_barracks", build_building_barracks),
        ("building_tower", build_building_tower),
        ("building_town_center", build_building_town_center),
        ("prop_cliff_rock", build_prop_cliff_rock),
        ("prop_shrub_cluster", build_prop_shrub_cluster),
        ("prop_ruins_arch", build_prop_ruins_arch),
    ]

    created_objects = []
    for unit_name, ufn in unit_builders:
        arm_obj, mesh_obj = ufn(unit_mats, col)
        glb_path = os.path.join(MODELS_DIR, f"{unit_name}.glb")
        generate_unit_assets.export_unit_glb(arm_obj, mesh_obj, glb_path)
        created_objects.append(arm_obj)

    for asset_name, fn in builders:
        obj = fn(mats, col)
        glb_path = os.path.join(MODELS_DIR, f"{asset_name}.glb")
        export_glb(obj, glb_path)
        created_objects.append(obj)

    setup_showcase_and_render(created_objects, mats)
    print("[Blender] ALL 13 HIGH-DETAIL PBR RTS ASSETS GENERATED SUCCESSFULLY.")


if __name__ == "__main__":
    main()
