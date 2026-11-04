#!/usr/bin/env python3
"""Crea app/FMLAB/it.lproj/Localizable.strings da strumenti/traduzioni_it.py e controlla che ogni testo
dell'interfaccia abbia la traduzione italiana. Con --controlla esce con errore se ne manca qualcuna (lo usa la
compilazione su GitHub), così nessun testo nuovo resta in inglese.

Cosa controlla:
- Swift (app/LinuxRunner/*.swift): ogni testo fisso dentro Text/Label/Button/Section/Toggle/NavigationLink/Picker/
  alert/LabeledContentRow/LF/TextField/... anche nelle scelte "a ? "x" : "y"" e nei testi con valori dentro
  ("Passati \\(n) secondi" diventa la chiave "Elapsed %@ seconds").
- Objective-C (schermo del desktop, menu e avvisi): ogni frase che finisce a schermo, esclusi i testi tecnici
  elencati in TECNICI (registri, nomi interni, pulsanti di prova nascosti).
"""
import glob, itertools, os, re, sys
sys.path.insert(0, os.path.dirname(__file__))
from traduzioni_it import TR, TR_OBJC

SWIFT = ["app/LinuxRunner/*.swift", "app/FMLAB/*.swift", "app/FMLAB/Emulatore/*.swift"]
OBJC = ["app/LinuxRunner/GUIViewController.m", "app/LinuxRunner/RuntimeBridge.m", "app/TerminalViewController.m",
        "app/AppDelegate.m", "app/SceneDelegate.m", "app/FMLAB/GUIViewController+FMLAB.inc.m", "app/FMLAB/RuntimeBridge+FMLAB.inc.m",
        "app/FMLAB/Emulatore/FMLABEmulatore.m"]

def vero(s):  # testo come lo vede l'app (senza gli escape del sorgente Swift)
    return s.replace('\\"', '"').replace("\\\\", "\\")

# ---------- Swift ----------
CHIAMATE = re.compile(r'\b(Text|Label|Button|Section|Toggle|NavigationLink|navigationTitle|Picker|LabeledContentRow|'
                      r'DisclosureGroup|alert|confirmationDialog|LF|TextField|SecureField|ProgressView|GroupBox|Link|'
                      r'Stepper|Menu|valueRow|DetailRow|metric|row|statusRow)\(')

def leggi_stringa(s, i):
    """s[i] è '"'. Ritorna (fine, chiave, ha_valori). I valori \\(…) diventano il loro specifier o %@."""
    if s.startswith('"""', i):
        return None
    j, out, valori = i + 1, [], False
    while j < len(s):
        c = s[j]
        if c == "\\":
            if s[j + 1] == "(":
                prof, k, inizio = 1, j + 2, j + 2
                while prof:
                    ch = s[k]
                    if ch == '"':
                        k = leggi_stringa(s, k)[0]; continue
                    prof += ch == "("; prof -= ch == ")"; k += 1
                m = re.search(r'specifier:\s*"([^"]*)"', s[inizio:k - 1])
                out.append(m.group(1) if m else "%@"); valori = True; j = k; continue
            out.append(s[j:j + 2]); j += 2; continue
        if c == '"':
            return j + 1, "".join(out), valori
        out.append(c); j += 1
    return j, "".join(out), valori

def testi_primo_argomento(s, i):
    prof, j, res = 0, i, []
    while j < len(s):
        c = s[j]
        if c == '"':
            r = leggi_stringa(s, j)
            if r is None:
                break
            prima, dopo = s[:j].rstrip()[-1:], s[r[0]:].lstrip()[:1]
            if prima not in "[=" and dopo != "]":  # niente chiavi di dizionario
                res.append(r[1])
            j = r[0]; continue
        if c in "([{": prof += 1
        elif c in ")]}":
            if prof == 0: break
            prof -= 1
        elif c == "," and prof == 0: break
        j += 1
    return res

