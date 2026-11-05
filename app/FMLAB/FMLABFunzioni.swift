// FMLAB Linux: le funzioni aggiunte da FMLAB a LinuxRunner (fuori da ManagerView.swift, così aggiornare la
// base LinuxRunner tocca meno codice nostro). Lingua, aggiornamenti dell'app, informazioni, RunnerKit, importazione
// delle distribuzioni da LinuxRunner, pulizia.
import SwiftUI
import UIKit
import AVKit
import AVFoundation

// MARK: - FMLAB: lingua
/// Testo tradotto (it.lproj) per le stringhe che non passano da Text("...")
func LF(_ s: String) -> String { NSLocalizedString(s, comment: "") }

// MARK: - FMLAB: aggiornamenti come in FMLAB Cleaner
// Il numero di versione e il file .ipa escono insieme nella pubblicazione "ultima" del repository: l'avviso compare
// solo quando il file nuovo è davvero pronto. Per installarlo non si scarica niente: si copia il link e
// LiveContainer lo installa sopra questa versione con "+ → Installa dall'URL" (i dati restano).
@MainActor
final class FMLABAggiornamenti: ObservableObject {
    static let repo = "https://github.com/cipherdesk007-max/fmlab-Linux-io"
    static let urlVersione = URL(string: repo + "/releases/download/ultima/VERSIONE.txt")!
    static let urlIpa = URL(string: repo + "/releases/download/ultima/FMLAB-Linux.ipa")!

    @Published var nuova: String?
    @Published var controllo = false
    @Published var esito: String?

    var attuale: String { Bundle.main.object(forInfoDictionaryKey: "FMLABVersion") as? String ?? "0.0.0" }
    /// Versione di LinuxRunner originale da cui parte questa FMLAB Linux
    var base: String { Bundle.main.object(forInfoDictionaryKey: "FMLABBaseLinuxRunner") as? String ?? "0.0.0" }
    /// Versione più nuova di LinuxRunner originale, se è uscita dopo la nostra base
    @Published var originaleNuova: String?

    func controllaOriginale() async {
        var r = URLRequest(url: URL(string: "https://api.github.com/repos/mxhm11cr/LinuxRunner/releases/latest")!)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.timeoutInterval = 15
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (dati, risposta) = try? await URLSession.shared.data(for: r),
              (risposta as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: dati) as? [String: Any],
              let tag = j["tag_name"] as? String else { return }
        let v = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
        originaleNuova = Self.piuNuova(v, di: base) ? v : nil
    }

    func controlla(manuale: Bool = false) async {
        controllo = true
        defer { controllo = false }
        var r = URLRequest(url: URL(string: Self.urlVersione.absoluteString + "?t=\(Int(Date().timeIntervalSince1970))")!)
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.timeoutInterval = 15
        guard let (dati, risposta) = try? await URLSession.shared.data(for: r),
              (risposta as? HTTPURLResponse)?.statusCode == 200,
              let v = String(data: dati, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              v.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else {
            if manuale { esito = LF("No connection to GitHub: try again later.") }
            return
        }
        if Self.piuNuova(v, di: attuale) { nuova = v; esito = nil }
        else { nuova = nil; if manuale { esito = String(format: LF("You already have the latest version (%@)."), attuale) } }
    }

    static func piuNuova(_ a: String, di b: String) -> Bool {
        let x = a.split(separator: ".").compactMap { Int($0) }, y = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }
}

struct FMLABAvvisoAggiornamento: View {
    @ObservedObject var agg: FMLABAggiornamenti
    @Environment(\.openURL) private var apri
    @State private var copiato = false

