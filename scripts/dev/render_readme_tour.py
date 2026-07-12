from __future__ import annotations

from pathlib import Path
from typing import Iterable

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "docs" / "media" / "readme" / "aethertune-platform-tour.gif"
SIZE = (960, 540)


def font(size: int, *, bold: bool = False) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = [
        Path("C:/Windows/Fonts/segoeuib.ttf" if bold else "C:/Windows/Fonts/segoeui.ttf"),
        Path("C:/Windows/Fonts/arialbd.ttf" if bold else "C:/Windows/Fonts/arial.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    try:
        return ImageFont.truetype("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf", size)
    except OSError:
        return ImageFont.load_default()


F_TITLE = font(56, bold=True)
F_H1 = font(34, bold=True)
F_H2 = font(24, bold=True)
F_BODY = font(19)
F_SMALL = font(15)
F_TINY = font(13, bold=True)


def lerp(a: int, b: int, t: float) -> int:
    return int(a + (b - a) * t)


def gradient(size: tuple[int, int], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGB", size, top)
    pixels = image.load()
    for y in range(size[1]):
        t = y / max(size[1] - 1, 1)
        color = tuple(lerp(top[i], bottom[i], t) for i in range(3))
        for x in range(size[0]):
            pixels[x, y] = color
    return image


def text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    value: str,
    fill: str,
    text_font: ImageFont.ImageFont,
    *,
    anchor: str | None = None,
) -> None:
    draw.text(xy, value, fill=fill, font=text_font, anchor=anchor)


def fit_text(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    value: str,
    fill: str,
    text_font: ImageFont.ImageFont,
    max_width: int,
    line_height: int,
    *,
    max_lines: int = 3,
) -> None:
    words = value.split()
    lines: list[str] = []
    current = ""
    for word in words:
        candidate = word if not current else f"{current} {word}"
        width = draw.textbbox((0, 0), candidate, font=text_font)[2]
        if width <= max_width:
            current = candidate
            continue
        if current:
            lines.append(current)
        current = word
    if current:
        lines.append(current)

    x, y = xy
    for line in lines[:max_lines]:
        text(draw, (x, y), line, fill, text_font)
        y += line_height


def chip(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], label: str, fill: str, fg: str) -> None:
    draw.rounded_rectangle(box, radius=18, fill=fill)
    text(draw, ((box[0] + box[2]) // 2, (box[1] + box[3]) // 2 - 1), label, fg, F_TINY, anchor="mm")


def card(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], fill: str = "#f8fafc") -> None:
    draw.rounded_rectangle(box, radius=26, fill=fill)


def base(title: str, subtitle: str) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = gradient(SIZE, (8, 17, 38), (10, 99, 102))
    draw = ImageDraw.Draw(image)
    text(draw, (56, 48), title, "#ffffff", F_H1)
    text(draw, (58, 90), subtitle, "#bae6fd", F_BODY)
    return image, draw


def draw_phone(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    w: int,
    h: int,
    title_value: str,
    accent: str,
    rows: Iterable[str],
    *,
    dark: bool = False,
) -> None:
    draw.rounded_rectangle((x, y, x + w, y + h), radius=38, fill="#020617")
    screen = (x + 14, y + 18, x + w - 14, y + h - 18)
    draw.rounded_rectangle(screen, radius=28, fill="#111827" if dark else "#f8fafc")
    fg = "#f8fafc" if dark else "#111827"
    muted = "#94a3b8" if dark else "#64748b"
    draw.rounded_rectangle((x + w // 2 - 42, y + 30, x + w // 2 + 42, y + 38), radius=4, fill=muted)
    text(draw, (x + 34, y + 72), "AetherTune", fg, F_H2)
    text(draw, (x + 34, y + 103), title_value, muted, F_SMALL)
    draw.rounded_rectangle((x + 34, y + 132, x + w - 34, y + 172), radius=16, fill="#e0f2fe" if not dark else "#1e293b")
    text(draw, (x + 54, y + 145), "Search library, sources, radio", "#0369a1" if not dark else "#7dd3fc", F_SMALL)

    row_y = y + 202
    for index, row in enumerate(rows):
        fill = "#ffffff" if not dark else "#0f172a"
        draw.rounded_rectangle((x + 34, row_y, x + w - 34, row_y + 58), radius=18, fill=fill, outline="#e2e8f0")
        draw.rounded_rectangle((x + 52, row_y + 13, x + 84, row_y + 45), radius=10, fill=accent)
        text(draw, (x + 98, row_y + 18), row, fg, F_SMALL)
        text(draw, (x + 98, row_y + 38), "local + provider ready", muted, font(12))
        row_y += 70
        if index == 2:
            break

    draw.rounded_rectangle((x + 34, y + h - 96, x + w - 34, y + h - 38), radius=20, fill="#0f172a")
    draw.rounded_rectangle((x + 54, y + h - 78, x + 88, y + h - 44), radius=10, fill=accent)
    text(draw, (x + 102, y + h - 75), "Now playing", "#ffffff", F_SMALL)
    text(draw, (x + 102, y + h - 54), "queue + lyrics + radio", "#cbd5e1", font(12))


def draw_desktop(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    w: int,
    h: int,
    title_value: str,
    accent: str,
    labels: tuple[str, str, str],
    *,
    dark: bool = False,
) -> None:
    fill = "#0f172a" if dark else "#f8fafc"
    fg = "#f8fafc" if dark else "#111827"
    muted = "#94a3b8" if dark else "#64748b"
    draw.rounded_rectangle((x, y, x + w, y + h), radius=24, fill=fill)
    draw.rounded_rectangle((x, y, x + w, y + 42), radius=24, fill="#111827")
    for dot_x, color in ((x + 28, "#ef4444"), (x + 54, "#f59e0b"), (x + 80, "#22c55e")):
        draw.ellipse((dot_x, y + 16, dot_x + 10, y + 26), fill=color)
    text(draw, (x + 112, y + 13), f"AetherTune {title_value}", "#f8fafc", F_SMALL)

    draw.rounded_rectangle((x + 26, y + 62, x + 190, y + h - 28), radius=18, fill="#111827" if not dark else "#020617")
    for i, label in enumerate(("Library", "Sources", "Queue", "Options")):
        chip(draw, (x + 46, y + 82 + i * 48, x + 170, y + 116 + i * 48), label, "#1e293b", "#dbeafe")

    draw.rounded_rectangle((x + 222, y + 62, x + w - 40, y + 108), radius=16, fill="#ffffff" if not dark else "#1e293b")
    text(draw, (x + 246, y + 77), "Search open providers and local music", muted, F_SMALL)
    draw.rounded_rectangle((x + w - 150, y + 72, x + w - 64, y + 98), radius=13, fill=accent)
    text(draw, (x + w - 107, y + 84), "Play", "#ffffff", F_TINY, anchor="mm")

    for i, label in enumerate(labels):
        top = y + 122 + i * 48
        draw.rounded_rectangle((x + 222, top, x + w - 40, top + 42), radius=14, fill="#ffffff" if not dark else "#1e293b", outline="#dbeafe")
        draw.rounded_rectangle((x + 244, top + 8, x + 270, top + 34), radius=8, fill=accent)
        text(draw, (x + 286, top + 6), label, fg, F_SMALL)
        text(draw, (x + 286, top + 25), "cross-platform Flutter surface", muted, font(11))

    draw.rounded_rectangle((x + 222, y + h - 66, x + w - 40, y + h - 28), radius=16, fill="#020617" if not dark else "#111827")
    text(draw, (x + 248, y + h - 54), "Mini player", "#f8fafc", F_SMALL)
    draw.rounded_rectangle((x + w - 270, y + h - 48, x + w - 80, y + h - 40), radius=4, fill="#334155")
    draw.rounded_rectangle((x + w - 270, y + h - 48, x + w - 168, y + h - 40), radius=4, fill=accent)


def overview() -> Image.Image:
    image = gradient(SIZE, (5, 14, 31), (6, 95, 70))
    draw = ImageDraw.Draw(image)
    text(draw, (64, 64), "AetherTune", "#ffffff", F_TITLE)
    fit_text(
        draw,
        (66, 128),
        "Open music workspace for Android, iOS, Windows, macOS, Linux, and a Dart server.",
        "#d1fae5",
        F_BODY,
        760,
        28,
    )
    platforms = [
        ("Android", "#22c55e"),
        ("iOS", "#ec4899"),
        ("Windows", "#38bdf8"),
        ("macOS", "#f59e0b"),
        ("Linux", "#84cc16"),
    ]
    x = 68
    for label, color in platforms:
        chip(draw, (x, 200, x + 138, 250), label, color, "#020617")
        x += 158
    card(draw, (70, 316, 890, 420), "#f8fafc")
    text(draw, (108, 354), "Local files + provider search + podcasts + radio + Internet Archive", "#0f172a", F_BODY)
    text(draw, (108, 388), "No ads, no telemetry, official/open sources only", "#0f766e", F_SMALL)
    text(draw, (68, 486), "README tour", "#bae6fd", F_SMALL)
    return image


def mobile() -> Image.Image:
    image, draw = base("Mobile-first player", "Android and iOS previews for library, sources, lyrics, and queues.")
    draw_phone(draw, 94, 132, 260, 362, "Android", "#22c55e", ("Folder imports", "Provider search", "Start radio"))
    draw_phone(draw, 606, 132, 260, 362, "iOS", "#ec4899", ("Playlists", "Synced lyrics", "Privacy"), dark=False)
    card(draw, (374, 178, 586, 448), "#ffffff")
    text(draw, (398, 218), "Shared Flutter UI", "#0f172a", font(20, bold=True))
    fit_text(
        draw,
        (398, 258),
        "Touch-first browsing, local playback, smart playlists, lyrics, queues, and offline-aware sources.",
        "#475569",
        F_SMALL,
        164,
        22,
        max_lines=7,
    )
    return image


def windows() -> Image.Image:
    image, draw = base("Windows desktop", "Wide layout for provider search, queue management, and playback control.")
    draw_desktop(draw, 78, 130, 804, 344, "for Windows", "#2563eb", ("Unified provider search", "Queue reorder/remove", "Start radio from any track"))
    return image


def macos() -> Image.Image:
    image, draw = base("macOS desktop", "Artwork-forward playback with lyrics, playlists, and source privacy.")
    draw_desktop(draw, 78, 130, 804, 344, "on macOS", "#f59e0b", ("Artwork and player controls", "Synced LRC lyrics", "Smart playlist rules"), dark=False)
    return image


def linux() -> Image.Image:
    image, draw = base("Linux desktop", "Local folders, open providers, backups, and CI-verified desktop builds.")
    draw_desktop(draw, 78, 130, 804, 344, "on Linux", "#22c55e", ("Recursive folder import", "Radio Browser + Archive", "JSON backup and restore"), dark=True)
    return image


def server() -> Image.Image:
    image, draw = base("Optional sync server", "Authenticated, versioned snapshots for a local-first library.")
    card(draw, (90, 142, 364, 432), "#0f172a")
    text(draw, (124, 186), "AetherTune Server", "#f8fafc", F_H2)
    for i, endpoint in enumerate(("/health", "/api/v1/info", "/api/v1/sync/library")):
        draw.rounded_rectangle((124, 226 + i * 58, 326, 270 + i * 58), radius=15, fill=("#064e3b", "#1e3a8a", "#7c2d12")[i])
        text(draw, (150, 239 + i * 58), endpoint, "#f8fafc", F_SMALL)

    card(draw, (416, 142, 870, 432), "#ffffff")
    text(draw, (454, 192), "Cross-platform app, shared project", "#0f172a", F_H2)
    for i, label in enumerate(("Bearer-token authentication", "Checksum + revision conflicts", "Portable, path-free snapshots")):
        draw.rounded_rectangle((454, 240 + i * 54, 818, 282 + i * 54), radius=16, fill="#ecfeff", outline="#a5f3fc")
        text(draw, (480, 252 + i * 54), label, "#155e75", F_SMALL)
    return image


def main() -> None:
    frames = [overview(), mobile(), windows(), macos(), linux(), server()]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        OUT,
        save_all=True,
        append_images=frames[1:],
        duration=[1300, 1100, 1100, 1100, 1100, 1300],
        loop=0,
        optimize=True,
        disposal=2,
    )
    print(f"Wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
