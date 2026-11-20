"""Gera ícones medievais supersampled (4x -> 64x64 / 128x128) e chrome 9-slice metálico para o HUD.

Saída:
  assets/ui/icons/*.png
  assets/ui/chrome/*.png
"""

import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(SCRIPT_DIR)
ICONS_DIR = os.path.join(PROJECT_DIR, "assets", "ui", "icons")
CHROME_DIR = os.path.join(PROJECT_DIR, "assets", "ui", "chrome")
os.makedirs(ICONS_DIR, exist_ok=True)
os.makedirs(CHROME_DIR, exist_ok=True)


# ==============================================================================
# UTILITÁRIOS DE DESENHO VETORIAL & CONTORNO SUPERSAMPLED
# ==============================================================================

def add_contour_and_shadow(im: Image.Image, outline_r: int = 5, shadow_dy: int = 4) -> Image.Image:
    """Adiciona contorno escuro nítido e sombra projetada suave usando apenas NumPy."""
    arr = np.asarray(im, dtype=np.uint8)
    alpha = arr[..., 3].astype(np.float32) / 255.0
    h, w = alpha.shape

    max_a = np.zeros_like(alpha)
    r2 = outline_r * outline_r
    for dy in range(-outline_r, outline_r + 1):
        for dx in range(-outline_r, outline_r + 1):
            if dx * dx + dy * dy > r2:
                continue
            src_y0 = max(0, -dy)
            src_y1 = min(h, h - dy)
            src_x0 = max(0, -dx)
            src_x1 = min(w, w - dx)
            dst_y0 = max(0, dy)
            dst_y1 = dst_y0 + (src_y1 - src_y0)
            dst_x0 = max(0, dx)
            dst_x1 = dst_x0 + (src_x1 - src_x0)
            max_a[dst_y0:dst_y1, dst_x0:dst_x1] = np.maximum(
                max_a[dst_y0:dst_y1, dst_x0:dst_x1],
                alpha[src_y0:src_y1, src_x0:src_x1],
            )

    # Sombra deslocada para baixo
    shad_a = np.zeros_like(alpha)
    if shadow_dy > 0:
        shad_a[shadow_dy:, :] = max_a[:-shadow_dy, :] * 0.55

    bg_a = np.clip(np.maximum(max_a * 0.92, shad_a), 0.0, 1.0)
    contour = np.zeros((h, w, 4), dtype=np.uint8)
    contour[..., 0] = 10
    contour[..., 1] = 11
    contour[..., 2] = 15
    contour[..., 3] = np.clip(bg_a * 255.0, 0, 255).astype(np.uint8)

    base = Image.fromarray(contour, mode="RGBA")
    return Image.alpha_composite(base, im)


def _new_hi(size: int = 256):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def _save_icon(name: str, im: Image.Image, target: int = 64, outline_r: int = 5):
    outlined = add_contour_and_shadow(im, outline_r=outline_r, shadow_dy=4)
    out = outlined.resize((target, target), Image.Resampling.LANCZOS)
    out.save(os.path.join(ICONS_DIR, f"{name}.png"))


def _pt(x: float, y: float, s: float = 256.0):
    return (x * s, y * s)


def _pts(coords, s: float = 256.0):
    return [(x * s, y * s) for x, y in coords]


def _poly(draw, coords, fill, outline=None, width=3, s=256.0):
    draw.polygon(_pts(coords, s), fill=fill, outline=outline, width=width)


def _line(draw, coords, fill, width=8, s=256.0):
    draw.line(_pts(coords, s), fill=fill, width=width, joint="curve")


def _circle(draw, cx, cy, r, fill, outline=None, width=3, s=256.0):
    draw.ellipse([(cx - r) * s, (cy - r) * s, (cx + r) * s, (cy + r) * s],
                 fill=fill, outline=outline, width=width)


# ==============================================================================
# GERADORES DE ÍCONES MEDIEVAIS (4x SUPERSAMPLED)
# ==============================================================================

def draw_res_food():
    im, d = _new_hi()
    # Três hastes de trigo dourado + feixe + frutos vermelhos silvestres
    stalks = [(-0.22, -16), (0.0, 0), (0.22, 16)]
    for dx, ang in stalks:
        rad = math.radians(ang)
        cx, cy = 0.50 + dx * 0.55, 0.52
        vx, vy = math.sin(rad), -math.cos(rad)
        px, py = math.cos(rad), math.sin(rad)
        # Haste
        _line(d, [(cx - vx * 0.16, cy - vy * 0.16 + 0.24), (cx + vx * 0.28, cy + vy * 0.28)],
              (196, 146, 44, 255), width=9)
        # Grãos alternados na espiga
        for k in range(5):
            t = 0.04 + k * 0.075
            gx = cx + vx * t
            gy = cy + vy * t
            for side in (-1, 1):
                ox = gx + px * side * 0.058 + vx * 0.02
                oy = gy + py * side * 0.058 + vy * 0.02
                col = (248, 206, 86, 255) if side < 0 else (218, 162, 46, 255)
                _circle(d, ox, oy, 0.046, col, outline=(132, 88, 18, 255), width=2)
        _circle(d, cx + vx * 0.37, cy + vy * 0.37, 0.042, (255, 224, 120, 255))

    # Fita carmesim amarrando o feixe
    _poly(d, [(0.36, 0.69), (0.64, 0.69), (0.62, 0.77), (0.38, 0.77)],
          (185, 42, 42, 255), outline=(92, 18, 18, 255), width=3)
    # Cachinho de frutos silvestres rubi na base
    for bx, by, br, c in [
        (0.68, 0.73, 0.085, (215, 42, 48, 255)),
        (0.58, 0.80, 0.080, (186, 26, 36, 255)),
        (0.75, 0.81, 0.072, (238, 66, 66, 255)),
    ]:
        _circle(d, bx, by, br, c, outline=(85, 14, 18, 255), width=3)
        _circle(d, bx - br * 0.32, by - br * 0.32, br * 0.25, (255, 195, 185, 210))
    _save_icon("res_food", im)


