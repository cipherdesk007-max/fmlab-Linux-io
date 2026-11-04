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
    print("$", " ".join(a), "->", r.returncode, (r.stdout + r.stderr).strip()[-300:])
    return r


def misura():
    out = run("xdpyinfo").stdout
    return next(l.split()[1] for l in out.splitlines() if "dimensions:" in l)


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
    xv = subprocess.Popen(["Xvfb", D, "-screen", "0", "1398x1398x24", "-nolisten", "tcp"])
    time.sleep(2)
    run("xrandr", "-q")
    assert run("sh", RUOTA, "1398", "644").returncode == 0, "rotazione iniziale non riuscita"
    assert misura() == "1398x644", misura()
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
    w, h = aspetta_misura(s, w, h, (644, 1398))
    assert run("sh", RUOTA, "1398", "644").returncode == 0
    aspetta_misura(s, w, h, (1398, 644))
    s.close(); vnc.terminate(); xv.terminate()
    print("OK rotazione: orizzontale -> verticale -> orizzontale senza riavviare il desktop")


if __name__ == "__main__":
    main()
