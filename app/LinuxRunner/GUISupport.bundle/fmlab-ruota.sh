#!/bin/sh
# FMLAB Linux: gira lo schermo del desktop senza riavviarlo (orizzontale <-> verticale).
#   sh fmlab-ruota.sh LARGHEZZA ALTEZZA      (lo manda l'app quando giri il telefono)
# Xvfb e' partito quadrato grande quanto il lato lungo (session.sh), quindi qualsiasi WxH entro quel lato va.
# Crea il modo se manca e lo imposta; x11vnc (-xrandr newfbsize) avvisa il visore dell'app della nuova misura.
fmlab_modo() {
    # Con Python + Xlib (installati da RunnerKit): misura creata, agganciata e usata nella stessa connessione.
    qui=$(CDPATH= cd -- "$(dirname -- "${FMLAB_RUOTA_DIR:-$0}")" 2>/dev/null && pwd)
    for d in "$qui" /home/mobile/Downloads/.linuxrunner/gui .; do
        if [ -f "$d/fmlab-ruota.py" ] && python3 -c 'import Xlib' 2>/dev/null; then python3 "$d/fmlab-ruota.py" "$1" "$2"; return; fi
    done
    echo "FMLAB_ROTAZIONE: serve python3-xlib (lo installa RunnerKit)"; return 1
}
# Solo se lanciato da solo (dall'app). Caricato da session.sh (". ./fmlab-ruota.sh") NON deve guardare i
# parametri della sessione: nella 0.8.0 lo faceva, rispondeva "misura non valida" e il desktop non partiva.
if [ -z "${FMLAB_RUOTA_SORGENTE:-}" ] && [ $# -eq 2 ]; then
    case "$1$2" in *[!0-9]*|'') echo 'FMLAB_ROTAZIONE: misura non valida'; exit 2;; esac
    if fmlab_modo "$1" "$2"; then echo "FMLAB_ROTAZIONE: ${1}x${2}"
    else echo "FMLAB_ROTAZIONE: non riuscita (${1}x${2})"; exit 1; fi
fi