def draw_res_wood():
    im, d = _new_hi()
    # Três toras de carvalho empilhadas em perspectiva
    logs = [(0.30, 0.66, 0.20, 0.44), (0.58, 0.66, 0.48, 0.44), (0.44, 0.42, 0.34, 0.20)]
    for x1, y1, x2, y2 in logs:
        r = 0.135
        # Corpo da tora
        dx, dy = x2 - x1, y2 - y1
        ln = math.hypot(dx, dy)
        nx, ny = -dy / ln * r, dx / ln * r
        _poly(d, [
            (x1 - nx, y1 - ny), (x2 - nx, y2 - ny),
            (x2 + nx, y2 + ny), (x1 + nx, y1 + ny),
        ], (122, 74, 36, 255), outline=(58, 32, 14, 255), width=3)
        # Luz na casca superior
        _poly(d, [
            (x1 - nx * 0.75, y1 - ny * 0.75), (x2 - nx * 0.75, y2 - ny * 0.75),
            (x2 - nx * 0.10, y2 - ny * 0.10), (x1 - nx * 0.10, y1 - ny * 0.10),
        ], (156, 98, 48, 255))
        # Topo cortado (anéis claros)
        _circle(d, x1, y1, r, (226, 178, 112, 255), outline=(88, 50, 22, 255), width=4)
        _circle(d, x1, y1, r * 0.62, (198, 145, 82, 255), outline=(146, 98, 46, 255), width=2)
        _circle(d, x1, y1, r * 0.25, (148, 96, 44, 255))
    _save_icon("res_wood", im)


def draw_res_gold():
    im, d = _new_hi()
    # Duas pilhas de moedas medievais douradas reluzentes
    def draw_coin(cx, cy, rx, ry, body_col, face_col):
        d.ellipse([(cx - rx) * 256, (cy - ry) * 256, (cx + rx) * 256, (cy + ry + 0.055) * 256],
                  fill=body_col, outline=(112, 74, 12, 255), width=3)
        d.ellipse([(cx - rx) * 256, (cy - ry) * 256, (cx + rx) * 256, (cy + ry) * 256],
                  fill=face_col, outline=(255, 240, 165, 255), width=2)
        d.ellipse([(cx - rx * 0.62) * 256, (cy - ry * 0.62) * 256,
                   (cx + rx * 0.62) * 256, (cy + ry * 0.62) * 256],
                  outline=(176, 120, 22, 255), width=2)

    for i in range(4):
        draw_coin(0.37, 0.72 - i * 0.10, 0.21, 0.085, (176, 118, 18, 255), (245, 198, 62, 255))
    for i in range(3):
        draw_coin(0.65, 0.77 - i * 0.10, 0.19, 0.080, (164, 108, 16, 255), (235, 186, 52, 255))
    # Brilho especular
    _poly(d, [(0.28, 0.24), (0.31, 0.30), (0.37, 0.33), (0.31, 0.36),
              (0.28, 0.42), (0.25, 0.36), (0.19, 0.33), (0.25, 0.30)],
          (255, 250, 210, 255))
    _save_icon("res_gold", im)


def draw_res_stone():
    im, d = _new_hi()
    # Bloco facetado de granito esculpido com chanfro medieval
    _poly(d, [(0.20, 0.36), (0.52, 0.18), (0.84, 0.34), (0.78, 0.72), (0.46, 0.86), (0.16, 0.68)],
          (148, 154, 164, 255), outline=(44, 48, 56, 255), width=4)
    # Face superior iluminada
    _poly(d, [(0.20, 0.36), (0.52, 0.18), (0.84, 0.34), (0.52, 0.50)], (202, 208, 218, 255))
    # Face direita sombreada
    _poly(d, [(0.52, 0.50), (0.84, 0.34), (0.78, 0.72), (0.46, 0.86)], (104, 110, 122, 255))
    # Face esquerda média
    _poly(d, [(0.20, 0.36), (0.52, 0.50), (0.46, 0.86), (0.16, 0.68)], (152, 158, 170, 255))
    # Trinca esculpida sutil
    _line(d, [(0.34, 0.42), (0.42, 0.56), (0.38, 0.70)], (76, 82, 92, 255), width=4)
    _line(d, [(0.21, 0.36), (0.52, 0.50), (0.83, 0.35)], (232, 236, 244, 200), width=3)
    _save_icon("res_stone", im)


def draw_res_pop():
    im, d = _new_hi()
    # Elmo medieval de aço polido com guarnição dourada
    # Cúpula do elmo
    _poly(d, [(0.24, 0.56), (0.28, 0.30), (0.50, 0.16), (0.72, 0.30), (0.76, 0.56),
              (0.70, 0.82), (0.57, 0.84), (0.55, 0.62), (0.45, 0.62), (0.43, 0.84), (0.30, 0.82)],
          (168, 178, 194, 255), outline=(42, 46, 56, 255), width=4)
    # Sombra lateral direita do aço
    _poly(d, [(0.50, 0.16), (0.72, 0.30), (0.76, 0.56), (0.70, 0.82), (0.57, 0.84), (0.55, 0.60), (0.50, 0.56)],
          (118, 128, 146, 255))
    # Fenda do visor
    _poly(d, [(0.28, 0.46), (0.72, 0.46), (0.70, 0.55), (0.30, 0.55)], (24, 26, 34, 255))
    # Crista e barra nasal douradas
    _poly(d, [(0.47, 0.15), (0.53, 0.15), (0.53, 0.68), (0.47, 0.68)],
          (222, 174, 62, 255), outline=(104, 72, 18, 255), width=2)
    _poly(d, [(0.25, 0.41), (0.75, 0.41), (0.75, 0.46), (0.25, 0.46)],
          (236, 192, 78, 255))
    _save_icon("res_pop", im)