def chiavi_swift():
    chiavi = set()
    for f in sorted(f for g in SWIFT for f in glob.glob(g)):
        s = open(f, encoding="utf-8").read()
        for m in CHIAMATE.finditer(s):
            for k in testi_primo_argomento(s, m.end()):
                k = vero(k)
                if not k.strip() or not re.search(r"[A-Za-z]{2}", k):
                    continue
                if re.fullmatch(r"[a-z_]+|[A-Za-z]+[a-z][A-Z][A-Za-z]*", k):  # nomi interni (state, statusDetail)
                    continue
                chiavi.add(k)
        # messaggi messi in variabili e mostrati dopo con Text(LF(…)): installer.message = "…", error = "…"
        for m in re.finditer(r'\b(?:message|failure|error|status|stage)\s*=\s*(?=")', s):
            r = leggi_stringa(s, m.end())
            if r and not r[2] and re.search(r"[A-Za-z]{2}", r[1]):
                chiavi.add(vero(r[1]))
        for m in re.finditer(r'\bmetric\(', s):  # metric(valore, "etichetta"): conta il secondo argomento
            j, prof = m.end(), 0
            while j < len(s):
                if s[j] == '"': j = leggi_stringa(s, j)[0]; continue
                if s[j] in "([{": prof += 1
                elif s[j] in ")]}": prof -= 1
                elif s[j] == "," and prof == 0: break
                if prof < 0: break
                j += 1
            if j < len(s) and s[j] == ",":
                chiavi.update(vero(k) for k in testi_primo_argomento(s, j + 1) if k.strip())
    return chiavi

# ---------- Objective-C ----------
LIT = re.compile(r'@"((?:[^"\\]|\\.)*)"')
NON_UI = re.compile(r'(logCategory:|event:|desktopTrace:|result:|LRBootEvent\(|NSLog\(|accessibilityIdentifier\s*=|'
                    r'URLByAppendingPathComponent:|[Ff]orKey:|containsString:|hasPrefix:|isEqual:|isEqualToString:|'
                    r'rangeOfString:|PathComponent:|systemImageNamed:|NSSelectorFromString\(|Notification|desktopStartLog:|'
                    r'imageNamed:|pathForResource:|componentsSeparatedByString:|InfoDictionaryKey:)\s*$')
TECNICI = {
    # errori interni, registri e pulsanti di prova (nascosti nel desktop), lasciati com'è
    "Managed support directory is a symbolic link.", "Invalid bundled GUI support manifest.",
    "Invalid support-resource name.", "Bundled support checksum mismatch: %@", ". See GUI Logs for details.",
    "Metal failed; Core Graphics fallback: ", "Metal final framebuffer presentation selected; guest rendering unchanged",
    "Metal unavailable; Core Graphics fallback selected", "Core Graphics", "Install GUI Support", "Run X11 Test",
    "Run xterm", "Run xclock", "Install Qt Support", "Run Qt Test", "GPU Bridge Test", "Metal Gears", "GLES2 Gears",
    "GLES2 Textures", "GLES2 Targets", "GLX Metal Check", "GLX Metal App", "Mesa GL Check", "Hybrid Check",
    "Blender Software", "Blender Hybrid", "Install Browser Support", "Run LinuxRunner Browser", "Run Firefox",
    "Install GUI Support in this environment, then open xclock or xterm. Install Qt Support for the Qt test. DISPLAY and authentication are set automatically per session. Debian GUI/browser acceptance requires physical testing.",
    "Esc", "Tab", "Shift", "Ctrl", "Alt", "Super", "GUI_SESSION: starting X.Org",
    "LinuxRunner Open Desktop report\napp %@ (%@) source %@\niOS %@ %@\nattempt %@ created %@\n", "On My iPhone/app",
    "Metal Gears currently requires Debian ARM64", "GLES2 Gears currently requires Debian ARM64",
    "GLES2 texture checks require Debian ARM64", "GLES2 target checks require Debian ARM64",
    "These graphics checks require the Debian ARM64 profile",
    "The experimental GPU demo currently requires Debian ARM64 glibc. Alpine graphics and the existing Metal presenter remain available.",
    "\n\nError: FILESYSTEM_ERROR", "LINUXRUNNER_GLX must be off or software. Software GLX is Mesa rendering, not Metal acceleration.",
    "X11 / Xvfb", "runGPUGears2", "GUISupport", "iCloud",
    # rapporti diagnostici e nomi di file esportati: restano in inglese per chi li legge su GitHub
    "App bundle path", "Application Support", "Asbestos memory dispatch", "Boot is serialized on the main thread",
    "Bundled rootfs", "Bundled rootfs exists", "Counts are live tasks; no claim of precise sleeping/blocked state",
    "D-Bus", "KWin", "Plasma", "Device architecture", "Device diagnostics: %@\n", "Host page size",
    "Package path allocation failed", "Repository database is not UTF-8", "Package metadata mismatch",
    "Runtime container", "Runtime state", "Last startup milestone", "Last runtime error", "Host startup error",
    "Latest guest application failure", "Startup logs", "Writable rootfs path", "Writable rootfs exists",
    "Simulator sandbox, real host snapshots encoded as Linux link/address/route replies; no physical Wi-Fi transition",
    "This method needs to be called on the main thread", "[GPU] Metal GPU unavailable (%@); software rendering",
    "experimental fusion (Mac-tested, device-unverified)", "imageManifestSha256", "Window Manager", "Panel",
    "Application", "Windows", "LinuxRunner Device Diagnostics", "Task Manager sent %@ to pid %d (%@)",
    "LinuxRunner %@ (%@)\nLinuxRunner compatibility runtime; ARM64\nJIT: %@ · %@ (mode %@, debugger %@, blocks %@)\nGPU: %@ · %@ (mode %@)\n%@\n",
    "LinuxRunner-Diagnostics-%@.zip", "LinuxRunner-OpenDesktop-%@.txt", "LinuxRunner-check-%@-renamed.txt",
    "LinuxRunner-diagnostics-%@.txt", "Debian GNU/Linux", "ANGLE/Metal", "iCloud Drive", "^[A-Za-z_][A-Za-z0-9_]*$",
    "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789",
}

