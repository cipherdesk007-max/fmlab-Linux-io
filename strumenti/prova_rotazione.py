#!/usr/bin/env python3
"""Prova della rotazione del desktop (FMLAB Linux 0.8), come sul telefono ma su Linux normale:
Xvfb quadrato 1398x1398 -> fmlab-ruota.sh 1398 644 -> x11vnc -xrandr newfbsize -> un visore RFB (come quello
dell'app, app/LinuxRunner/RFBClient.m) deve ricevere DesktopSize 644x1398 quando si gira in verticale e di nuovo
1398x644 tornando in orizzontale. Serve: Xvfb, x11vnc, xrandr, xdpyinfo."""
import os, socket, struct, subprocess, sys, time

D = ":77"
QUI = os.path.dirname(os.path.abspath(__file__))
RUOTA = os.path.join(QUI, "..", "app", "LinuxRunner", "GUISupport.bundle", "fmlab-ruota.sh")
env = dict(os.environ, DISPLAY=D)


def run(*a):
    r = subprocess.run(a, env=env, capture_output=True, text=True)
    print("$", " ".join(a), "->", r.returncode, (r.stdout + r.stderr).strip()[-1500:])
    return r


def misura():
    """Misura della finestra principale (come la legge desktop-components.sh con xwininfo -root)."""
    out = run("xwininfo", "-root").stdout
    w = next(l.split()[1] for l in out.splitlines() if l.strip().startswith("Width:"))
    h = next(l.split()[1] for l in out.splitlines() if l.strip().startswith("Height:"))
    return f"{w}x{h}"


def leggi(s, n):
    b = b""
    while len(b) < n:
        c = s.recv(n - len(b))
        if not c:
            raise SystemExit("connessione chiusa")
        b += c
    return b


def aspetta_misura(s, w0, h0, voluta, secondi=20):
    """Chiede aggiornamenti finche' non arriva un DesktopSize (-223) con la misura voluta."""
    w, h = w0, h0
    fine = time.time() + secondi
    while time.time() < fine:
        s.sendall(struct.pack(">BBHHHH", 3, 1, 0, 0, w, h))
        t = leggi(s, 1)[0]
        if t == 2:
            continue
        if t == 3:
            _, n = struct.unpack(">3sI", leggi(s, 7)); leggi(s, n); continue
        assert t == 0, f"messaggio inatteso {t}"
        _, nr = struct.unpack(">BH", leggi(s, 3))
        for _ in range(nr):
            x, y, rw, rh, enc = struct.unpack(">HHHHi", leggi(s, 12))
            if enc == -223:
                w, h = rw, rh
                print("DesktopSize ->", w, h)
            elif enc == 0:
                leggi(s, rw * rh * 4)
            else:
                raise SystemExit(f"codifica inattesa {enc}")
        if (w, h) == voluta:
            return w, h
    raise SystemExit(f"il visore non ha ricevuto {voluta} (ultima misura {w}x{h})")


def main():
    xv = subprocess.Popen(["Xvfb", D, "-screen", "0", "1398x1398x24", "-noreset", "-nolisten", "tcp"])
    time.sleep(2)
    run("xrandr", "-q")
    assert run("sh", RUOTA, "1398", "644").returncode == 0, "rotazione iniziale non riuscita"
    assert misura() == "1398x644", misura()
    # finestre: un gestore finestre vero (openbox) e una finestra larga; girando deve restare tutta dentro
    wm = subprocess.Popen(["openbox"], env=env); time.sleep(2)
    xl = subprocess.Popen(["xlogo", "-geometry", "1200x500+150+60"], env=env); time.sleep(2)
    vnc = subprocess.Popen(["x11vnc", "-display", D, "-localhost", "-rfbport", "5977", "-nopw", "-forever",
                            "-xrandr", "newfbsize", "-noxrecord", "-noxdamage", "-quiet"], env=env)
    time.sleep(3)
    s = socket.create_connection(("127.0.0.1", 5977), timeout=20)
    leggi(s, 12); s.sendall(b"RFB 003.008\n")
    n = leggi(s, 1)[0]; tipi = leggi(s, n); assert 1 in tipi, tipi
    s.sendall(b"\x01"); assert struct.unpack(">I", leggi(s, 4))[0] == 0
    s.sendall(b"\x01")
    w, h = struct.unpack(">HH", leggi(s, 4)); leggi(s, 16); leggi(s, struct.unpack(">I", leggi(s, 4))[0])
    print("visore collegato:", w, h); assert (w, h) == (1398, 644)
    s.sendall(struct.pack(">BxxxBBBBHHHBBBxxx", 0, 32, 24, 0, 1, 255, 255, 255, 16, 8, 0))   # come l'app
    s.sendall(struct.pack(">BxHii", 2, 2, 0, -223))                                        # Raw + DesktopSize
    assert run("sh", RUOTA, "644", "1398").returncode == 0
    assert misura() == "644x1398", misura()
    time.sleep(1)
    info = run("xwininfo", "-name", "xlogo").stdout
    v = {k.strip(): int(x.split()[0]) for k, x in (l.split(":", 1) for l in info.splitlines() if ":" in l)
         if k.strip() in ("Absolute upper-left X", "Absolute upper-left Y", "Width", "Height")}
    print("finestra in verticale:", v)
    assert v["Absolute upper-left X"] >= 0 and v["Absolute upper-left X"] + v["Width"] <= 644, "finestra fuori in larghezza"
    assert v["Absolute upper-left Y"] >= 0 and v["Absolute upper-left Y"] + v["Height"] <= 1398, "finestra fuori in altezza"
    w, h = aspetta_misura(s, w, h, (644, 1398))
    assert run("sh", RUOTA, "1398", "644").returncode == 0
    aspetta_misura(s, w, h, (1398, 644))
    s.close(); vnc.terminate(); xl.terminate(); wm.terminate(); xv.terminate()
    print("OK rotazione: orizzontale -> verticale -> orizzontale senza riavviare il desktop, finestre dentro lo schermo")


if __name__ == "__main__":
    main()