    var body: some View {
        if let v = agg.nuova {
            VStack(alignment: .leading, spacing: 10) {
                Label("FMLAB Linux \(v) available", systemImage: "arrow.down.circle.fill").font(.headline)
                Text(copiato
                     ? LF("Link copied. Now close FMLAB Linux, then in LiveContainer tap + → Install from URL → Paste → OK. It installs over this one; Linux and your data stay.")
                     : LF("No file to download: copy the link and install it from LiveContainer (+ → Install from URL)."))
                    .font(copiato ? .callout : .footnote).foregroundColor(copiato ? .primary : .secondary)
                Button {
                    UIPasteboard.general.string = FMLABAggiornamenti.urlIpa.absoluteString
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    copiato = true
                } label: {
                    Label(copiato ? LF("Link Copied") : LF("Copy Install Link"), systemImage: copiato ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Or download the .ipa file") { apri(FMLABAggiornamenti.urlIpa) }.font(.footnote)
            }
            .padding(.vertical, 4)
        }
    }
}

/// Riga per Impostazioni: versione FMLAB, controllo manuale e collegamenti al codice e alle segnalazioni.
struct FMLABInformazioni: View {
    @ObservedObject var agg: FMLABAggiornamenti
    @Environment(\.openURL) private var apri
    @AppStorage("FMLAB.lingua") private var lingua = "en"
    @State private var linguaCambiata = false

    var body: some View {
        Section {
            Picker(selection: $lingua) { Text("English").tag("en"); Text("Italiano").tag("it") } label: { Label("Language", systemImage: "globe") }
                .onChange(of: lingua) { nuova in UserDefaults.standard.set([nuova], forKey: "AppleLanguages"); linguaCambiata = true }
            if linguaCambiata {
                Text(lingua == "it" ? "Chiudi FMLAB Linux dal multitasking e riaprila per vederla in italiano."
                                    : "Close FMLAB Linux from the app switcher and reopen it to see it in English.")
                    .font(.footnote).foregroundColor(.orange)
            }
            HStack { Text("FMLAB Linux"); Spacer(); Text(agg.attuale).foregroundColor(.secondary) }
            Button(agg.controllo ? LF("Checking…") : LF("Check for Updates")) { Task { await agg.controlla(manuale: true) } }
                .disabled(agg.controllo)
            if let e = agg.esito { Text(e).font(.footnote).foregroundColor(.secondary) }
            FMLABAvvisoAggiornamento(agg: agg)
            HStack { Text("Based on LinuxRunner"); Spacer(); Text(agg.base).foregroundColor(.secondary) }
            if let o = agg.originaleNuova {
                Label("Original LinuxRunner is now at \(o): FMLAB Linux will catch up. When ready, it arrives here as an update.", systemImage: "sparkles")
                    .font(.footnote).foregroundColor(.orange)
            }
            Button("Source Code and Reports (GitHub)") { apri(URL(string: FMLABAggiornamenti.repo)!) }
            Button("Original LinuxRunner (Leminos)") { apri(URL(string: "https://github.com/mxhm11cr/LinuxRunner")!) }
        } header: { Text("FMLAB") } footer: {
            Text("FMLAB Linux is based on LinuxRunner by Leminos, derived from iSH and ios-linuxkit. GPL-3.0 license.")
        }
    }
}


// MARK: - FMLAB: RunnerKit già installato
// La prima volta che Debian è pronto, FMLAB Linux apre un terminale che installa FMlab - RunnerKit dal ramo
// "stabile" (lo stesso comando del README di RunnerKit). Un solo tentativo automatico per ambiente; poi c'è il pulsante.
enum FMLABRunnerKit {
    static let comando = "echo '== FMLAB Linux: installing FMlab - RunnerKit =='; " +
        "S=''; [ \"$(id -u)\" -ne 0 ] && S=sudo; " +
        "command -v curl >/dev/null 2>&1 || $S apt-get install -y curl || { $S apt-get update && $S apt-get install -y curl; }; " +
        "curl -fsSL https://raw.githubusercontent.com/cipherdesk007-max/FMlab---RunnerKit/stabile/install.sh | sh; " +
        "echo; echo 'Done. You can close this window.'; exec sh"

    /// `rk disinstalla` toglie tutto RunnerKit e rimette il sistema com'era (README di RunnerKit)
    static let comandoTogli = "if command -v rk >/dev/null 2>&1; then rk disinstalla; else echo 'RunnerKit is not installed.'; fi; " +
        "echo; echo 'Done. You can close this window.'; exec sh"
    /// Comando per il terminale dell'app (gli avviatori in modalità terminale)
    static func programma(_ comando: String) -> LinuxApplication {
        var a = LinuxApplication(name: "FMlab - RunnerKit", command: "/bin/sh", arguments: ["-c", comando])
        a.workingDirectory = "/"
        return a
    }
    private static func radice() -> URL { LRRuntimeBridge.rootURL(LRRuntimeBridge.activeRootName()) }
    static func installato() -> Bool {
        FileManager.default.fileExists(atPath: radice().appendingPathComponent("data/usr/local/bin/touchpad").path)
    }
    private static var chiave: String { "FMLAB.RunnerKit.tentato." + LRRuntimeBridge.activeRootName() }
    /// Debian configurato (prima configurazione finita), RunnerKit assente e mai provato in automatico
    static func daInstallareDaSolo() -> Bool {
        let pronto = FileManager.default.fileExists(atPath: radice().appendingPathComponent("data/var/lib/linuxrunner/initialized").path)
        return pronto && !installato() && !UserDefaults.standard.bool(forKey: chiave)
    }
    static func segnaTentativo() { UserDefaults.standard.set(true, forKey: chiave) }
}

// MARK: - FMLAB: prendere le distribuzioni già installate in LinuxRunner
// Dentro LiveContainer le app ospitate stanno nella stessa cartella di LiveContainer: FMLAB Linux trova i dati di
// LinuxRunner (contenitore dell'app o gruppo condiviso) e sposta o copia le sue distribuzioni nelle proprie.
// "Sposta" è istantaneo e non occupa spazio in più (stesso disco), ma LinuxRunner non le avrà più; "Copia" le lascia
// anche a LinuxRunner e occupa il doppio. Poi va chiusa e riaperta FMLAB Linux, che le legge all'avvio.
struct FMLABDistribuzioneTrovata: Identifiable {
    let id = UUID()
    let sorgente: URL        // cartella "LinuxRunner" (con roots/, exchanges/, environments.json)
    let nomeRadice: String   // nome della cartella in roots/
    let nome: String
    let ambiente: LinuxEnvironment?
    var byte: Int64
}

@MainActor
final class FMLABImporta: ObservableObject {
    @Published var trovati: [FMLABDistribuzioneTrovata] = []
    @Published var lavoro = false
    @Published var messaggio: String?

    nonisolated private static func contenitoriLinuxRunner() -> [URL] {
        guard let h = getenv("LC_HOME_PATH") else { return [] }
        let fm = FileManager.default
        let docs = URL(fileURLWithPath: String(cString: h)).appendingPathComponent("Documents")
        var basi: [URL] = []
        // dati delle app ospitate: Library/Application Support/LinuxRunner (quando il gruppo non c'è)
        for d in (try? fm.contentsOfDirectory(at: docs.appendingPathComponent("Data/Application"), includingPropertiesForKeys: nil)) ?? [] {
            basi.append(d.appendingPathComponent("Library/Application Support/LinuxRunner"))
        }
        // gruppi condivisi emulati da LiveContainer
        var gruppi = [docs.appendingPathComponent("Data/AppGroup")]
        let sel = NSSelectorFromString("lcAppGroupPath")
        if (UserDefaults.self as AnyObject).responds(to: sel),
           let p = (UserDefaults.self as AnyObject).perform(sel)?.takeUnretainedValue() as? String {
            gruppi.append(URL(fileURLWithPath: p).appendingPathComponent("LiveContainer/Data/AppGroup"))
        }
        for g in gruppi {
            for d in (try? fm.contentsOfDirectory(at: g, includingPropertiesForKeys: nil)) ?? []
            where d.lastPathComponent.lowercased().contains("linuxrunner") && !d.lastPathComponent.contains("fmlab") {
                basi.append(d)
            }
        }
        let mio = LRRuntimeBridge.catalogURL().deletingLastPathComponent().resolvingSymlinksInPath().path
        return basi.filter { fm.fileExists(atPath: $0.appendingPathComponent("roots").path) && $0.resolvingSymlinksInPath().path != mio }
    }

    // MARK: impostazioni di LinuxRunner (tema, terminale, mouse, grafica, audio, desktop…)
    @Published var impostazioniDisponibili = false
    static let chiaveImportate = "FMLAB.impostazioniLinuxRunnerImportate"

    /// File delle impostazioni di LinuxRunner dentro LiveContainer (Library/Preferences/dev.linuxrunner.app.plist)
    nonisolated static func fileImpostazioni() -> URL? {
        guard let h = getenv("LC_HOME_PATH") else { return nil }
        let fm = FileManager.default
        let app = URL(fileURLWithPath: String(cString: h)).appendingPathComponent("Documents/Data/Application")
        let candidati = ((try? fm.contentsOfDirectory(at: app, includingPropertiesForKeys: nil)) ?? [])
            .map { $0.appendingPathComponent("Library/Preferences/dev.linuxrunner.app.plist") }
            .filter { fm.fileExists(atPath: $0.path) }
        // se ce n'è più d'uno (contenitori vecchi), il più recente
        return candidati.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < db
        }
    }

    /// Copia le impostazioni di LinuxRunner in FMLAB Linux. Non tocca: impostazioni di sistema, quelle FMLAB, lo stato
    /// della procedura guidata e la distribuzione predefinita se qui non c'è. Restituisce quante ne ha prese.
    @discardableResult
    func importaImpostazioni() -> Int {
        guard let f = Self.fileImpostazioni(), let d = NSDictionary(contentsOf: f) as? [String: Any] else { return 0 }
        let escluse = ["Apple", "NS", "com.apple", "FMLAB", "LinuxRunnerSetup.", "WebKit", "LC", "lc", "PK", "MSV", "AK", "INNext"]
        let miei = Set(LRRuntimeBridge.rootNames())
        let ud = UserDefaults.standard
        var n = 0
        for (k, v) in d where !escluse.contains(where: { k.hasPrefix($0) }) {
            if k == "Default Root" {
                guard let r = v as? String, miei.contains(r) || FileManager.default.fileExists(atPath: LRRuntimeBridge.catalogURL().deletingLastPathComponent().appendingPathComponent("roots").appendingPathComponent(r).path) else { continue }
            }
            ud.set(v, forKey: k); n += 1
        }
        ud.set(true, forKey: Self.chiaveImportate)
        impostazioniDisponibili = false
        return n
    }

    func cerca() {
        impostazioniDisponibili = Self.fileImpostazioni() != nil && !UserDefaults.standard.bool(forKey: Self.chiaveImportate)
        let miei = Set(LRRuntimeBridge.rootNames())
        Task.detached(priority: .utility) {
            var out: [FMLABDistribuzioneTrovata] = []
            for base in Self.contenitoriLinuxRunner() {
                let catalogo = try? EnvironmentCatalog.read(base.appendingPathComponent("environments.json"))
                for r in (try? FileManager.default.contentsOfDirectory(atPath: base.appendingPathComponent("roots").path)) ?? []
                where !r.hasPrefix(".") && !miei.contains(r) {
                    let amb = catalogo?.environments.first { $0.rootfsName == r }
                    out.append(FMLABDistribuzioneTrovata(sorgente: base, nomeRadice: r, nome: amb?.name ?? amb?.distribution ?? r,
                                                         ambiente: amb, byte: Self.peso(base.appendingPathComponent("roots").appendingPathComponent(r))))
                }
            }
            await MainActor.run { self.trovati = out }
        }
    }

    nonisolated static func peso(_ u: URL) -> Int64 {
        var tot: Int64 = 0
        let k: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let e = FileManager.default.enumerator(at: u, includingPropertiesForKeys: k, options: [], errorHandler: { _, _ in true }) {
            for case let f as URL in e {
                if let v = try? f.resourceValues(forKeys: Set(k)), v.isRegularFile == true { tot += Int64(v.totalFileAllocatedSize ?? 0) }
            }
        }
        return tot
    }

    func prendi(_ t: FMLABDistribuzioneTrovata, sposta: Bool, manager: EnvironmentManager) {
        guard !lavoro else { return }
        lavoro = true; messaggio = sposta ? String(format: LF("Moving %@…"), t.nome) : String(format: LF("Copying %@… (may take a few minutes)"), t.nome)
        let mieRadici = LRRuntimeBridge.catalogURL().deletingLastPathComponent().appendingPathComponent("roots")
        let mieiScambi = LRRuntimeBridge.catalogURL().deletingLastPathComponent().appendingPathComponent("exchanges")
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var errore: String?
            do {
                try fm.createDirectory(at: mieRadici, withIntermediateDirectories: true)
                let da = t.sorgente.appendingPathComponent("roots").appendingPathComponent(t.nomeRadice)
                let a = mieRadici.appendingPathComponent(t.nomeRadice)
                if sposta { try fm.moveItem(at: da, to: a) } else { try fm.copyItem(at: da, to: a) }
                let sda = t.sorgente.appendingPathComponent("exchanges").appendingPathComponent(t.nomeRadice)
                if fm.fileExists(atPath: sda.path) {
                    try? fm.createDirectory(at: mieiScambi, withIntermediateDirectories: true)
                    let sa = mieiScambi.appendingPathComponent(t.nomeRadice)
                    if sposta { try? fm.moveItem(at: sda, to: sa) } else { try? fm.copyItem(at: sda, to: sa) }
                }
                if sposta, var cat = try? EnvironmentCatalog.read(t.sorgente.appendingPathComponent("environments.json")) {
                    cat.environments.removeAll { $0.rootfsName == t.nomeRadice }
                    try? cat.write(t.sorgente.appendingPathComponent("environments.json"))
                }
            } catch { errore = error.localizedDescription }
            await MainActor.run {
                self.lavoro = false
                if let errore { self.messaggio = String(format: LF("Failed: %@. Close LinuxRunner and try again."), errore); return }
                if let amb = t.ambiente, !manager.environments.contains(where: { $0.id == amb.id || $0.rootfsName == amb.rootfsName }) {
                    manager.environments.append(amb); try? manager.persist()
                }
                self.trovati.removeAll { $0.id == t.id }
                let n = self.importaImpostazioni()
                self.messaggio = String(format: LF(n > 0 ? "%@ is now in FMLAB Linux, with your LinuxRunner settings. Close FMLAB Linux from the app switcher and reopen it, then choose it in Distributions."
                                                       : "%@ is now in FMLAB Linux. Close FMLAB Linux from the app switcher and reopen it, then choose it in Distributions."), t.nome)
            }
        }
    }
}

extension FMLABImporta {
    /// Elimina una distribuzione rimasta nei file di LinuxRunner (es. dopo averlo tolto da LiveContainer, i suoi
    /// dati restano). Toglie radice e cartella di scambio e la voce nel suo elenco. FMLAB Linux non viene toccata.
    func elimina(_ t: FMLABDistribuzioneTrovata) {
        guard !lavoro else { return }
        lavoro = true; messaggio = String(format: LF("Deleting %@…"), t.nome)
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var errore: String?
            do {
                try fm.removeItem(at: t.sorgente.appendingPathComponent("roots").appendingPathComponent(t.nomeRadice))
                try? fm.removeItem(at: t.sorgente.appendingPathComponent("exchanges").appendingPathComponent(t.nomeRadice))
                if var cat = try? EnvironmentCatalog.read(t.sorgente.appendingPathComponent("environments.json")) {
                    cat.environments.removeAll { $0.rootfsName == t.nomeRadice }
                    try? cat.write(t.sorgente.appendingPathComponent("environments.json"))
                }
            } catch { errore = error.localizedDescription }
            await MainActor.run {
                self.lavoro = false
                if let errore { self.messaggio = String(format: LF("Failed: %@. Close LinuxRunner and try again."), errore); return }
                self.trovati.removeAll { $0.id == t.id }
                self.messaggio = String(format: LF("%@ deleted from LinuxRunner's files. Freed %@."), t.nome,
                                        ByteCountFormatter.string(fromByteCount: t.byte, countStyle: .file))
            }
        }
    }
}

