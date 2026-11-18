"""Seed a real practice log into localStorage so screenshots show content.

The screenshots in `screenshots/` are verification artifacts, and an empty
journal proves nothing about the timeline layout. Headless Chrome cannot click
inside a Flutter canvas, so instead of driving the UI these host pages write the
same bytes the app itself would have written — `shared_preferences_web` stores
every value as `localStorage['flutter.' + key] = json.encode(value)`, which
means a string setting arrives double-encoded and a string list arrives as an
array of JSON strings.

Keeping the payloads here, rather than in the app, means the product code has no
screenshot-only branches.
"""

import json
import pathlib
from datetime import datetime, timedelta, timezone

# (local start, kind, minutes, phase, completed?, text)
ENTRIES = [
    ("2026-11-19 00:20", "focus", 25, "focus", True,
     "Bageshri — bādhak, second round. Kept the drone on Sa-Pa."),
    ("2026-11-19 00:47", "note", 0, None, False,
     "The meend in the third phrase finally sat. Write it down before I forget it."),
    ("2026-11-18 21:30", "riyaz", 42, None, False,
     "Tanpura only, no timer. Just ālāp in Yaman, slowly."),
    ("2026-11-18 22:20", "focus", 25, "focus", True,
     "Bandish, dhrupad-chey opening."),
    ("2026-11-18 22:50", "breakSession", 5, "shortBreak", True, ""),
    ("2026-11-18 22:56", "note", 0, None, False,
     "Slow the gamak at the top of the octave."),
    ("2026-11-17 07:00", "focus", 25, "focus", True, "Sargam exercise, medium tempo."),
    ("2026-11-17 07:35", "riyaz", 35, None, False, "Bandish recall, then meend work."),
    ("2026-11-16 06:45", "focus", 50, "focus", True, "Jhala at three speeds."),
    ("2026-11-15 22:00", "focus", 25, "focus", True, "Ālāp into jod."),
    ("2026-11-14 07:15", "riyaz", 30, None, False, "Meends and the third phrase."),
    ("2026-11-13 07:00", "focus", 25, "focus", True, "Yaman ālāp again, slower this time."),
]

NUDGE = {
    "intervalMinutes": 10,
    "quietDuringFocus": True,
    "showBanner": True,
    # Silent and notification-free so a screenshot run stays quiet; the banner
    # itself looks identical either way.
    "playChime": False,
    "osAlerts": False,
    "flashTaskbar": False,
    "prompts": [
        "Back to it — what were you in the middle of?",
        "Ten minutes on the tanpura first.",
    ],
    "promptCursor": 0,
}

TEMPLATE = """<!doctype html>
<html>
<head><meta charset="utf-8"><title>seed {w}x{h} {mode} {nudge}</title>
<style>
  html, body {{ margin: 0; background: #101010; overflow: hidden; }}
  iframe {{ border: 0; width: {w}px; height: {h}px; display: block; }}
</style>
<script>
{seed}
</script>
</head>
<body><iframe src="/index.html"></iframe></body>
</html>
"""

# Headless Chrome cannot click inside a Flutter canvas, so the phone shot needs
# the tap scripted from the parent page: Flutter web's gesture detector listens
# for pointer events on the glass pane, and the phone shell's NavigationBar has
# five equal destinations across 390 px above an 80 px bar — the third one's
# centre is x 195, y 800.
PHONE_TEMPLATE = """<!doctype html>
<html>
<head><meta charset="utf-8"><title>seed 390 journal</title>
<style>
  html, body {{ margin: 0; background: #101010; overflow: hidden; }}
  iframe {{ border: 0; width: 390px; height: 844px; display: block; }}
</style>
<script>
{seed}
function tap(frame, x, y) {{
  const win = frame.contentWindow;
  const pane = win.document.querySelector('flt-glass-pane');
  const mk = (type, Ctor, extra) => new Ctor(type, {{
    bubbles: true, composed: true, cancelable: true,
    clientX: x, clientY: y, screenX: x, screenY: y,
    pointerId: 1, pointerType: 'mouse', isPrimary: true, button: 0, ...extra,
  }});
  // The engine needs to see the pointer *arrive* before it will accept a
  // press: hover and move register the position, down/up then hit a widget.
  pane.dispatchEvent(mk('pointerover', win.PointerEvent, {{buttons: 0}}));
  pane.dispatchEvent(mk('pointerenter', win.PointerEvent, {{buttons: 0}}));
  pane.dispatchEvent(mk('pointermove', win.PointerEvent, {{buttons: 0}}));
  pane.dispatchEvent(mk('mousemove', win.MouseEvent, {{buttons: 0}}));
  setTimeout(() => {{
    pane.dispatchEvent(mk('pointerdown', win.PointerEvent, {{buttons: 1}}));
    pane.dispatchEvent(mk('mousedown', win.MouseEvent, {{buttons: 1}}));
    setTimeout(() => {{
      const up = {{buttons: 0}};
      pane.dispatchEvent(mk('pointerup', win.PointerEvent, up));
      pane.dispatchEvent(mk('mouseup', win.MouseEvent, up));
      pane.dispatchEvent(mk('click', win.MouseEvent, up));
    }}, 300);
  }}, 300);
}}
// Headless Chrome reports the page as hidden, which makes Flutter web's
// visibility observer stop producing frames after the first one — a screenshot
// then catches a transition mid-flight. Claiming the page is visible and firing
// the event the observer listens for lets it paint the settled state.
function forceVisible(frame) {{
  const win = frame.contentWindow;
  Object.defineProperty(win.document, 'visibilityState', {{get: () => 'visible', configurable: true}});
  Object.defineProperty(win.document, 'hidden', {{get: () => false, configurable: true}});
  win.document.dispatchEvent(new win.Event('visibilitychange'));
}}
window.addEventListener('load', () => {{
  const frame = document.querySelector('iframe');
  [2000, 6000, 8500, 9500, 11000].forEach((t) => setTimeout(() => forceVisible(frame), t));
  setTimeout(() => {{
    tap(frame, 195, 804);
    setTimeout(() => forceVisible(frame), 1500);
  }}, 9000);
}});
</script>
</head>
<body><iframe src="/index.html"></iframe></body>
</html>
"""


