"""Gera o ícone do Velksync: Keycaps da marca Velk, com a tecla de baixo em menta.

Uso (precisa do resvg-py e do pillow; com uv não instala nada no sistema):
    uv run --no-project --with resvg-py --with pillow python tools/icon/generate.py
        (Android, iOS, bandeja do Linux, .ico e BMPs do Windows e imagens de docs/)

Depois, para o ícone do .exe, regenerar o agent/rsrc_windows_amd64.syso com o go-winres.
"""
import io
import json
from pathlib import Path

import resvg_py
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
INK, PAPER, MENTA = "#1b1a1e", "#f6f4f1", "#a8e0b7"
# Cantos superiores esquerdos das teclas num quadro de 48; a do meio é a de baixo.
KEYS = [(0.2, 10.0), (10.0, 19.8), (19.8, 29.6), (29.6, 19.8), (39.4, 10.0)]
SCALE = 1.08  # quadro de 48 dentro do miolo 72x72 do ícone adaptativo (canvas 108)


def layers():
    """(x, y, lado_x, lado_y, raio, cor, opacidade) no canvas de 108."""
    for i, (x, y) in enumerate(KEYS):
        color = MENTA if i == 2 else PAPER
        for dx, dy, w, h, r, alpha in ((0, 0, 8.4, 8.4, 2.3, 0.5), (1.3, 0.8, 5.8, 5.4, 1.5, 1.0)):
            yield (54 + (x + dx - 24) * SCALE, 54 + (y + dy - 24) * SCALE,
                   w * SCALE, h * SCALE, r * SCALE, color, alpha)


def keys_svg():
    return "".join(f'<rect x="{x:.2f}" y="{y:.2f}" width="{w:.2f}" height="{h:.2f}" rx="{r:.2f}" '
                   f'fill="{c}" fill-opacity="{a}"/>' for x, y, w, h, r, c, a in layers())


def render(svg, width, height, viewbox):
    doc = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
           f'viewBox="{viewbox}">{svg}</svg>')
    return Image.open(io.BytesIO(bytes(resvg_py.svg_to_bytes(svg_string=doc)))).convert("RGBA")


def tile(size, radius=17):
    """Miolo 72x72 do ícone adaptativo; radius=0 para o iOS, que recorta sozinho."""
    body = f'<rect x="18" y="18" width="72" height="72" rx="{radius}" fill="{INK}"/>' + keys_svg()
    return render(body, size, size, "18 18 72 72")


def vector(paths):
    return ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
            '    android:width="108dp" android:height="108dp"\n'
            '    android:viewportWidth="108" android:viewportHeight="108">\n' + "".join(paths) + "</vector>\n")


def path(d, color, alpha=1.0):
    return (f'    <path android:pathData="{d}"\n        android:fillColor="{color}" '
            f'android:fillAlpha="{alpha}"/>\n')


def rounded(x, y, w, h, r):
    return (f"M{x + r:.2f},{y:.2f}h{w - 2 * r:.2f}q{r:.2f},0 {r:.2f},{r:.2f}v{h - 2 * r:.2f}"
            f"q0,{r:.2f} {-r:.2f},{r:.2f}h{-(w - 2 * r):.2f}q{-r:.2f},0 {-r:.2f},{-r:.2f}"
            f"v{-(h - 2 * r):.2f}q0,{-r:.2f} {r:.2f},{-r:.2f}z")


def android():
    res = ROOT / "app/android/app/src/main/res"
    drawables = {
        "background": [path("M0,0h108v108h-108z", INK)],
        "foreground": [path(rounded(x, y, w, h, r), c, a) for x, y, w, h, r, c, a in layers()],
        "monochrome": [path(rounded(x, y, w, h, r), "#FFFFFF", a) for x, y, w, h, r, _, a in layers()],
    }
    for name, paths in drawables.items():
        (res / f"drawable/ic_launcher_{name}.xml").write_text(vector(paths))
    for folder, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
        tile(px).save(res / f"mipmap-{folder}/ic_launcher.png")


def ios():
    folder = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    for image in json.loads((folder / "Contents.json").read_text())["images"]:
        points = float(image["size"].split("x")[0])
        px = round(points * int(image["scale"].rstrip("x")))
        tile(px, radius=0).convert("RGB").save(folder / image["filename"])


def windows_and_linux():
    out = ROOT / "agent/deploy/installer"
    tile(256).save(ROOT / "agent/deploy/tray-icon.png")
    tile(256).save(out / "velksync.ico", sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    # O Inno Setup escolhe a imagem pela escala da tela; BMP sem transparência.
    for scale in (1, 2):
        n = 55 * scale
        small = Image.new("RGB", (n, n), "white")
        icon = tile(n)
        small.paste(icon, (0, 0), icon)
        small.save(out / f"small-{scale}x.bmp")
        side = render(
            f'<rect width="164" height="314" fill="{INK}"/>'
            f'<svg x="32" y="92" width="100" height="100" viewBox="18 18 72 72">{keys_svg()}</svg>'
            f'<text x="82" y="228" text-anchor="middle" font-family="Ubuntu, DejaVu Sans" font-weight="700" '
            f'font-size="22" fill="{PAPER}">Velksync</text>', 164 * scale, 314 * scale, "0 0 164 314")
        side.convert("RGB").save(out / f"side-{scale}x.bmp")


def docs():
    out = ROOT / "docs"
    tile(256).save(out / "icon.png")
    # Prévia de link do GitHub (Settings → Social preview): 1280x640.
    font = 'font-family="Ubuntu, DejaVu Sans"'
    render(
        f'<rect width="1280" height="640" fill="{INK}"/>'
        f'<svg x="130" y="170" width="300" height="300" viewBox="18 18 72 72">{keys_svg()}</svg>'
        f'<text x="500" y="315" {font} font-weight="700" font-size="104" fill="{PAPER}">Velksync</text>'
        f'<text x="504" y="385" {font} font-size="32" fill="{MENTA}">Ligue, desligue e controle o PC pelo celular</text>'
        f'<text x="504" y="440" {font} font-size="30" fill="{PAPER}" fill-opacity="0.6">'
        "Windows e Linux · rede local · código aberto</text>",
        1280, 640, "0 0 1280 640").save(out / "social-preview.png")


if __name__ == "__main__":
    android()
    ios()
    windows_and_linux()
    docs()