def draw_stat_attack():
    im, d = _new_hi()
    # Espada medieval diagonal em aço e latão
    # Lâmina principal (metade clara + metade sombreada)
    _poly(d, [(0.84, 0.16), (0.72, 0.18), (0.29, 0.61), (0.39, 0.71), (0.82, 0.28)],
          (224, 232, 242, 255), outline=(45, 50, 62, 255), width=3)
    _poly(d, [(0.84, 0.16), (0.82, 0.28), (0.39, 0.71), (0.34, 0.66)], (152, 164, 182, 255))
    _line(d, [(0.36, 0.64), (0.77, 0.23)], (255, 255, 255, 210), width=4)
    # Guarda cruzada dourada
    _poly(d, [(0.22, 0.54), (0.46, 0.78), (0.40, 0.83), (0.17, 0.60)],
          (226, 176, 62, 255), outline=(92, 62, 16, 255), width=3)
    # Empunhadura couro + pomo dourado
    _line(d, [(0.31, 0.69), (0.18, 0.82)], (126, 56, 36, 255), width=14)
    _circle(d, 0.16, 0.84, 0.068, (230, 180, 66, 255), outline=(92, 62, 16, 255), width=3)
    _save_icon("stat_attack", im)


def draw_stat_armor():
    im, d = _new_hi()
    # Escudo medieval com borda dourada e umbo central
    outer = [(0.22, 0.18), (0.50, 0.14), (0.78, 0.18), (0.76, 0.52), (0.50, 0.86), (0.24, 0.52)]
    inner = [(0.29, 0.24), (0.50, 0.21), (0.71, 0.24), (0.69, 0.50), (0.50, 0.77), (0.31, 0.50)]
    _poly(d, outer, (216, 168, 56, 255), outline=(72, 48, 12, 255), width=4)
    _poly(d, inner, (76, 114, 168, 255), outline=(44, 62, 92, 255), width=2)
    # Metade sombreada + cruz metálica
    _poly(d, [(0.50, 0.21), (0.71, 0.24), (0.69, 0.50), (0.50, 0.77)], (52, 82, 128, 255))
    _poly(d, [(0.46, 0.22), (0.54, 0.22), (0.54, 0.74), (0.46, 0.74)], (210, 218, 228, 255))
    _poly(d, [(0.31, 0.42), (0.69, 0.42), (0.69, 0.50), (0.31, 0.50)], (210, 218, 228, 255))
    _circle(d, 0.50, 0.46, 0.085, (238, 194, 78, 255), outline=(88, 60, 18, 255), width=3)
    _save_icon("stat_armor", im)


def draw_stat_speed():
    im, d = _new_hi()
    # Bota alada / rastro de vento dourado
    for wy, lx in [(0.34, 0.14), (0.49, 0.10), (0.64, 0.18)]:
        _line(d, [(lx, wy), (lx + 0.24, wy)], (130, 224, 245, 255), width=10)
    # Bota medieval de couro escuro e dobra clara
    _poly(d, [(0.44, 0.22), (0.66, 0.24), (0.62, 0.58), (0.86, 0.67), (0.84, 0.79),
              (0.38, 0.79), (0.42, 0.52)],
          (148, 86, 44, 255), outline=(56, 28, 12, 255), width=4)
    _poly(d, [(0.42, 0.20), (0.68, 0.22), (0.67, 0.34), (0.43, 0.32)],
          (224, 178, 72, 255), outline=(92, 62, 16, 255), width=3)
    # Asa estilizada dourada no calcanhar
    _poly(d, [(0.40, 0.56), (0.18, 0.40), (0.28, 0.56), (0.20, 0.62), (0.38, 0.66)],
          (246, 208, 92, 255), outline=(104, 74, 18, 255), width=2)
    _save_icon("stat_speed", im)


def draw_stat_sight():
    im, d = _new_hi()
    # Olho de vigia radiante com íris azul-celeste e aro dourado
    _poly(d, [(0.12, 0.50), (0.32, 0.28), (0.50, 0.24), (0.68, 0.28), (0.88, 0.50),
              (0.68, 0.72), (0.50, 0.76), (0.32, 0.72)],
          (236, 232, 218, 255), outline=(212, 164, 58, 255), width=6)
    _circle(d, 0.50, 0.50, 0.165, (64, 152, 232, 255), outline=(28, 66, 118, 255), width=3)
    _circle(d, 0.50, 0.50, 0.085, (18, 28, 46, 255))
    _circle(d, 0.44, 0.43, 0.042, (255, 255, 255, 240))
    _save_icon("stat_sight", im)


def draw_stat_range():
    im, d = _new_hi()
    # Arco tensionado com flecha pronta
    _line(d, [(0.34, 0.16), (0.24, 0.50), (0.34, 0.84)], (216, 210, 196, 220), width=4)
    d.arc([0.14 * 256, 0.12 * 256, 0.62 * 256, 0.88 * 256], start=-72, end=72, fill=(168, 104, 48, 255), width=14)
    d.arc([0.14 * 256, 0.12 * 256, 0.62 * 256, 0.88 * 256], start=-65, end=65, fill=(212, 146, 78, 255), width=5)
    # Flecha horizontal
    _line(d, [(0.24, 0.50), (0.76, 0.50)], (218, 178, 116, 255), width=8)
    _poly(d, [(0.89, 0.50), (0.71, 0.39), (0.74, 0.50), (0.71, 0.61)], (228, 234, 244, 255), outline=(48, 54, 66, 255), width=2)
    _poly(d, [(0.24, 0.50), (0.16, 0.42), (0.28, 0.42), (0.34, 0.50), (0.28, 0.58), (0.16, 0.58)], (206, 54, 48, 255))
    _save_icon("stat_range", im)


