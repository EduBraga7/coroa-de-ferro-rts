"""Renderiza retratos 3D de todos os 23 modelos GLB para o HUD ('assets/ui/portraits/').

Executar em Blender 5.2 headless:
    blender --background --python tools/render_hud_portraits.py
"""

import math
import os
import time
import bpy
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
MODELS_DIR = os.path.join(PROJECT_DIR, "assets", "models")
OUT_DIR = os.path.join(PROJECT_DIR, "assets", "ui", "portraits")
os.makedirs(OUT_DIR, exist_ok=True)

ASSETS = [
    # Unidades (humanoides em retrato heroico busto/peito -> capacete/arma; ariete inteiro)
    "unit_worker",
    "unit_scout",
    "unit_soldier",
    "unit_spearman",
    "unit_archer",
    "unit_knight",
    "unit_ram",
    # Prédios (3/4 isométrico completo)
    "building_town_center",
    "building_house",
    "building_farm",
    "building_mill",
    "building_lumber_camp",
    "building_mining_camp",
    "building_market",
    "building_barracks",
    "building_archery_range",
    "building_siege_workshop",
    "building_tower",
    "building_castle",
    "building_lair",
    # Recursos
    "resource_berry_bush",
    "resource_tree",
    "resource_gold_mine",
    "resource_stone_quarry",
]

HUMANOID_UNITS = {
    "unit_worker",
    "unit_scout",
    "unit_soldier",
    "unit_spearman",
    "unit_archer",
    "unit_knight",
}

TEAM_TINTS = {
    "Mat_TeamPrimary": (0.10, 0.36, 0.92, 1.0),
    "Mat_TeamCape": (0.06, 0.22, 0.68, 1.0),
    "Mat_TeamAccent": (0.24, 0.62, 1.00, 1.0),
}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tint_team_materials():
    """Tinta materiais neutros Mat_Team* para o Azul Real do jogador preservando texturas."""
    for mat in bpy.data.materials:
        if not mat.use_nodes or not mat.node_tree:
            continue
        tint = None
        for prefix, col in TEAM_TINTS.items():
            if mat.name.startswith(prefix):
                tint = col
                break
        if tint is None:
            continue

        nt = mat.node_tree
        nodes = nt.nodes
        links = nt.links
        bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None or "Base Color" not in bsdf.inputs:
            continue

        base_in = bsdf.inputs["Base Color"]
        if base_in.is_linked:
            src_sock = base_in.links[0].from_socket
            links.remove(base_in.links[0])
            mix = nodes.new("ShaderNodeMix")
            mix.data_type = "RGBA"
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0
            rgba_in = [s for s in mix.inputs if s.type == "RGBA"]
            rgba_out = [s for s in mix.outputs if s.type == "RGBA"]
            if len(rgba_in) >= 2 and len(rgba_out) >= 1:
                links.new(src_sock, rgba_in[0])
                rgba_in[1].default_value = tint
                links.new(rgba_out[0], base_in)
        else:
            base_in.default_value = tint


def remove_bone_shape_widgets():
    """Remove meshes auxiliares de bone shape exportados pelo glTF (ex: Icosphere)."""
    for obj in list(bpy.context.scene.objects):
        if obj.type == "MESH" and obj.name.startswith("Icosphere"):
            bpy.data.objects.remove(obj, do_unlink=True)


