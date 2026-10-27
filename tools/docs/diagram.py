"""Gera o diagrama do README em duas versões, clara e escura, com fundo transparente.

Uso:
    python3 tools/docs/diagram.py docs
        (docs/arquitetura-light.svg e docs/arquitetura-dark.svg; o README escolhe
        pelo tema com <picture>)
"""
import os
import sys

# Cores no espírito do GitHub para ficar em casa nos dois temas.
THEMES = {
    "light": {
        "fg": "#1F2328", "muted": "#59636E", "line": "#D1D9E0", "soft": "#F6F8FA",
        "wol": "#9A6700", "tls": "#0969DA", "live": "#1A7F37", "pres": "#8250DF",
    },
    "dark": {
        "fg": "#E6EDF3", "muted": "#9198A1", "line": "#3D444D", "soft": "#151B23",
        "wol": "#D29922", "tls": "#58A6FF", "live": "#3FB950", "pres": "#A371F7",
    },
}

# Asas do ícone, já no quadro 0..40.
WING_L = "M20,34 L6,12 L11,14 L11.5,9 L15.5,15 L17,10.5 L20,21 Z"
WING_R = "M20,34 L34,12 L29,14 L28.5,9 L24.5,15 L23,10.5 L20,21 Z"

# (y, cor, título, detalhe, sentido): "->" celular → PC, "<-" PC → celular, "<>" os dois.
CHANNELS = [
    (118, "wol", "Wake-on-LAN", "UDP 9", "->"),
    (204, "tls", "Comandos", "HTTPS · TLS 1.3 com pin · TCP 41100", "->"),
    (252, "live", "Ao vivo", "desempenho, mídia e avisos · SSE", "<-"),
    (338, "pres", "Presença", "antes do login · UDP 41101", "<>"),
]

# (y, altura, cor, título, linhas de detalhe)
PARTS = [
    (88, 60, "wol", "Placa de rede", ["acorda o PC desligado"]),
    (172, 112, "tls", "velksync-agent", ["energia, comandos, mídia e terminal", "desempenho e avisos para o celular",
                                         "roda quando você entra"]),
    (308, 60, "pres", "Sinal de presença", ["responde só \"estou ligado\""]),
]


def svg(c):
    out = [
        '<svg xmlns="http://www.w3.org/2000/svg" width="880" height="420" viewBox="0 0 880 420" '
        'role="img" aria-labelledby="t d">',
        '<title id="t">Como o Velksync funciona</title>',
        '<desc id="d">O celular liga o PC por Wake-on-LAN, manda comandos ao agente por HTTPS com certificado '
        'fixado, recebe desempenho, mídia e avisos ao vivo e vê o PC ligado antes do login pelo sinal de '
        'presença. Tudo na rede local.</desc>',
        "<defs>",
    ]
    for k in ("wol", "tls", "live", "pres"):
        out.append(f'<marker id="m-{k}" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="6" markerHeight="6" '
                   f'orient="auto-start-reverse"><path d="M1,1 L9,5 L1,9" fill="none" stroke="{c[k]}" '
                   'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></marker>')
    out.append(
        '<style>text{font-family:-apple-system,"Segoe UI",Ubuntu,"Noto Sans",Helvetica,Arial,sans-serif}'
        f'.h{{font-size:16px;font-weight:600;fill:{c["fg"]}}}'
        f'.t{{font-size:14px;font-weight:600}}'
        f'.m{{font-size:12.5px;fill:{c["muted"]}}}</style></defs>')

    # Rede local: só uma moldura tracejada discreta.
    out.append(f'<rect x="1" y="1" width="878" height="418" rx="16" fill="none" stroke="{c["line"]}" '
               'stroke-width="1.5" stroke-dasharray="6 6"/>')
    out.append(f'<text x="24" y="30" class="m">rede local · nada sai dela</text>')

    # Celular.
    out.append(f'<rect x="48" y="78" width="148" height="300" rx="26" fill="none" stroke="{c["fg"]}" '
               'stroke-width="1.8"/>')
    out.append(f'<rect x="104" y="90" width="36" height="5" rx="2.5" fill="{c["line"]}"/>')
    out.append(f'<g transform="translate(92 168) scale(1.5)">'
               f'<path d="{WING_L}" fill="{c["tls"]}" fill-opacity="0.2" stroke="{c["tls"]}" stroke-width="1.2" '
               'stroke-linejoin="round"/>'
               f'<path d="{WING_R}" fill="{c["tls"]}" fill-opacity="0.2" stroke="{c["tls"]}" stroke-width="1.2" '
               'stroke-linejoin="round"/></g>')
    out.append('<text x="122" y="262" class="h" text-anchor="middle">App</text>')
    out.append('<text x="122" y="282" class="m" text-anchor="middle">Android</text>')

    # PC.
    out.append(f'<rect x="580" y="62" width="276" height="330" rx="18" fill="none" stroke="{c["fg"]}" '
               'stroke-width="1.8"/>')
    out.append('<text x="600" y="50" class="h">PC</text>')
    out.append('<text x="626" y="50" class="m">Windows ou Linux</text>')
    for y, h, k, title, details in PARTS:
        out.append(f'<rect x="598" y="{y}" width="240" height="{h}" rx="10" fill="{c["soft"]}" '
                   f'stroke="{c["line"]}"/>')
        out.append(f'<rect x="598" y="{y + 12}" width="3" height="{h - 24}" rx="1.5" fill="{c[k]}"/>')
        out.append(f'<text x="616" y="{y + 26}" class="t" fill="{c["fg"]}">{title}</text>')
        for i, detail in enumerate(details):
            out.append(f'<text x="616" y="{y + 45 + 19 * i}" class="m">{detail}</text>')

    # Canais.
    for y, k, title, detail, way in CHANNELS:
        x1, x2 = 208, 586
        start = f' marker-start="url(#m-{k})"' if way in ("<-", "<>") else ""
        end = f' marker-end="url(#m-{k})"' if way in ("->", "<>") else ""
        dash = ' stroke-dasharray="7 5"' if way == "<-" else ""
        out.append(f'<line x1="{x1}" y1="{y}" x2="{x2}" y2="{y}" stroke="{c[k]}" stroke-width="2"'
                   f' stroke-linecap="round"{dash}{start}{end}/>')
        out.append(f'<text x="228" y="{y - 10}" class="t" fill="{c[k]}">{title}'
                   f'<tspan class="m" dx="10">{detail}</tspan></text>')

    out.append("</svg>")
    return "\n".join(out) + "\n"


if __name__ == "__main__":
    out = sys.argv[1]
    for name, colors in THEMES.items():
        with open(os.path.join(out, f"arquitetura-{name}.svg"), "w", encoding="utf-8") as f:
            f.write(svg(colors))