def draw_cmd_attack_move():
    im, d = _new_hi()
    # Duas espadas cruzadas + seta carmesim para frente
    for flip in (-1, 1):
        def fx(x):
            return 0.5 + (x - 0.5) * flip
        _poly(d, [(fx(0.20), 0.72), (fx(0.74), 0.18), (fx(0.82), 0.18), (fx(0.80), 0.26), (fx(0.28), 0.78)],
              (216, 224, 236, 255), outline=(46, 50, 62, 255), width=3)
        _line(d, [(fx(0.16), 0.62), (fx(0.36), 0.82)], (212, 162, 54, 255), width=10)
    # Ponta vermelha tática embaixo
    _poly(d, [(0.50, 0.62), (0.64, 0.80), (0.55, 0.80), (0.55, 0.88), (0.45, 0.88), (0.45, 0.80), (0.36, 0.80)],
          (232, 66, 56, 255), outline=(88, 18, 18, 255), width=3)
    _save_icon("cmd_attack_move", im)


def draw_cmd_stop():
    im, d = _new_hi()
    # Escudo octogonal com palma / marca de parada em bronze e carmesim
    pts = []
    for k in range(8):
        a = math.radians(22.5 + k * 45.0)
        pts.append((0.50 + math.cos(a) * 0.35, 0.50 + math.sin(a) * 0.35))
    _poly(d, pts, (168, 44, 44, 255), outline=(228, 182, 72, 255), width=6)
    _poly(d, [(0.34, 0.34), (0.66, 0.34), (0.66, 0.66), (0.34, 0.66)],
          (240, 226, 190, 255), outline=(92, 24, 24, 255), width=3)
    _save_icon("cmd_stop", im)


def draw_cmd_gather():
    im, d = _new_hi()
    # Picareta cruzada em aço e madeira
    _line(d, [(0.22, 0.78), (0.74, 0.26)], (152, 92, 42, 255), width=13)
    _poly(d, [(0.36, 0.16), (0.58, 0.20), (0.82, 0.42), (0.84, 0.64),
              (0.73, 0.46), (0.62, 0.34), (0.42, 0.25)],
          (198, 208, 222, 255), outline=(44, 48, 58, 255), width=3)
    _circle(d, 0.68, 0.32, 0.055, (220, 174, 62, 255), outline=(72, 48, 16, 255), width=2)
    _save_icon("cmd_gather", im)


def draw_cmd_follow():
    im, d = _new_hi()
    # Bússola/retículo dourado real
    _circle(d, 0.50, 0.50, 0.32, (36, 54, 78, 180), outline=(232, 186, 72, 255), width=8)
    _circle(d, 0.50, 0.50, 0.11, (96, 198, 248, 255), outline=(255, 244, 196, 255), width=4)
    for dx, dy in [(0, -1), (0, 1), (-1, 0), (1, 0)]:
        _line(d, [(0.50 + dx * 0.18, 0.50 + dy * 0.18), (0.50 + dx * 0.42, 0.50 + dy * 0.42)],
              (246, 206, 94, 255), width=9)
    _save_icon("cmd_follow", im)


def draw_cmd_cancel():
    im, d = _new_hi()
    _circle(d, 0.50, 0.50, 0.34, (78, 24, 26, 240), outline=(210, 74, 62, 255), width=6)
    _line(d, [(0.32, 0.32), (0.68, 0.68)], (245, 92, 82, 255), width=18)
    _line(d, [(0.68, 0.32), (0.32, 0.68)], (245, 92, 82, 255), width=18)
    _save_icon("cmd_cancel", im)


def draw_tab_eco():
    im, d = _new_hi()
    # Martelo de construtor dourado + folha verde
    _line(d, [(0.24, 0.78), (0.64, 0.38)], (162, 98, 44, 255), width=13)
    _poly(d, [(0.42, 0.24), (0.62, 0.16), (0.82, 0.36), (0.62, 0.44)],
          (232, 188, 72, 255), outline=(88, 56, 14, 255), width=3)
    _poly(d, [(0.56, 0.68), (0.72, 0.48), (0.84, 0.60), (0.68, 0.80)],
          (106, 198, 92, 255), outline=(34, 74, 28, 255), width=3)
    _save_icon("tab_eco", im)


def draw_tab_mil():
    im, d = _new_hi()
    # Espada por trás de um pequeno escudo de aço/carmesim
    _poly(d, [(0.78, 0.16), (0.84, 0.22), (0.28, 0.78), (0.22, 0.72)],
          (218, 226, 238, 255), outline=(44, 48, 58, 255), width=3)
    _line(d, [(0.20, 0.56), (0.44, 0.80)], (220, 174, 62, 255), width=9)
    outer = [(0.34, 0.34), (0.56, 0.30), (0.78, 0.34), (0.76, 0.62), (0.56, 0.86), (0.36, 0.62)]
    _poly(d, outer, (176, 44, 44, 255), outline=(228, 186, 78, 255), width=5)
    _poly(d, [(0.56, 0.30), (0.78, 0.34), (0.76, 0.62), (0.56, 0.86)], (128, 30, 32, 255))
    _save_icon("tab_mil", im)


def draw_market_buy():
    im, d = _new_hi()
    # Seta verde esmeralda apontando para baixo (entrar recurso) + moeda
    _poly(d, [(0.42, 0.16), (0.58, 0.16), (0.58, 0.46), (0.74, 0.46),
              (0.50, 0.76), (0.26, 0.46), (0.42, 0.46)],
          (86, 212, 118, 255), outline=(24, 78, 36, 255), width=4)
    _circle(d, 0.72, 0.74, 0.14, (245, 198, 62, 255), outline=(112, 74, 14, 255), width=3)
    _save_icon("market_buy", im)


def draw_market_sell():
    im, d = _new_hi()
    # Seta âmbar-ouro apontando para cima (vender por ouro) + moeda
    _poly(d, [(0.50, 0.16), (0.74, 0.46), (0.58, 0.46), (0.58, 0.78),
              (0.42, 0.78), (0.42, 0.46), (0.26, 0.46)],
          (246, 186, 62, 255), outline=(104, 62, 12, 255), width=4)
    _circle(d, 0.72, 0.74, 0.14, (245, 210, 82, 255), outline=(112, 74, 14, 255), width=3)
    _save_icon("market_sell", im)


