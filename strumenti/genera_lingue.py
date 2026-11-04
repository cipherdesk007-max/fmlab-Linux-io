#!/usr/bin/env python3
"""Crea app/FMLAB/it.lproj/Localizable.strings da strumenti/traduzioni_it.py e controlla che ogni testo
dell'interfaccia (Text/Label/Button/Section/Toggle/NavigationLink/navigationTitle/Picker con testo fisso) abbia
la traduzione italiana. Con --controlla esce con errore se ne manca qualcuna (usato dalla compilazione)."""
import glob, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from traduzioni_it import TR

def vero(s):  # testo come lo vede l'app (senza gli escape del sorgente Swift)
    return s.replace('\\"', '"').replace("\\\\", "\\")

tr = {vero(k): vero(v) for k, v in TR.items()}
chiavi = []
for f in sorted(glob.glob("app/LinuxRunner/*.swift")):
    s = open(f, encoding="utf-8").read()
    for m in re.finditer(r'\b(?:Text|Label|Button|Section|Toggle|NavigationLink|navigationTitle|Picker)\(\s*"((?:[^"\\]|\\.)*)"', s):
        k = m.group(1)
        if "\\(" in k or not k.strip():
            continue
        chiavi.append(vero(k))
mancano = sorted({k for k in chiavi if k not in tr})
if mancano:
    print("Manca la traduzione italiana di:")
    for k in mancano:
        print("  -", k[:100])
    if "--controlla" in sys.argv:
        sys.exit(1)

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

os.makedirs("app/FMLAB/it.lproj", exist_ok=True)
with open("app/FMLAB/it.lproj/Localizable.strings", "w", encoding="utf-8") as out:
    out.write("/* FMLAB Linux, italiano. Generato da strumenti/genera_lingue.py: modifica strumenti/traduzioni_it.py */\n")
    for k in sorted(tr):
        out.write(f'"{esc(k)}" = "{esc(tr[k])}";\n')
print(f"it.lproj: {len(tr)} testi, {len(set(chiavi))} usati nell'interfaccia, {len(mancano)} senza traduzione")
