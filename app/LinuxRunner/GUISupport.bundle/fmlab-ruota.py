#!/usr/bin/env python3
"""FMLAB Linux: gira lo schermo di Xvfb a LARGHEZZA x ALTEZZA con RandR, in una sola connessione.
(xrandr --newmode crea la misura e la perde quando esce: Xvfb la cancella se nessuno la usa ancora.)
Uso: python3 fmlab-ruota.py LARGHEZZA ALTEZZA"""
import sys
from Xlib import X, display
from Xlib.ext import randr


def ruota(w, h):
    d = display.Display()
    root = d.screen().root
    res = randr.get_screen_resources(root)
    out = next(o for o in res.outputs if randr.get_output_info(root, o, res.config_timestamp).connection == 0)
    crtc = res.crtcs[0]
    nome = f"{w}x{h}"
    mode = next((m.id for m in res.modes if (m.width, m.height) == (w, h)), None)
    if mode is None:
        info = dict(id=0, width=w, height=h, dot_clock=60_000_000, h_sync_start=w + 8, h_sync_end=w + 16,
                    h_total=w + 24, h_skew=0, v_sync_start=h + 3, v_sync_end=h + 6, v_total=h + 9,
                    name_length=len(nome), flags=0)
        mode = randr.create_mode(root, info, nome).mode
    if mode not in randr.get_output_info(root, out, res.config_timestamp).modes:
        randr.add_output_mode(d, out, mode)
    # spegni, cambia misura dello schermo, riaccendi con la misura nuova (cosi' va sia ingrandendo sia rimpicciolendo)
    ts = randr.get_screen_resources(root).config_timestamp
    randr.set_crtc_config(d, crtc, ts, 0, 0, 0, randr.Rotate_0, [])
    mm = lambda px: max(1, int(px * 25.4 / 96))
    randr.set_screen_size(root, w, h, mm(w), mm(h))
    ts = randr.get_screen_resources(root).config_timestamp
    randr.set_crtc_config(d, crtc, ts, 0, 0, mode, randr.Rotate_0, [out])
    d.sync()
    g = root.get_geometry()
    return g.width, g.height


if __name__ == "__main__":
    w, h = int(sys.argv[1]), int(sys.argv[2])
    if not (240 <= w <= 2560 and 240 <= h <= 2560):
        sys.exit("FMLAB_ROTAZIONE: misura non valida")
    gw, gh = ruota(w, h)
    print(f"FMLAB_ROTAZIONE: {gw}x{gh}")
    sys.exit(0 if (gw, gh) == (w, h) else 1)