def draw_emblem_crown():
    s = 512.0
    im, d = _new_hi(512)
    # Brasão em forma de escudo + Coroa de Ferro forjada + gema azul real
    shield = [(0.16, 0.18), (0.50, 0.12), (0.84, 0.18), (0.81, 0.62), (0.50, 0.90), (0.19, 0.62)]
    _poly(d, shield, (28, 34, 46, 255), outline=(218, 174, 72, 255), width=10, s=s)
    # Faixa radial diagonal azul real
    _poly(d, [(0.22, 0.22), (0.50, 0.16), (0.78, 0.22), (0.75, 0.59), (0.50, 0.83), (0.25, 0.59)],
          (34, 64, 118, 255), s=s)
    _poly(d, [(0.50, 0.16), (0.78, 0.22), (0.75, 0.59), (0.50, 0.83)],
          (24, 46, 88, 255), s=s)
    # Coroa de Ferro estilizada central
    crown = [
        (0.26, 0.60), (0.24, 0.34), (0.37, 0.46), (0.50, 0.24),
        (0.63, 0.46), (0.76, 0.34), (0.74, 0.60),
    ]
    _poly(d, crown, (148, 156, 172, 255), outline=(232, 190, 82, 255), width=6, s=s)
    # Sombreamento direito da coroa
    _poly(d, [(0.50, 0.24), (0.63, 0.46), (0.76, 0.34), (0.74, 0.60), (0.50, 0.60)],
          (102, 110, 126, 255), s=s)
    # Aro inferior da coroa em ferro & ouro
    _poly(d, [(0.25, 0.56), (0.75, 0.56), (0.75, 0.64), (0.25, 0.64)],
          (224, 178, 64, 255), outline=(88, 62, 16, 255), width=4, s=s)
    # Três pontas e safira central
    for px, py, r in [(0.24, 0.33, 0.032), (0.50, 0.22, 0.040), (0.76, 0.33, 0.032)]:
        _circle(d, px, py, r, (246, 206, 86, 255), outline=(92, 62, 18, 255), width=3, s=s)
    _circle(d, 0.50, 0.48, 0.055, (72, 168, 255, 255), outline=(242, 212, 108, 255), width=4, s=s)
    _circle(d, 0.48, 0.46, 0.018, (220, 245, 255, 240), s=s)
    _save_icon("emblem_crown", im, target=128, outline_r=8)


def draw_ui_idle_worker():
    im, d = _new_hi()
    # Sino da vila em latão polido (alerta clássico de camponês ocioso)
    _poly(d, [(0.36, 0.22), (0.64, 0.22), (0.74, 0.64), (0.82, 0.72),
              (0.18, 0.72), (0.26, 0.64)],
          (236, 184, 58, 255), outline=(92, 58, 14, 255), width=4)
    _poly(d, [(0.50, 0.22), (0.64, 0.22), (0.74, 0.64), (0.82, 0.72), (0.50, 0.72)],
          (188, 136, 36, 255))
    _circle(d, 0.50, 0.19, 0.06, (218, 170, 56, 255), outline=(88, 56, 14, 255), width=3)
    _circle(d, 0.50, 0.76, 0.075, (186, 138, 42, 255), outline=(72, 46, 12, 255), width=3)
    _save_icon("ui_idle_worker", im)


def draw_ui_base():
    im, d = _new_hi()
    # Torre de menagem / Salão Real estilizado
    _poly(d, [(0.26, 0.34), (0.74, 0.34), (0.78, 0.84), (0.22, 0.84)],
          (186, 192, 204, 255), outline=(48, 52, 62, 255), width=4)
    # Ameias
    for bx in (0.24, 0.42, 0.60):
        _poly(d, [(bx, 0.20), (bx + 0.14, 0.20), (bx + 0.14, 0.34), (bx, 0.34)],
              (212, 216, 226, 255), outline=(48, 52, 62, 255), width=3)
    # Portão arqueado e bandeira azul
    _poly(d, [(0.42, 0.56), (0.58, 0.56), (0.58, 0.84), (0.42, 0.84)], (54, 42, 32, 255))
    _circle(d, 0.50, 0.56, 0.08, (54, 42, 32, 255))
    _line(d, [(0.50, 0.08), (0.50, 0.22)], (228, 184, 72, 255), width=5)
    _poly(d, [(0.51, 0.09), (0.74, 0.14), (0.51, 0.20)], (64, 146, 245, 255))
    _save_icon("ui_base", im)


def draw_ui_alert():
    im, d = _new_hi()
    # Trompa / Olifante de guerra em latão com onda sonora
    _poly(d, [(0.16, 0.68), (0.48, 0.44), (0.68, 0.22), (0.80, 0.52), (0.52, 0.62), (0.22, 0.78)],
          (232, 182, 56, 255), outline=(92, 58, 14, 255), width=4)
    d.ellipse([0.64 * 256, 0.22 * 256, 0.82 * 256, 0.52 * 256],
              fill=(136, 78, 22, 255), outline=(248, 212, 98, 255), width=4)
    d.arc([0.66 * 256, 0.22 * 256, 0.92 * 256, 0.54 * 256], start=-45, end=45, fill=(255, 196, 86, 240), width=7)
    _save_icon("ui_alert", im)


def draw_ui_sound(muted: bool):
    im, d = _new_hi()
    col = (182, 188, 198, 255) if not muted else (142, 146, 156, 255)
    _poly(d, [(0.18, 0.38), (0.34, 0.38), (0.56, 0.20), (0.56, 0.80), (0.34, 0.62), (0.18, 0.62)],
          col, outline=(42, 46, 56, 255), width=4)
    if not muted:
        d.arc([0.52 * 256, 0.30 * 256, 0.72 * 256, 0.70 * 256], start=-55, end=55, fill=(236, 194, 78, 255), width=8)
        d.arc([0.54 * 256, 0.18 * 256, 0.86 * 256, 0.82 * 256], start=-55, end=55, fill=(236, 194, 78, 230), width=8)
    else:
        _line(d, [(0.62, 0.34), (0.84, 0.66)], (232, 68, 62, 255), width=12)
        _line(d, [(0.84, 0.34), (0.62, 0.66)], (232, 68, 62, 255), width=12)
    _save_icon("ui_sound_off" if muted else "ui_sound_on", im)


