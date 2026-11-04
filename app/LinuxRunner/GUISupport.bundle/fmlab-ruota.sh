#!/bin/sh
# FMLAB Linux: gira lo schermo del desktop senza riavviarlo (orizzontale <-> verticale).
#   sh fmlab-ruota.sh LARGHEZZA ALTEZZA      (lo manda l'app quando giri il telefono)
# Xvfb e' partito quadrato grande quanto il lato lungo (session.sh), quindi qualsiasi WxH entro quel lato va.
# Crea il modo se manca e lo imposta; x11vnc (-xrandr newfbsize) avvisa il visore dell'app della nuova misura.
fmlab_modo() {
    n="${1}x${2}"
    # uscita di Xvfb (di solito "screen"): la prima collegata
    out=$(xrandr -q 2>/dev/null | awk '$2=="connected"{print $1; exit}'); out=${out:-screen}
    xrandr -q 2>/dev/null | grep -q "^ *$n " || {
        xrandr --newmode "$n" 60 "$1" $(($1+8)) $(($1+16)) $(($1+24)) "$2" $(($2+3)) $(($2+6)) $(($2+9)) 2>/dev/null
        xrandr --addmode "$out" "$n"
    }
    xrandr --output "$out" --mode "$n" --fb "$n" || xrandr --fb "$n" --output "$out" --mode "$n"
}
if [ $# -eq 2 ]; then
    case "$1$2" in *[!0-9]*|'') echo 'FMLAB_ROTAZIONE: misura non valida'; exit 2;; esac
    if fmlab_modo "$1" "$2"; then echo "FMLAB_ROTAZIONE: ${1}x${2}"
    else echo "FMLAB_ROTAZIONE: non riuscita (${1}x${2})"; exit 1; fi
fi