def _utc(moment: str) -> str:
    """Local wall clock in the seeded entries, as the UTC ISO the store writes.

    The suffix matters: Dart's DateTime.parse reads a bare timestamp as *local*
    time, and the store writes every row in UTC.
    """
    local = datetime.strptime(moment, "%Y-%m-%d %H:%M").astimezone(timezone.utc)
    return local.strftime("%Y-%m-%dT%H:%M:%S.%f") + "Z"


def _rows() -> list[str]:
    rows = []
    for index, (start, kind, minutes, phase, completed, text) in enumerate(ENTRIES):
        begin = datetime.strptime(start, "%Y-%m-%d %H:%M")
        row = {
            "id": f"seed-{index}",
            "k": kind,
            "s": _utc(start),
        }
        if minutes:
            row["e"] = _utc((begin + timedelta(minutes=minutes)).strftime("%Y-%m-%d %H:%M"))
        if phase:
            row["p"] = phase
            row["pl"] = minutes
        if text:
            row["t"] = text
        if completed:
            row["c"] = True
        rows.append(json.dumps(row, ensure_ascii=False))
    return rows


def _sessions() -> list[str]:
    return [
        json.dumps({"t": _utc(start), "m": minutes})
        for start, minutes, completed in [
            ("2026-11-19 00:45", 25, True),
            ("2026-11-18 22:45", 25, True),
            ("2026-11-17 07:25", 25, True),
            ("2026-11-16 07:35", 50, True),
            ("2026-11-15 22:25", 25, True),
            ("2026-11-14 07:45", 30, True),
            ("2026-11-13 07:25", 25, True),
        ]
        if completed
    ]


def main() -> None:
    out = pathlib.Path("build/web")

    def seed(dark: bool, nudges: bool) -> str:
        store = {
            "flutter.app.darkMode.v1": json.dumps(dark),
            "flutter.journal.entries.v1": json.dumps(_rows(), ensure_ascii=False),
            "flutter.pomodoro.focusLog.v1": json.dumps(_sessions()),
            "flutter.nudge.config.v1": json.dumps(
                json.dumps(NUDGE if nudges else {**NUDGE, "intervalMinutes": 0})
            ),
        }
        lines = [
            f"localStorage.setItem({json.dumps(key)}, {json.dumps(value)});"
            for key, value in store.items()
        ]
        return "\n  ".join(lines)

    for width, height in [(1440, 900), (820, 1000), (390, 844)]:
        for mode, dark in [("dark", True), ("light", False)]:
            for nudge in [False, True]:
                name = f"_seed_{width}_{mode}{'_nudge' if nudge else ''}.html"
                (out / name).write_text(
                    TEMPLATE.format(
                        w=width, h=height, mode=mode, nudge=str(nudge),
                        seed=seed(dark, nudge),
                    ),
                    encoding="utf-8",
                )
                print(name)

    (out / "_seed_390_journal.html").write_text(
        PHONE_TEMPLATE.format(seed=seed(dark=True, nudges=False)), encoding="utf-8"
    )
    print("_seed_390_journal.html")


if __name__ == "__main__":
    main()