struct FMLABImportaView: View {
    @ObservedObject var imp: FMLABImporta
    @ObservedObject var manager: EnvironmentManager
    @State private var scelta: FMLABDistribuzioneTrovata?

    var body: some View {
        if imp.lavoro { HStack { ProgressView(); Text(imp.messaggio ?? "") } }
        else if let m = imp.messaggio { Text(m).font(.footnote) }
        if !imp.trovati.isEmpty && !imp.lavoro {
            Text("These distributions are in LinuxRunner's files (they stay even after removing LinuxRunner). Tap one to take it here without reinstalling, or to delete it and free the space.")
                .font(.footnote).foregroundColor(.secondary)
        }
        if imp.impostazioniDisponibili && !imp.lavoro {
            Button {
                let n = imp.importaImpostazioni()
                imp.messaggio = n > 0 ? String(format: LF("Took %lld settings from LinuxRunner (theme, terminal, mouse, graphics, desktop…). Close and reopen FMLAB Linux to see them all."), n)
                                      : LF("No settings to take.")
            } label: { Label("Take Settings from LinuxRunner", systemImage: "slider.horizontal.3") }
        }
        ForEach(imp.trovati) { t in
            Button { scelta = t } label: {
                HStack {
                    Image(systemName: "shippingbox.fill")
                    VStack(alignment: .leading) { Text(t.nome); Text(ByteCountFormatter.string(fromByteCount: t.byte, countStyle: .file)).font(.caption).foregroundColor(.secondary) }
                    Spacer(); Image(systemName: "arrow.down.circle")
                }
            }.disabled(imp.lavoro)
        }
        .confirmationDialog("Take \(scelta?.nome ?? "") from LinuxRunner?", isPresented: Binding(get: { scelta != nil }, set: { if !$0 { scelta = nil } }), titleVisibility: .visible) {
            Button("Move (instant, no extra space)") { if let t = scelta { imp.prendi(t, sposta: true, manager: manager) } }
            Button("Copy (also stays in LinuxRunner)") { if let t = scelta { imp.prendi(t, sposta: false, manager: manager) } }
            Button(role: .destructive) { if let t = scelta { imp.elimina(t) } } label: { Text(String(format: LF("Delete It (frees %@)"), ByteCountFormatter.string(fromByteCount: scelta?.byte ?? 0, countStyle: .file))) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Move: the distribution goes to FMLAB Linux and LinuxRunner no longer has it. Copy: uses twice the space. Delete: removes it from LinuxRunner's files for good.") }
    }
}


// MARK: - FMLAB: pulizia dei file inutili
// Fuori da Linux: file temporanei di installazione non più in uso, cartella temporanea e cache dell'app (si ricreano
// da sole). Dentro Linux (Debian con RunnerKit): `pulizia --sicura`, che non tocca mai i file personali.
struct FMLABPulizia: View {
    var run: (LinuxApplication) -> Void
    @State private var conferma = false
    @State private var esito: String?
    @State private var lavoro = false

    var body: some View {
        Section {
            Button { conferma = true } label: { Label("Clean Up Unneeded Files", systemImage: "sparkles") }.disabled(lavoro)
            if LRRuntimeBridge.isRunning(), LRRuntimeBridge.activeEnvironmentIsDebian(), FMLABRunnerKit.installato() {
                Button { run(FMLABRunnerKit.programma("pulizia --sicura; echo; pulizia | head -40; echo; echo 'Done. You can close this window.'; exec sh")) } label: {
                    Label("Clean Up Inside Linux (RunnerKit)", systemImage: "trash.circle")
                }
            }
            if lavoro { ProgressView() }
            if let e = esito { Text(e).font(.footnote).foregroundColor(.green) }
        } header: { Text("Cleanup") } footer: {
            Text("Removes temporary installation files, the app's temporary folder and caches that rebuild themselves. Linux, your files, accounts and packages are never touched. Inside Linux, RunnerKit cleans apt caches, old logs and temporary files, never personal files.")
        }
        .confirmationDialog("Clean up unneeded files?", isPresented: $conferma, titleVisibility: .visible) {
            Button("Clean Up") { pulisci() }
        }
    }

    private func pulisci() {
        lavoro = true
        let staging = LRRuntimeBridge.managedStorageURL().appendingPathComponent("installer-temporary")
        let installa = UserDefaults.standard.bool(forKey: "InstallerActive")
        Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            var cartelle = [URL(fileURLWithPath: NSTemporaryDirectory())]
            if let c = fm.urls(for: .cachesDirectory, in: .userDomainMask).first { cartelle.append(c) }
            var liberati: Int64 = 0
            if !installa, fm.fileExists(atPath: staging.path) { liberati += FMLABImporta.peso(staging); try? fm.removeItem(at: staging) }
            for c in cartelle {
                for f in (try? fm.contentsOfDirectory(at: c, includingPropertiesForKeys: nil)) ?? [] {
                    let p = FMLABImporta.peso(f) + Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
                    if (try? fm.removeItem(at: f)) != nil { liberati += p }
                }
            }
            let testo = String(format: LF("Freed %@."), ByteCountFormatter.string(fromByteCount: liberati, countStyle: .file))
            await MainActor.run { esito = testo; lavoro = false }
        }
    }
}


// MARK: AirPlay: cerca le TV vicine senza uscire dall'app
/// Elenco di sistema dei dispositivi AirPlay (Apple TV, TV AirPlay, Mac). Sceglierne uno manda lì il suono;
/// l'immagine la manda solo Duplica schermo del Centro di Controllo (iOS non lascia avviarla a un'app).
final class FMLABAirPlay {
    private static let scelta: AVRoutePickerView = {
        let v = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        v.prioritizesVideoDevices = true
        return v
    }()
    /// Apre l'elenco da qualunque punto (menu del gioco, Impostazioni).
    static func apri(da vista: UIView) {
        let v = scelta
        if v.superview !== vista { v.removeFromSuperview(); v.alpha = 0.02; vista.addSubview(v) }
        for case let b as UIButton in v.subviews { b.sendActions(for: .touchUpInside); return }
    }
}
struct FMLABSceltaAirPlay: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView(); v.prioritizesVideoDevices = true
        v.tintColor = .clear; v.activeTintColor = .clear; v.backgroundColor = .clear
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
/// Riga "Cerca TV AirPlay…": tutta la riga apre l'elenco di sistema.
struct FMLABRigaAirPlay: View {
    var body: some View {
        ZStack {
            HStack { Label("Sound Only to AirPlay…", systemImage: "airplayaudio"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary) }
            FMLABSceltaAirPlay()
        }
    }
}


// MARK: Guida "Usa la TV": Duplica schermo (immagine) contro AirPlay del suono, con lo stato dal vivo
/// iOS lascia mandare l'immagine solo a Duplica schermo del Centro di Controllo (nessuna app può avviarla):
/// questa scheda lo spiega e si accorge da sola quando la duplicazione parte.
struct FMLABGuidaTV: View {
    var perGiochi = true
    var chiudi: (() -> Void)? = nil
    @State private var duplica = false
    @State private var suono = ""
    private let giro = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private func aggiorna() {
        duplica = UIScreen.screens.count > 1 || UIApplication.shared.connectedScenes.contains { ($0.session.role.rawValue).contains("ExternalDisplay") }
        suono = AVAudioSession.sharedInstance().currentRoute.outputs.map { $0.portName }.joined(separator: ", ")
    }
    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: duplica ? "checkmark.circle.fill" : "rectangle.on.rectangle").font(.title2).foregroundColor(duplica ? .green : .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(duplica ? "Screen Mirroring is on" : "Screen Mirroring is off").font(.headline)
                        Text(duplica ? (perGiochi ? "Open a game: the TV shows only the game, the iPhone is the controller." : "Open the Linux desktop: it goes on the TV.") : "The TV gets the picture only with Screen Mirroring.").font(.callout).foregroundColor(.secondary)
                    }
                }.padding(.vertical, 4)
                if !suono.isEmpty { HStack { Label("Sound", systemImage: "speaker.wave.2"); Spacer(); Text(suono).foregroundColor(.secondary) } }
            }
            if !duplica {
                Section {
                    Label("Swipe down from the top-right corner to open Control Center.", systemImage: "1.circle.fill")
                    Label("Tap Screen Mirroring: the two overlapping rectangles. If it is missing, hold on Control Center › + › Screen Mirroring.", systemImage: "2.circle.fill")
                    Label("Choose your Apple TV or AirPlay TV and come back here.", systemImage: "3.circle.fill")
                } header: { Text("Picture on the TV") } footer: {
                    Text("iOS does not let any app start Screen Mirroring by itself: it is only in Control Center. The iPhone and the TV must be on the same Wi-Fi. A USB-C/HDMI cable works too, with nothing to tap.")
                }
            }
            Section {
                FMLABRigaAirPlay()
            } footer: { Text("Sends only the sound (like music from Spotify): the picture stays on the iPhone.") }
        }
        .navigationTitle(perGiochi ? LF("Play on the TV") : LF("Linux Desktop on the TV"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { if let chiudi { Button("Done") { chiudi() } } } }
        .onAppear(perform: aggiorna)
        .onReceive(giro) { _ in aggiorna() }
    }
}
