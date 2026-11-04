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


def adatta_finestre(d, root, vecchio, nuovo):
    """Dopo la rotazione ogni finestra resta dentro lo schermo nuovo (le massimizzate le rifà il gestore delle
    finestre): si rimpicciolisce se non ci sta e si sposta in proporzione, cosi' niente resta fuori o tagliato."""
    import time
    A = lambda n: d.intern_atom(n)
    (ow, oh), (W, H) = vecchio, nuovo
    time.sleep(0.4)   # il gestore finestre aggiorna prima la sua area di lavoro
    wa = root.get_full_property(A("_NET_WORKAREA"), X.AnyPropertyType)
    ax, ay, aw, ah = (list(wa.value[:4]) if wa and len(wa.value) >= 4 else [0, 0, W, H - 40])
    if aw > W or ah > H or aw < 100 or ah < 100:
        ax, ay, aw, ah = 0, 0, W, H - 40
    lista = root.get_full_property(A("_NET_CLIENT_LIST"), X.AnyPropertyType)
    salta = {A(f"_NET_WM_WINDOW_TYPE_{t}") for t in ("DOCK", "DESKTOP", "NOTIFICATION", "TOOLTIP", "SPLASH")}
    massimizzata = {A("_NET_WM_STATE_MAXIMIZED_HORZ"), A("_NET_WM_STATE_MAXIMIZED_VERT")}
    n = 0
    for wid in (lista.value if lista else []):
        try:
            w = d.create_resource_object("window", wid)
            tipo = w.get_full_property(A("_NET_WM_WINDOW_TYPE"), X.AnyPropertyType)
            if tipo and set(tipo.value) & salta:
                continue
            stato = w.get_full_property(A("_NET_WM_STATE"), X.AnyPropertyType)
            if stato and massimizzata <= set(stato.value):
                continue
            g = w.get_geometry(); p = w.translate_coords(root, 0, 0)
            x, y = -p.x, -p.y
            ext = w.get_full_property(A("_NET_FRAME_EXTENTS"), X.AnyPropertyType)
            l, r, t, b = (list(ext.value[:4]) if ext and len(ext.value) >= 4 else [0, 0, 0, 0])
            cw, ch = min(g.width, aw - l - r), min(g.height, ah - t - b)
            # posizione in proporzione allo schermo vecchio, poi dentro l'area di lavoro
            nx = ax + l + int((x - l) * max(1, aw - cw - l - r) / max(1, ow - g.width - l - r)) if ow > g.width else ax + l
            ny = ay + t + int((y - t) * max(1, ah - ch - t - b) / max(1, oh - g.height - t - b)) if oh > g.height else ay + t
            nx = max(ax + l, min(nx, ax + aw - r - cw)); ny = max(ay + t, min(ny, ay + ah - b - ch))
            if (nx, ny, cw, ch) == (x, y, g.width, g.height):
                continue
            # _NET_MOVERESIZE_WINDOW: gravita' statica (coordinate della finestra), x y larghezza altezza, da "pager"
            flags = 10 | (1 << 8) | (1 << 9) | (1 << 10) | (1 << 11) | (2 << 12)
            from Xlib.protocol import event
            ev = event.ClientMessage(window=w, client_type=A("_NET_MOVERESIZE_WINDOW"), data=(32, [flags, nx, ny, cw, ch]))
            root.send_event(ev, event_mask=X.SubstructureRedirectMask | X.SubstructureNotifyMask)
            n += 1
        except Exception:
            continue
    d.sync()
    return n


if __name__ == "__main__":
    w, h = int(sys.argv[1]), int(sys.argv[2])
    if not (240 <= w <= 2560 and 240 <= h <= 2560):
        sys.exit("FMLAB_ROTAZIONE: misura non valida")
    _d = display.Display(); _g = _d.screen().root.get_geometry(); prima = (_g.width, _g.height); _d.close()
    gw, gh = ruota(w, h)
    n = 0
    if (gw, gh) == (w, h) and prima != (w, h):
        try:
            _d = display.Display(); n = adatta_finestre(_d, _d.screen().root, prima, (w, h)); _d.close()
        except Exception as e:
            print("FMLAB_ROTAZIONE: finestre non adattate:", e)
    print(f"FMLAB_ROTAZIONE: {gw}x{gh} (finestre adattate: {n})")
    sys.exit(0 if (gw, gh) == (w, h) else 1)