def compute_world_bounds():
    """Calcula AABB global de todas as malhas avaliadas na cena atual."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    pts = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH" or obj.hide_render:
            continue
        eval_obj = obj.evaluated_get(depsgraph)
        me = eval_obj.to_mesh()
        if me is None or len(me.vertices) == 0:
            eval_obj.to_mesh_clear()
            continue
        mw = eval_obj.matrix_world
        for v in me.vertices:
            pts.append(mw @ v.co)
        eval_obj.to_mesh_clear()

    if not pts:
        return Vector((-1, -1, 0)), Vector((1, 1, 2))
    xs = [p.x for p in pts]
    ys = [p.y for p in pts]
    zs = [p.z for p in pts]
    return Vector((min(xs), min(ys), min(zs))), Vector((max(xs), max(ys), max(zs)))


def find_armature_bones():
    for obj in bpy.context.scene.objects:
        if obj.type == "ARMATURE":
            out = {}
            for bname in ("Hips", "Chest", "Head"):
                pb = obj.pose.bones.get(bname)
                if pb is not None:
                    out[bname] = obj.matrix_world @ pb.head
            return out
    return {}


def configure_render():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.03
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 2
    scene.cycles.transparent_max_bounces = 4

    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"

    try:
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.look = "AgX - Medium High Contrast"
    except Exception:
        try:
            scene.view_settings.view_transform = "Filmic"
        except Exception:
            pass
    scene.view_settings.exposure = 0.62

    world = bpy.data.worlds.new("StudioWorld")
    scene.world = world
    world.use_nodes = True
    wnodes = world.node_tree.nodes
    bg = wnodes.get("Background")
    if bg is not None:
        bg.inputs[0].default_value = (0.20, 0.24, 0.32, 1.0)
        bg.inputs[1].default_value = 0.65


def add_area_light(name, location, target, color, energy, size):
    ldata = bpy.data.lights.new(name=name, type="AREA")
    ldata.color = color
    ldata.energy = energy
    ldata.size = size
    lobj = bpy.data.objects.new(name=name, object_data=ldata)
    bpy.context.scene.collection.objects.link(lobj)
    lobj.location = location
    direction = (target - location).normalized()
    lobj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return lobj


def setup_camera_and_lights(stem, bmin, bmax):
    span = bmax - bmin
    full_center = (bmin + bmax) * 0.5
    full_radius = max(0.35, span.length * 0.5)

    # Parâmetros de enquadramento por categoria
    if stem in HUMANOID_UNITS:
        bones = find_armature_bones()
        hips_z = bones["Hips"].z if "Hips" in bones else (bmin.z + 0.72)
        head_z = bones["Head"].z if "Head" in bones else (bmin.z + 1.24)
        z_lo = hips_z - 0.04
        # Garante topo generoso para chapéu/elmo/pluma sem deixar lança gigante afastar a câmera
        cap_top = head_z + (0.84 if stem == "unit_knight" else (0.68 if stem == "unit_soldier" else 0.56))
        z_hi = min(bmax.z + 0.08, cap_top)
        focus = Vector((0.0, 0.0, (z_lo + z_hi) * 0.5))
        half_h = (z_hi - z_lo) * 0.52
        half_w = half_h * 0.90
        az_deg = -24.0
        el_deg = 7.0
        lens_mm = 70.0
        fill_factor = 0.86
    elif stem == "unit_ram":
        focus = full_center + Vector((0.0, 0.0, span.z * 0.03))
        half_h = span.z * 0.55
        half_w = max(span.x, span.y) * 0.58
        az_deg = -38.0
        el_deg = 22.0
        lens_mm = 50.0
        fill_factor = 0.82
    elif stem.startswith("building_"):
        focus = full_center + Vector((0.0, 0.0, span.z * 0.04))
        half_h = span.z * 0.54
        half_w = math.hypot(span.x, span.y) * 0.48
        az_deg = -38.0
        el_deg = 42.0 if stem == "building_farm" else (20.0 if stem == "building_tower" else 27.0)
        lens_mm = 45.0
        fill_factor = 0.82
    else:
        # Recursos
        focus = full_center + Vector((0.0, 0.0, span.z * 0.04))
        half_h = span.z * 0.54
        half_w = max(span.x, span.y) * 0.55
        az_deg = -30.0
        el_deg = 24.0
        lens_mm = 50.0
        fill_factor = 0.82

    cam_data = bpy.data.cameras.new("PortraitCam")
    cam_data.lens = lens_mm
    cam_data.sensor_width = 36.0
    fov = 2.0 * math.atan(cam_data.sensor_width / (2.0 * cam_data.lens))

    # Direção da câmera partindo da frente (+Y) com azimute e elevação
    az = math.radians(az_deg)
    el = math.radians(el_deg)
    view_dir = Vector((
        math.sin(az) * math.cos(el),
        math.cos(az) * math.cos(el),
        math.sin(el),
    )).normalized()

    req_half = max(half_h, half_w) / fill_factor
    dist = req_half / math.tan(fov * 0.5)
    cam_pos = focus + view_dir * dist

    cam_obj = bpy.data.objects.new("PortraitCam", cam_data)
    bpy.context.scene.collection.objects.link(cam_obj)
    cam_obj.location = cam_pos
    cam_obj.rotation_euler = (focus - cam_pos).normalized().to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = cam_obj

    # Iluminação de estúdio em 3 pontos escalada ao tamanho real do modelo
    r = full_radius
    # Vetores no plano da câmera
    forward = view_dir
    right = Vector((0, 0, 1)).cross(forward).normalized()
    up = Vector((0, 0, 1))

    key_pos = focus + (forward * 1.4 - right * 1.6 + up * 1.9) * r * 1.8
    fill_pos = focus + (forward * 1.1 + right * 2.1 + up * 0.9) * r * 1.9
    rim_pos = focus + (-forward * 1.9 + right * 0.5 + up * 2.1) * r * 1.9

    # Potência de área em Cycles escala com r^2 para exposição consistente entre camponês e castelo
    r2 = max(0.75, r * r)
    add_area_light("KeyLight", key_pos, focus, (1.0, 0.91, 0.74), energy=125.0 * r2, size=2.4 * r)
    add_area_light("FillLight", fill_pos, focus, (0.62, 0.80, 1.00), energy=58.0 * r2, size=3.4 * r)
    add_area_light("RimLight", rim_pos, focus, (1.0, 0.95, 0.84), energy=145.0 * r2, size=2.2 * r)


def render_one(stem):
    glb_path = os.path.join(MODELS_DIR, f"{stem}.glb")
    out_path = os.path.join(OUT_DIR, f"{stem}.png")
    if not os.path.exists(glb_path):
        print(f"[Portrait] MISSING: {glb_path}")
        return False

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=glb_path)
    remove_bone_shape_widgets()
    bpy.context.scene.frame_set(1)
    bpy.context.view_layer.update()

    if stem.startswith("unit_"):
        tint_team_materials()
    configure_render()
    bmin, bmax = compute_world_bounds()
    setup_camera_and_lights(stem, bmin, bmax)

    bpy.context.scene.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    return os.path.exists(out_path)


def main():
    t0 = time.time()
    ok = 0
    for stem in ASSETS:
        ts = time.time()
        res = render_one(stem)
        dt = time.time() - ts
        print(f"[Portrait] {stem}: {'OK' if res else 'FAIL'} ({dt:.2f}s)")
        if res:
            ok += 1
    print(f"[Portrait] Finished {ok}/{len(ASSETS)} portraits in {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
