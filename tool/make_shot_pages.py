"""Build throwaway host pages so headless Chrome can show real narrow viewports.

Chrome clamps --window-size to a ~500 px minimum, so a phone-sized Flutter web
run cannot be screenshotted directly. Embedding the app in an exact-size iframe
gives it a true 390 px viewport, and the same-origin parent can seed
localStorage first to pick the theme.
"""

import json
import pathlib

TEMPLATE = """<!doctype html>
<html>
<head><meta charset="utf-8"><title>shot {w}x{h} {mode}</title>
<style>
  body {{ margin: 0; background: #333; display: flex; }}
  iframe {{ border: 0; width: {w}px; height: {h}px; display: block; }}
</style>
<script>
  localStorage.setItem('flutter.app.darkMode.v1', {dark});
</script>
</head>
<body><iframe src="/index.html"></iframe><div style="width:40px;height:{h}px;background:#f0f"></div></body>
</html>
"""


def main() -> None:
    out = pathlib.Path("build/web")
    for width, height in [(390, 844), (360, 640), (430, 932)]:
        for mode, dark in [("dark", "true"), ("light", "false")]:
            name = f"_shot_{width}_{mode}.html"
            (out / name).write_text(
                TEMPLATE.format(w=width, h=height, mode=mode, dark=dark),
                encoding="utf-8",
            )
            print(name, json.dumps({"size": f"{width}x{height}", "mode": mode}))


if __name__ == "__main__":
    main()