def draw_ui_edge_pan():
    im, d = _new_hi()
    # Rosa dos ventos / setas de câmera em 4 direções
    for ang_deg in (0, 90, 180, 270):
        rad = math.radians(ang_deg)
        vx, vy = math.cos(rad), math.sin(rad)
        px, py = -vy, vx
        tip = (0.50 + vx * 0.38, 0.50 + vy * 0.38)
        b1 = (0.50 + vx * 0.16 + px * 0.13, 0.50 + vy * 0.16 + py * 0.13)
        b2 = (0.50 + vx * 0.16 - px * 0.13, 0.50 + vy * 0.16 - py * 0.13)
        _poly(d, [tip, b1, (0.50 + vx * 0.12, 0.50 + vy * 0.12), b2],
              (232, 188, 76, 255), outline=(88, 60, 16, 255), width=2)
    _circle(d, 0.50, 0.50, 0.10, (198, 210, 226, 255), outline=(54, 62, 76, 255), width=3)
    _save_icon("ui_edge_pan", im)


def draw_ui_pause():
    im, d = _new_hi()
    _poly(d, [(0.26, 0.22), (0.43, 0.22), (0.43, 0.78), (0.26, 0.78)],
          (232, 186, 72, 255), outline=(88, 58, 14, 255), width=4)
    _poly(d, [(0.57, 0.22), (0.74, 0.22), (0.74, 0.78), (0.57, 0.78)],
          (232, 186, 72, 255), outline=(88, 58, 14, 255), width=4)
    _save_icon("ui_pause", im)


def draw_ui_help():
    im, d = _new_hi()
    # Pergaminho com ?
    _poly(d, [(0.24, 0.18), (0.76, 0.18), (0.76, 0.82), (0.24, 0.82)],
          (228, 210, 168, 255), outline=(122, 86, 42, 255), width=5)
    d.arc([0.36 * 256, 0.26 * 256, 0.64 * 256, 0.54 * 256], start=-165, end=70, fill=(142, 46, 36, 255), width=14)
    _line(d, [(0.58, 0.46), (0.50, 0.56), (0.50, 0.62)], (142, 46, 36, 255), width=14)
    _circle(d, 0.50, 0.72, 0.042, (142, 46, 36, 255))
    _save_icon("ui_help", im)


def draw_phase_peace():
    im, d = _new_hi()
    outer = [(0.22, 0.20), (0.50, 0.15), (0.78, 0.20), (0.76, 0.54), (0.50, 0.85), (0.24, 0.54)]
    _poly(d, outer, (68, 158, 102, 255), outline=(216, 224, 232, 255), width=6)
    _line(d, [(0.34, 0.52), (0.45, 0.64), (0.68, 0.36)], (245, 238, 198, 255), width=14)
    _save_icon("phase_peace", im)


def draw_phase_war():
    im, d = _new_hi()
    for flip in (-1, 1):
        def fx(x):
            return 0.5 + (x - 0.5) * flip
        _poly(d, [(fx(0.18), 0.76), (fx(0.76), 0.16), (fx(0.84), 0.16), (fx(0.82), 0.25), (fx(0.26), 0.82)],
              (238, 92, 76, 255), outline=(88, 18, 18, 255), width=3)
        _line(d, [(fx(0.16), 0.62), (fx(0.36), 0.82)], (232, 184, 68, 255), width=11)
    _save_icon("phase_war", im)


def draw_obj_badges():
    # Concluído: selo esmeralda com V
    im, d = _new_hi()
    _circle(d, 0.50, 0.50, 0.34, (64, 178, 92, 255), outline=(218, 245, 212, 255), width=6)
    _line(d, [(0.32, 0.52), (0.44, 0.66), (0.70, 0.34)], (255, 255, 255, 255), width=16)
    _save_icon("obj_done", im)

    # Pendente: losango dourado medieval
    im, d = _new_hi()
    _poly(d, [(0.50, 0.16), (0.84, 0.50), (0.50, 0.84), (0.16, 0.50)],
          (218, 172, 64, 255), outline=(88, 60, 14, 255), width=5)
    _poly(d, [(0.50, 0.30), (0.70, 0.50), (0.50, 0.70), (0.30, 0.50)], (42, 46, 56, 255))
    _save_icon("obj_todo", im)

    # Alerta: losango carmesim com !
    im, d = _new_hi()
    _poly(d, [(0.50, 0.16), (0.84, 0.50), (0.50, 0.84), (0.16, 0.50)],
          (218, 62, 52, 255), outline=(255, 198, 120, 255), width=5)
    _line(d, [(0.50, 0.32), (0.50, 0.56)], (255, 245, 228, 255), width=14)
    _circle(d, 0.50, 0.69, 0.045, (255, 245, 228, 255))
    _save_icon("obj_warn", im)


# ==============================================================================
# GERADOR DE CHROME 9-SLICE METÁLICO E FORJADO (NP + PIL)
# ==============================================================================

def _brushed_metal_rgba(w: int, h: int, top_rgb, bot_rgb, grain_amp: float = 4.5, alpha: int = 242, seed: int = 11):
    rng = np.random.default_rng(seed)
    yy = np.linspace(0.0, 1.0, h, dtype=np.float32)[:, None]
    base = np.zeros((h, w, 4), dtype=np.float32)
    for c in range(3):
        base[..., c] = top_rgb[c] * (1.0 - yy) + bot_rgb[c] * yy
    # Microtextura horizontal escovada + ruído sutil
    row_noise = rng.normal(0.0, grain_amp * 0.65, size=(h, 1, 1)).astype(np.float32)
    px_noise = rng.normal(0.0, grain_amp * 0.55, size=(h, w, 1)).astype(np.float32)
    base[..., :3] = np.clip(base[..., :3] + row_noise + px_noise, 0.0, 255.0)
    base[..., 3] = float(alpha)
    return base


