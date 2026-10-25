"""Gera o ícone do Velksync (asas de gelo em V, inspiradas na Velkhana).

Uso (precisa do resvg-py; com uv não instala nada no sistema):
    uv run --no-project --with resvg-py python tools/icon/generate.py android app/android/app/src/main/res preview.png
    uv run --no-project --with resvg-py python tools/icon/generate.py sheet variacoes.png


Canvas do ícone adaptativo: 108x108; o launcher mostra o miolo 72x72 (18..90)
e o conteúdo deve caber no círculo de raio 33 (área segura).
"""
import math
import sys

import resvg_py

NAVY_A, NAVY_B = "#16345F", "#060F22"
ICE_HI, ICE_MID, ICE_LO = "#F2FBFF", "#A8DDFF", "#4BA8E8"
GLOW = "#7FE3FF"

WING = [(54, 82), (22, 30), (33, 35), (34, 24), (43, 37), (46, 27), (54, 50)]


def fit(points, radius=33.0):
    """Escala e move as asas para o centro (54,54) cabendo no raio da área segura."""
    allp = points + [(108 - x, y) for x, y in points]
    xs, ys = [p[0] for p in allp], [p[1] for p in allp]
    cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
    far = max(math.hypot(x - cx, y - cy) for x, y in allp)
    s = radius / far
    return lambda x, y: (54 + (x - cx) * s, 54 + (y - cy) * s), s


def design(v):
    """v: dict com dot, radius, ice (cores), bg (cores)."""
    t, s = fit(WING, v.get("radius", 26.0))
    wing = "M" + " L".join(f"{t(x, y)[0]:.2f},{t(x, y)[1]:.2f}" for x, y in WING) + " Z"
    mirror = "M" + " L".join(f"{108 - t(x, y)[0]:.2f},{t(x, y)[1]:.2f}" for x, y in WING) + " Z"
    hi, mid, lo = v.get("ice", (ICE_HI, ICE_MID, ICE_LO))
    a, b = v.get("bg", (NAVY_A, NAVY_B))
    sw = 1.2 * s / 0.84
    body = (f'<defs><linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1"><stop offset="0" stop-color="{a}"/>'
            f'<stop offset="1" stop-color="{b}"/></linearGradient>'
            f'<linearGradient id="ice" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{hi}"/>'
            f'<stop offset="0.55" stop-color="{mid}"/><stop offset="1" stop-color="{lo}"/></linearGradient></defs>'
            f'<rect width="108" height="108" fill="url(#bg)"/>'
            f'<path d="{wing}" fill="url(#ice)" stroke="{hi}" stroke-width="{sw:.2f}" stroke-linejoin="round"/>'
            f'<path d="{mirror}" fill="url(#ice)" stroke="{hi}" stroke-width="{sw:.2f}" stroke-linejoin="round"/>')
    if v.get("dot", True):
        dx, dy = t(54, 30)
        body += f'<circle cx="{dx:.2f}" cy="{dy:.2f}" r="{4 * s:.2f}" fill="{GLOW}"/>'
    return body


VARIANTS = {
    "a": {},                                              # como a 5, sem brilho e centralizada
    "b": {"dot": False},                                  # sem o ponto
    "c": {"bg": ("#0E2547", "#0E2547")},                  # fundo liso
    "d": {"ice": ("#FFFFFF", "#CBEBFF", "#7CC4F2")},      # gelo mais claro
}


def tile(body, x, y, size, shape, uid):
    clip = ('<rect x="18" y="18" width="72" height="72" rx="17"/>' if shape == "square"
            else '<circle cx="54" cy="54" r="36"/>')
    body = body.replace('id="bg"', f'id="bg{uid}"').replace("url(#bg)", f"url(#bg{uid})")
    body = body.replace('id="ice"', f'id="ice{uid}"').replace("url(#ice)", f"url(#ice{uid})")
    return (f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="18 18 72 72">'
            f'<defs><clipPath id="k{uid}">{clip}</clipPath></defs><g clip-path="url(#k{uid})">{body}</g></svg>')


if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "sheet":
        # linha de cima: quadrado arredondado; de baixo: círculo. Colunas = variações a..d.
        parts = []
        for n, (k, v) in enumerate(VARIANTS.items()):
            body = design(v)
            parts.append(tile(body, 30 + n * 250, 30, 200, "square", f"s{k}"))
            parts.append(tile(body, 30 + n * 250, 270, 200, "circle", f"c{k}"))
        sheet = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1020" height="500">'
                 f'<rect width="100%" height="100%" fill="#3B4A6B"/>{"".join(parts)}</svg>')
        open(sys.argv[2], "wb").write(bytes(resvg_py.svg_to_bytes(svg_string=sheet)))

    elif mode == "android":
        import os
        res = sys.argv[2]
        v = VARIANTS["b"]
        t, s = fit(WING, 26.0)
        wing = "M" + " L".join(f"{t(x, y)[0]:.2f},{t(x, y)[1]:.2f}" for x, y in WING) + " Z"
        mirror = "M" + " L".join(f"{108 - t(x, y)[0]:.2f},{t(x, y)[1]:.2f}" for x, y in WING) + " Z"
        ys = [t(x, y)[1] for x, y in WING]
        top, bottom = min(ys), max(ys)
        sw = 1.2 * s / 0.84
        head = ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
                '    xmlns:aapt="http://schemas.android.com/aapt"\n'
                '    android:width="108dp" android:height="108dp"\n'
                '    android:viewportWidth="108" android:viewportHeight="108">\n')
        bg = head + f'''    <path android:pathData="M0,0h108v108h-108z">
        <aapt:attr name="android:fillColor">
            <gradient android:type="linear" android:startX="0" android:startY="0"
                android:endX="64.8" android:endY="108"
                android:startColor="{NAVY_A}" android:endColor="{NAVY_B}"/>
        </aapt:attr>
    </path>
</vector>
'''
        ice = f'''        <aapt:attr name="android:fillColor">
            <gradient android:type="linear" android:startX="54" android:startY="{top:.2f}"
                android:endX="54" android:endY="{bottom:.2f}">
                <item android:offset="0" android:color="{ICE_HI}"/>
                <item android:offset="0.55" android:color="{ICE_MID}"/>
                <item android:offset="1" android:color="{ICE_LO}"/>
            </gradient>
        </aapt:attr>
'''
        fg = head
        for d in (wing, mirror):
            fg += (f'    <path android:pathData="{d}"\n        android:strokeColor="{ICE_HI}" '
                   f'android:strokeWidth="{sw:.2f}" android:strokeLineJoin="round">\n{ice}    </path>\n')
        fg += "</vector>\n"
        mono = head + "".join(f'    <path android:pathData="{d}" android:fillColor="#FFFFFFFF"/>\n' for d in (wing, mirror)) + "</vector>\n"
        for name, content in (("background", bg), ("foreground", fg), ("monochrome", mono)):
            open(os.path.join(res, "drawable", f"ic_launcher_{name}.xml"), "w").write(content)
        body = design(v)
        for folder, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)):
            svgs = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{px}" height="{px}" viewBox="0 0 {px} {px}">'
                    + tile(body, 0, 0, px, "square", "l") + "</svg>")
            open(os.path.join(res, f"mipmap-{folder}", "ic_launcher.png"), "wb").write(
                bytes(resvg_py.svg_to_bytes(svg_string=svgs)))
        # prévia final em 512 para conferência
        open(sys.argv[3], "wb").write(bytes(resvg_py.svg_to_bytes(svg_string=(
            '<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512">' + tile(body, 0, 0, 512, "square", "p") + "</svg>"))))