def objc_vero(s):
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), s)

def chiavi_objc():
    chiavi = set()
    for f in OBJC:
        s = open(f, encoding="utf-8").read()
        for m in LIT.finditer(s):
            k = objc_vero(m.group(1))
            if NON_UI.search(s[max(0, m.start() - 60):m.start()]) or not re.search(r"[A-Z][a-z]", k):
                continue
            if re.search(r"=\S|^/|\.sh$|^[A-Z_]+$|^LinuxRunner[A-Z]", k) or re.fullmatch(r"[A-Za-z]+[a-z][A-Z][A-Za-z]*", k):
                continue
            chiavi.add(k)
    return chiavi - TECNICI

# ---------- traduzioni ----------
tr = {vero(k): vero(v) for k, v in TR.items()}
tr.update(TR_OBJC)

mancano = sorted(k for k in chiavi_swift() | chiavi_objc() if k not in tr)
if mancano:
    print("Manca la traduzione italiana di:")
    for k in mancano:
        print("  -", repr(k)[:140])
    if "--controlla" in sys.argv:
        sys.exit(1)

# SwiftUI mette %lld per i numeri interi e %lf per i decimali: per ogni %@ si scrivono anche quelle varianti.
def varianti(k, v):
    n = k.count("%@")
    if n == 0 or n > 3 or v.count("%@") > n:
        return [(k, v)]
    out = []
    for scelta in itertools.product(["%@", "%lld", "%lf"], repeat=n):
        kk, vv = k, v
        for i, p in enumerate(scelta):
            kk = kk.replace("%@", "\0%d\0" % i, 1)
            vv = vv.replace("%@", "\0%d\0" % i, 1)
        for i, p in enumerate(scelta):
            kk = kk.replace("\0%d\0" % i, p); vv = vv.replace("\0%d\0" % i, p)
        out.append((kk, vv))
    return out

tutte = {}
for k, v in tr.items():
    for kk, vv in varianti(k, v):
        tutte.setdefault(kk, vv)

def esc(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")

os.makedirs("app/FMLAB/it.lproj", exist_ok=True)
with open("app/FMLAB/it.lproj/Localizable.strings", "w", encoding="utf-8") as out:
    out.write("/* FMLAB Linux, italiano. Generato da strumenti/genera_lingue.py: modifica strumenti/traduzioni_it.py */\n")
    for k in sorted(tutte):
        out.write(f'"{esc(k)}" = "{esc(tutte[k])}";\n')
print(f"it.lproj: {len(tr)} testi ({len(tutte)} con le varianti), {len(chiavi_swift())} Swift + "
      f"{len(chiavi_objc())} Objective-C controllati, {len(mancano)} senza traduzione")