def _rounded_mask(w: int, h: int, r: int) -> np.ndarray:
    m = Image.new("L", (w, h), 0)
    md = ImageDraw.Draw(m)
    md.rounded_rectangle([0, 0, w - 1, h - 1], radius=r, fill=255)
    return np.asarray(m, dtype=np.float32) / 255.0


def _draw_rivet(d: ImageDraw.ImageDraw, cx: float, cy: float, r: float = 3.2):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(168, 132, 54, 255), outline=(42, 30, 12, 255), width=1)
    d.ellipse([cx - r * 0.45, cy - r * 0.45, cx + r * 0.15, cy + r * 0.15], fill=(242, 214, 128, 220))


def make_ornate_panel(name: str, w: int, h: int, top_rgb, bot_rgb, gold_outer, gold_inner,
                      alpha: int = 244, corner_r: int = 10, rivets: bool = True, inset: int = 7, seed: int = 10):
    arr = _brushed_metal_rgba(w, h, top_rgb, bot_rgb, grain_amp=4.0, alpha=alpha, seed=seed)
    mask = _rounded_mask(w, h, corner_r)
    arr[..., 3] *= mask
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGBA")
    d = ImageDraw.Draw(im)

    # Sombra interna sutil no contorno externo + borda de latão envelhecido
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=corner_r, outline=(8, 10, 14, 255), width=2)
    d.rounded_rectangle([2, 2, w - 3, h - 3], radius=max(2, corner_r - 2), outline=gold_outer, width=2)
    d.rounded_rectangle([inset, inset, w - 1 - inset, h - 1 - inset],
                        radius=max(2, corner_r - 4), outline=gold_inner, width=1)

    if rivets:
        off = 11
        for rx, ry in [(off, off), (w - 1 - off, off), (off, h - 1 - off), (w - 1 - off, h - 1 - off)]:
            _draw_rivet(d, rx, ry, r=3.2)

    im.save(os.path.join(CHROME_DIR, f"{name}.png"))


def make_topbar_chrome():
    w, h = 128, 48
    arr = _brushed_metal_rgba(w, h, (26, 31, 43), (14, 17, 25), grain_amp=3.5, alpha=245, seed=31)
    # Brilho metálico na parte superior
    arr[:4, :, :3] = np.clip(arr[:4, :, :3] + 18.0, 0, 255)
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGBA")
    d = ImageDraw.Draw(im)
    d.line([(0, 0), (w - 1, 0)], fill=(128, 102, 48, 190), width=1)
    d.line([(0, h - 4), (w - 1, h - 4)], fill=(116, 88, 34, 210), width=1)
    d.line([(0, h - 3), (w - 1, h - 3)], fill=(208, 168, 76, 245), width=2)
    d.line([(0, h - 1), (w - 1, h - 1)], fill=(6, 7, 10, 255), width=1)
    im.save(os.path.join(CHROME_DIR, "panel_topbar.png"))


def make_banner_chrome():
    w, h = 256, 48
    arr = _brushed_metal_rgba(w, h, (28, 31, 42), (16, 18, 26), grain_amp=3.0, alpha=232, seed=41)
    # Fade elegante nas bordas esquerda/direita
    xx = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :]
    edge = np.clip(np.minimum(xx / 0.14, (1.0 - xx) / 0.14), 0.0, 1.0)
    arr[..., 3] *= edge
    im = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGBA")
    d = ImageDraw.Draw(im)
    # Filetes dourados afinando nas extremidades
    for x in range(w):
        t = min(x / 36.0, (w - 1 - x) / 36.0, 1.0)
        a_g = int(230 * t)
        d.point((x, 2), fill=(214, 174, 82, a_g))
        d.point((x, h - 3), fill=(214, 174, 82, a_g))
    im.save(os.path.join(CHROME_DIR, "panel_banner.png"))


def make_bar_chrome():
    w, h = 64, 20
    # Track escavado
    arr = _brushed_metal_rgba(w, h, (11, 13, 18), (20, 23, 30), grain_amp=2.0, alpha=245, seed=51)
    arr[..., 3] *= _rounded_mask(w, h, 5)
    tr = Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), mode="RGBA")
    d = ImageDraw.Draw(tr)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=5, outline=(72, 62, 40, 220), width=1)
    tr.save(os.path.join(CHROME_DIR, "bar_track.png"))

    fills = {
        "bar_fill_ally": ((82, 214, 140), (34, 132, 74)),
        "bar_fill_warn": ((248, 198, 72), (186, 114, 24)),
        "bar_fill_enemy": ((242, 86, 76), (166, 36, 34)),
        "bar_fill_queue": ((92, 188, 248), (38, 108, 182)),
        "bar_fill_resource": ((240, 184, 64), (168, 112, 24)),
    }
    for name, (top_c, bot_c) in fills.items():
        fa = _brushed_metal_rgba(w, h, top_c, bot_c, grain_amp=1.5, alpha=250, seed=55)
        # Brilho especular na faixa superior
        fa[2:5, :, :3] = np.clip(fa[2:5, :, :3] + 38.0, 0, 255)
        fa[..., 3] *= _rounded_mask(w, h, 4)
        fim = Image.fromarray(np.clip(fa, 0, 255).astype(np.uint8), mode="RGBA")
        ImageDraw.Draw(fim).rounded_rectangle([0, 0, w - 1, h - 1], radius=4, outline=(255, 255, 255, 65), width=1)
        fim.save(os.path.join(CHROME_DIR, f"{name}.png"))


def make_divider_gold():
    w, h = 256, 14
    im = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    cy = h // 2
    for x in range(8, w - 8):
        dx = abs(x - w * 0.5) / (w * 0.5 - 8)
        a = int(235 * (1.0 - dx ** 1.6))
        d.line([(x, cy), (x, cy)], fill=(214, 174, 80, a))
        if dx < 0.72:
            d.line([(x, cy - 1), (x, cy - 1)], fill=(244, 212, 128, int(a * 0.55)))
    # Losango central forjado
    mx = w // 2
    d.polygon([(mx, 2), (mx + 9, cy), (mx, h - 2), (mx - 9, cy)],
              fill=(232, 192, 86, 255), outline=(88, 60, 16, 255))
    im.save(os.path.join(CHROME_DIR, "divider_gold.png"))


def generate_all_chrome():
    # Painéis principais
    make_ornate_panel("panel_ornate", 128, 128, (27, 32, 44), (14, 17, 25),
                      (196, 156, 68, 240), (112, 86, 36, 150), alpha=245, corner_r=10, rivets=True, inset=7, seed=11)
    make_ornate_panel("panel_subtle", 96, 96, (21, 25, 34), (13, 16, 22),
                      (156, 124, 58, 195), (90, 72, 34, 90), alpha=216, corner_r=8, rivets=False, inset=5, seed=12)
    make_ornate_panel("minimap_frame", 128, 128, (32, 36, 48), (16, 19, 27),
                      (212, 170, 74, 250), (128, 96, 40, 190), alpha=250, corner_r=10, rivets=True, inset=7, seed=13)
    make_ornate_panel("portrait_frame", 128, 128, (20, 23, 32), (10, 12, 18),
                      (208, 168, 72, 245), (108, 84, 34, 180), alpha=250, corner_r=8, rivets=True, inset=5, seed=14)

    # Slots / Botões do cartão de comandos
    make_ornate_panel("slot_normal", 96, 96, (34, 41, 56), (20, 24, 34),
                      (154, 124, 58, 225), (72, 82, 102, 95), alpha=246, corner_r=7, rivets=False, inset=4, seed=21)
    make_ornate_panel("slot_hover", 96, 96, (54, 62, 82), (32, 37, 50),
                      (238, 196, 92, 255), (186, 148, 64, 175), alpha=252, corner_r=7, rivets=False, inset=4, seed=22)
    make_ornate_panel("slot_pressed", 96, 96, (20, 24, 33), (28, 34, 46),
                      (255, 222, 118, 255), (204, 166, 76, 200), alpha=252, corner_r=7, rivets=False, inset=4, seed=23)
    make_ornate_panel("slot_disabled", 96, 96, (32, 24, 28), (22, 17, 21),
                      (128, 68, 62, 195), (78, 42, 38, 110), alpha=232, corner_r=7, rivets=False, inset=4, seed=24)

    # Pílulas, keycap, abas e CTAs
    make_ornate_panel("pill_bg", 64, 36, (15, 18, 25), (22, 26, 36),
                      (124, 98, 46, 205), (54, 62, 78, 90), alpha=238, corner_r=7, rivets=False, inset=3, seed=25)
    make_ornate_panel("keycap_bg", 32, 32, (46, 40, 28), (26, 22, 15),
                      (196, 158, 68, 240), (96, 76, 32, 140), alpha=248, corner_r=4, rivets=False, inset=3, seed=26)
    make_ornate_panel("tab_active", 96, 36, (56, 50, 36), (34, 32, 28),
                      (232, 190, 84, 255), (156, 122, 48, 160), alpha=250, corner_r=6, rivets=False, inset=3, seed=27)
    make_ornate_panel("tab_inactive", 96, 36, (24, 28, 38), (16, 19, 27),
                      (112, 92, 48, 185), (56, 62, 74, 80), alpha=228, corner_r=6, rivets=False, inset=3, seed=28)

    # CTAs primário (esmeralda real) e perigo (carmesim)
    make_ornate_panel("btn_primary_normal", 128, 48, (36, 78, 52), (22, 50, 34),
                      (224, 182, 78, 250), (144, 116, 46, 140), alpha=250, corner_r=8, rivets=True, inset=4, seed=31)
    make_ornate_panel("btn_primary_hover", 128, 48, (48, 102, 68), (30, 68, 45),
                      (252, 214, 104, 255), (192, 158, 66, 190), alpha=255, corner_r=8, rivets=True, inset=4, seed=32)
    make_ornate_panel("btn_danger_normal", 128, 48, (86, 32, 34), (56, 20, 22),
                      (202, 96, 76, 240), (126, 56, 44, 140), alpha=248, corner_r=8, rivets=True, inset=4, seed=33)
    make_ornate_panel("btn_danger_hover", 128, 48, (112, 42, 44), (74, 26, 28),
                      (242, 134, 102, 255), (176, 84, 64, 180), alpha=255, corner_r=8, rivets=True, inset=4, seed=34)

    make_topbar_chrome()
    make_banner_chrome()
    make_bar_chrome()
    make_divider_gold()


def main():
    draw_res_food()
    draw_res_wood()
    draw_res_gold()
    draw_res_stone()
    draw_res_pop()

    draw_stat_attack()
    draw_stat_armor()
    draw_stat_speed()
    draw_stat_sight()
    draw_stat_range()

    draw_cmd_attack_move()
    draw_cmd_stop()
    draw_cmd_gather()
    draw_cmd_follow()
    draw_cmd_cancel()
    draw_tab_eco()
    draw_tab_mil()
    draw_market_buy()
    draw_market_sell()

    draw_emblem_crown()
    draw_ui_idle_worker()
    draw_ui_base()
    draw_ui_alert()
    draw_ui_sound(False)
    draw_ui_sound(True)
    draw_ui_edge_pan()
    draw_ui_pause()
    draw_ui_help()
    draw_phase_peace()
    draw_phase_war()
    draw_obj_badges()

    generate_all_chrome()

    n_icons = len([f for f in os.listdir(ICONS_DIR) if f.endswith(".png")])
    n_chrome = len([f for f in os.listdir(CHROME_DIR) if f.endswith(".png")])
    print(f"[HUDAssets] Generated {n_icons} icons and {n_chrome} chrome textures.")


if __name__ == "__main__":
    main()
