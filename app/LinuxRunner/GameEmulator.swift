import SwiftUI
import UIKit
import UniformTypeIdentifiers
import GameController
import CryptoKit

// MARK: - FMLAB Game Emulator
// Non fa parte di LinuxRunner e non usa Linux: i core libretro (dal progetto fmlab-retro) sono
// dentro l'app e girano nativi sull'iPhone, senza JIT. I giochi li mette l'utente nella cartella
// Giochi (app File › FMLAB Linux › Giochi) o con Importa. Nessun gioco incluso.

struct FMLABGioco: Identifiable, Hashable {
    var id: String { url.path }
    let url: URL
    let core: FMLABCore
    /// Cartella scelta dall'utente (fuori dall'app): va aperta con il permesso di iOS mentre si gioca.
    var cartella: URL? = nil
    var nomeCartella: String? = nil
    /// Su iCloud e non ancora scaricato sull'iPhone.
    var inDownload = false
    /// Icona del gioco (dentro i giochi DS) o copertina messa dall'utente accanto al gioco.
    var icona: UIImage? = nil
    var nome: String { url.deletingPathExtension().lastPathComponent }
    static func == (a: Self, b: Self) -> Bool { a.url == b.url && a.inDownload == b.inDownload }
    func hash(into h: inout Hasher) { h.combine(url) }
}

/// Cartelle di giochi scelte dall'utente (Sul mio iPhone, iCloud Drive, chiavetta…): l'app ricorda il permesso
/// di iOS (segnalibro) e legge i giochi da lì, senza copiarli.
struct FMLABCartellaGiochi: Codable, Identifiable, Hashable {
    var id = UUID()
    var nome: String
    var segnalibro: Data
    static let chiave = "FMLAB.cartelleGiochi"
    static func tutte() -> [Self] { (try? JSONDecoder().decode([Self].self, from: UserDefaults.standard.data(forKey: chiave) ?? Data())) ?? [] }
    static func salva(_ c: [Self]) { UserDefaults.standard.set(try? JSONEncoder().encode(c), forKey: chiave) }
    func url() -> URL? {
        var vecchio = false
        guard let u = try? URL(resolvingBookmarkData: segnalibro, options: [], relativeTo: nil, bookmarkDataIsStale: &vecchio) else { return nil }
        return u
    }
}

enum FMLABArchivioGiochi {
    /// Cerca i giochi in una cartella (fino a 4 livelli): solo i file che un emulatore apre, niente roba di Linux.
    static func cerca(in base: URL, cartella: URL?, nomeCartella: String?) -> [FMLABGioco] {
        var trovati: [FMLABGioco] = []
        let interna = cartella == nil
        let salta: Set<String> = ["BIOS", "Salvataggi", "Copertine", "Shared", ".linuxrunner"]
        guard let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsPackageDescendants]) else { return [] }
        for case let u as URL in e {
            if e.level > 4 { e.skipDescendants(); continue }
            let nome = u.lastPathComponent
            if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if (interna && e.level == 1 && salta.contains(nome)) || nome.hasPrefix(".") { e.skipDescendants() }
                continue
            }
            // iCloud: ".Gioco.nds.icloud" = c'è ma non è ancora sull'iPhone
            var vero = u, scaricare = false
            if nome.hasPrefix("."), nome.hasSuffix(".icloud") {
                vero = u.deletingLastPathComponent().appendingPathComponent(String(nome.dropFirst().dropLast(7)))
                scaricare = true
            } else if nome.hasPrefix(".") { continue }
            guard let c = FMLABEmulatore.core(per: vero.lastPathComponent) else { continue }
            let est = vero.pathExtension.lowercased()
            // le tracce .bin di un disco con .cue accanto non sono giochi a sé
            if est == "bin", (try? FileManager.default.contentsOfDirectory(atPath: vero.deletingLastPathComponent().path))?.contains(where: { $0.lowercased().hasSuffix(".cue") }) == true { continue }
            trovati.append(FMLABGioco(url: vero, core: c, cartella: cartella, nomeCartella: nomeCartella, inDownload: scaricare,
                                      icona: scaricare ? nil : FMLABIcona.per(vero, core: c.nome)))
        }
        return trovati
    }
}

/// Icone dei giochi: quella che i giochi DS hanno dentro (banner 32×32, 16 colori) oppure una copertina con lo
/// stesso nome del gioco (.png/.jpg) accanto al file o in Giochi/Copertine.
enum FMLABIcona {
    static func per(_ url: URL, core: String) -> UIImage? {
        let base = url.deletingPathExtension().lastPathComponent
        let posti = [url.deletingLastPathComponent(), FMLABEmulatore.cartellaGiochi().appendingPathComponent("Copertine")]
        for d in posti { for e in ["png", "jpg", "jpeg", "PNG", "JPG"] {
            let f = d.appendingPathComponent(base).appendingPathExtension(e)
            if let img = UIImage(contentsOfFile: f.path) { return img }
        } }
        return core == "desmume" ? ds(url) : nil
    }
    static func ds(_ url: URL) -> UIImage? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        func leggi(_ da: UInt64, _ n: Int) -> Data? { try? h.seek(toOffset: da); let d = h.readData(ofLength: n); return d.count == n ? d : nil }
        guard let testa = leggi(0x68, 4) else { return nil }
        let banner = UInt64(testa.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        guard banner > 0x200, let dati = leggi(banner, 0x240) else { return nil }
        let bitmap = dati.subdata(in: 0x20..<0x220), tavolozza = dati.subdata(in: 0x220..<0x240)
        var colori = [UInt32](repeating: 0, count: 16)
        for i in 0..<16 {
            let c = UInt16(tavolozza[i * 2]) | UInt16(tavolozza[i * 2 + 1]) << 8
            let r = UInt32(c & 31) * 255 / 31, g = UInt32((c >> 5) & 31) * 255 / 31, b = UInt32((c >> 10) & 31) * 255 / 31
            colori[i] = i == 0 ? 0 : (0xFF << 24) | (b << 16) | (g << 8) | r   // RGBA in memoria (little endian)
        }
        var px = [UInt32](repeating: 0, count: 32 * 32)
        for ty in 0..<4 { for tx in 0..<4 { for y in 0..<8 { for x in stride(from: 0, to: 8, by: 2) {
            let byte = bitmap[(ty * 4 + tx) * 32 + y * 4 + x / 2]
            let riga = (ty * 8 + y) * 32 + tx * 8 + x
            px[riga] = colori[Int(byte & 15)]; px[riga + 1] = colori[Int(byte >> 4)]
        } } } }
        guard px.contains(where: { $0 != 0 }) else { return nil }
        let dataPx = px.withUnsafeBytes { Data($0) }
        guard let prov = CGDataProvider(data: dataPx as CFData),
              let img = CGImage(width: 32, height: 32, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue), provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else { return nil }
        return UIImage(cgImage: img)
    }
}

/// Riquadro del gioco: l'icona vera se c'è, altrimenti il colore e la sigla della console.
struct FMLABRiquadroGioco: View {
    let gioco: FMLABGioco
    private var sigla: (String, Color) {
        switch gioco.core.nome {
        case "fceumm": return ("NES", Color(red: 0.75, green: 0.15, blue: 0.15))
        case "gambatte": return (gioco.url.pathExtension.lowercased() == "gbc" ? "GBC" : "GB", Color(red: 0.35, green: 0.45, blue: 0.25))
        case "mgba": return ("GBA", Color(red: 0.35, green: 0.25, blue: 0.6))
        case "bsnes": return ("SNES", Color(red: 0.45, green: 0.42, blue: 0.6))
        case "pcsx_rearmed": return ("PS1", Color(red: 0.3, green: 0.3, blue: 0.35))
        case "desmume": return ("DS", Color(red: 0.25, green: 0.4, blue: 0.6))
        default: return ("?", .gray)
        }
    }
    var body: some View {
        ZStack {
            if let img = gioco.icona {
                Image(uiImage: img).resizable().interpolation(img.size.width <= 64 ? .none : .medium).aspectRatio(contentMode: img.size.width <= 64 ? .fit : .fill)
            } else {
                sigla.1
                Text(sigla.0).font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundColor(.white).minimumScaleFactor(0.6)
            }
            if gioco.inDownload { Color.black.opacity(0.45); Image(systemName: "icloud.and.arrow.down").foregroundColor(.white) }
        }
        .frame(width: 48, height: 48)
        .background(Color(white: 0.15))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Dati del motore (fmlab-retro/dati/emulatore.json)
// Solo dati, niente codice: estensioni, opzioni dei core, BIOS controllati, avvisi. Si aggiornano da GitHub senza
// nuova versione dell'app; se la rete manca valgono l'ultima copia scaricata o quella scritta qui sotto.
enum FMLABDati {
    static let indirizzo = URL(string: "https://raw.githubusercontent.com/cipherdesk007-max/fmlab-retro/main/dati/emulatore.json")!
    private static let interno = #"{"schema":1,"versione":"2026.11.04-1","nota":"Dati del Game Emulator di FMLAB Linux: l'app li scarica da qui (niente codice, solo impostazioni). Gli emulatori veri sono nel disco core-<n>.","core":{"fceumm":{"estensioni":["nes","fds","unf","unif"],"opzioni":{"fceumm_aspect":"8:7 PAR"}},"gambatte":{"estensioni":["gb","gbc","dmg"],"opzioni":{}},"bsnes":{"estensioni":["sfc","smc","bs"],"opzioni":{}},"pcsx_rearmed":{"estensioni":["cue","pbp","chd","m3u","iso","img","bin"],"opzioni":{"pcsx_rearmed_drc":"disabled","pcsx_rearmed_frameskip":"0"}},"mgba":{"estensioni":["gba"],"opzioni":{"mgba_skip_bios":"ON"}},"desmume":{"estensioni":["nds"],"opzioni":{"desmume_cpu_mode":"interpreter","desmume_internal_resolution":"256x192","desmume_screens_layout":"top/bottom","desmume_pointer_type":"touch","desmume_frameskip":"0"}}},"bios":[{"core":"pcsx_rearmed","file":"scph5501.bin","md5":"490f666e1afb15b7362b406ed1cea246","it":"PlayStation (USA), facoltativo: senza, il BIOS è emulato","en":"PlayStation (USA), optional: without it the BIOS is emulated"},{"core":"pcsx_rearmed","file":"scph5502.bin","md5":"32736f17079d0b2b7024407c39bd3050","it":"PlayStation (Europa), facoltativo","en":"PlayStation (Europe), optional"},{"core":"pcsx_rearmed","file":"scph5500.bin","md5":"8dd7d5296a650fac7319bce665a6a53c","it":"PlayStation (Giappone), facoltativo","en":"PlayStation (Japan), optional"},{"core":"mgba","file":"gba_bios.bin","md5":"a860e8c0b6d573d191e4ec7db1b1e4f6","it":"Game Boy Advance, facoltativo","en":"Game Boy Advance, optional"}],"avviso":{"it":"","en":""}}"#
    private static var copia: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FMLAB", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("emulatore.json")
    }
    private(set) static var attuali: [String: Any] = [:]
    static var versione: String { attuali["versione"] as? String ?? "?" }
    static var bios: [[String: String]] { (attuali["bios"] as? [[String: Any]] ?? []).compactMap { $0 as? [String: String] } }
    static var avviso: String? {
        let a = attuali["avviso"] as? [String: String]; let t = a?[UserDefaults.standard.string(forKey: "FMLAB.lingua") == "it" ? "it" : "en"]
        return (t?.isEmpty == false) ? t : nil
    }

    /// Controlla un file di dati come fanno le prove di fmlab-retro: niente di strano passa all'emulatore.
    static func valido(_ data: Data) -> [String: Any]? {
        guard let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any], d["schema"] as? Int == 1,
              let v = d["versione"] as? String, v.range(of: #"^\d{4}\.\d\d\.\d\d-\d+$"#, options: .regularExpression) != nil,
              let core = d["core"] as? [String: [String: Any]] else { return nil }
        let noti: Set<String> = ["fceumm", "gambatte", "bsnes", "pcsx_rearmed", "mgba", "desmume"]
        for (n, c) in core {
            guard noti.contains(n), let e = c["estensioni"] as? [String], !e.isEmpty,
                  e.allSatisfy({ $0.range(of: #"^[a-z0-9]{1,5}$"#, options: .regularExpression) != nil }),
                  let o = c["opzioni"] as? [String: String], o.keys.allSatisfy({ $0.replacingOccurrences(of: "_", with: "").allSatisfy { $0.isLetter || $0.isNumber } }) else { return nil }
        }
        return d
    }
    private static func usa(_ d: [String: Any]) {
        attuali = d
        FMLABEmulatore.usaDati(d["core"] as? [String: [String: Any]] ?? [:])
    }
    /// All'avvio: la copia scaricata (se valida) o quella interna.
    static func carica() {
        if let d = (try? Data(contentsOf: copia)).flatMap(valido) { usa(d) }
        else if let d = valido(Data(interno.utf8)) { usa(d) }
    }
    /// Al massimo ogni 6 ore (o subito con forza): scarica, controlla e usa i dati nuovi.
    static func aggiorna(forza: Bool = false, fatto: (() -> Void)? = nil) {
        let chiave = "FMLAB.dati.ultimoControllo"
        if !forza, Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: chiave) < 6 * 3600 { return }
        var r = URLRequest(url: indirizzo, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.setValue("FMLAB-Linux", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: r) { data, risposta, _ in
            DispatchQueue.main.async {
                defer { fatto?() }
                guard (risposta as? HTTPURLResponse)?.statusCode == 200, let data, data.count < 512 * 1024, let d = valido(data) else { return }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: chiave)
                if (d["versione"] as? String) != versione { try? data.write(to: copia, options: .atomic); usa(d) }
            }
        }.resume()
    }
}

/// Ultimi giochi aperti (in cima all'elenco).
enum FMLABRecenti {
    static let chiave = "FMLAB.recenti"
    static var elenco: [String] { UserDefaults.standard.stringArray(forKey: chiave) ?? [] }
    static func aggiungi(_ g: FMLABGioco) {
        var e = elenco.filter { $0 != g.url.path }; e.insert(g.url.path, at: 0)
        UserDefaults.standard.set(Array(e.prefix(6)), forKey: chiave)
    }
}

/// Riga della sezione "Game Emulator" in Distribuzioni.
struct GameEmulatorRow: View {
    var body: some View {
        NavigationLink(destination: GameEmulatorView()) {
            HStack(spacing: 14) {
                Image(systemName: "gamecontroller.fill").font(.title2).foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Game Emulator").font(.headline)
                    Text(FMLABEmulatore.core().isEmpty ? LF("Emulators not included in this build") : FMLABEmulatore.core().map(\.console).joined(separator: " · "))
                        .font(.caption).foregroundColor(.secondary).lineLimit(2)
                }
            }.padding(.vertical, 6)
        }.accessibilityIdentifier("game-emulator")
    }
}

/// Modalità "Solo giochi": l'app si apre sul Game Emulator; il tasto Linux riporta al resto dell'app.
struct GameEmulatorSoloGiochi: View {
    @AppStorage("FMLAB.soloGiochi") private var soloGiochi = false
    var body: some View {
        NavigationView {
            GameEmulatorView(soloGiochi: true)
                .toolbar { ToolbarItem(placement: .navigationBarLeading) {
                    Button { soloGiochi = false } label: { Label("Linux", systemImage: "terminal") }.accessibilityIdentifier("torna-linux")
                } }
        }.navigationViewStyle(.stack)
    }
}

struct GameEmulatorView: View {
    var soloGiochi = false
    @AppStorage("FMLAB.soloGiochi") private var modoSoloGiochi = false
    @State private var giochi: [FMLABGioco] = []
    @State private var cartelle: [FMLABCartellaGiochi] = FMLABCartellaGiochi.tutte()
    @State private var inGioco: FMLABGioco?
    @State private var daTogliere: FMLABGioco?
    @State private var errore: String?
    @State private var cercando = false
    @State private var statoBIOS: [String: Bool] = [:]     // file -> impronta giusta
    @AppStorage("FMLAB.comandi.scala") private var scala = 1.0
    @AppStorage("FMLAB.comandi.opacita") private var opacita = 0.9
    @AppStorage("FMLAB.comandi.vibra") private var vibra = true
    @AppStorage("FMLAB.riprendi") private var riprendi = true

    private var perConsole: [(String, [FMLABGioco])] {
        let ordine = FMLABEmulatore.core().map(\.console)
        return Dictionary(grouping: giochi, by: { $0.core.console }).sorted { (ordine.firstIndex(of: $0.key) ?? 99) < (ordine.firstIndex(of: $1.key) ?? 99) }.map { ($0.key, $0.value.sorted { $0.nome.localizedStandardCompare($1.nome) == .orderedAscending }) }
    }

    var body: some View {
        List {
            if FMLABEmulatore.core().isEmpty {
                Section { Text("This build of FMLAB Linux has no emulators inside. Update the app from the latest release.").foregroundColor(.orange) }
            }
            if giochi.isEmpty && !cercando {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("No games yet", systemImage: "gamecontroller").font(.headline)
                        Text("Choose the folder where you keep your games (On My iPhone, iCloud Drive, a USB drive…): FMLAB reads them from there and sorts them by console. Or import single files, or put them in Files › FMLAB Linux › Giochi.").font(.callout).foregroundColor(.secondary)
                        Text("No games are included or downloaded by FMLAB: only use files you own or free homebrew.").font(.footnote).foregroundColor(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if let a = FMLABDati.avviso { Section { Label(a, systemImage: "info.circle").font(.callout) } }
            if cercando { Section { HStack(spacing: 12) { ProgressView(); Text("Looking for games…") } } }
            let recenti = FMLABRecenti.elenco.compactMap { p in giochi.first { $0.url.path == p } }
            if !recenti.isEmpty {
                Section("Recently Played") { ForEach(recenti) { riga($0) } }
            }
            ForEach(perConsole, id: \.0) { console, lista in
                Section(LF(console) + " · \(lista.count)") {
                    ForEach(lista) { gioco in
                        riga(gioco)
                        .swipeActions { if gioco.cartella == nil { Button(role: .destructive) { daTogliere = gioco } label: { Label("Delete", systemImage: "trash") } } }
                    }
                }
            }
            Section {
                ForEach(cartelle) { c in
                    Label(c.nome, systemImage: "folder").swipeActions { Button(role: .destructive) { togliCartella(c) } label: { Label("Remove", systemImage: "minus.circle") } }
                }
                Label("FMLAB Linux › Giochi", systemImage: "folder.badge.gearshape").foregroundColor(.secondary)
                Button { FMLABSceltaFile.apri(cartella: true) { aggiungiCartella($0.first) } } label: { Label("Choose Games Folder…", systemImage: "folder.badge.plus") }
                Button { FMLABSceltaFile.apri(cartella: false) { importaFile($0) } } label: { Label("Import Games…", systemImage: "square.and.arrow.down") }
            } header: { Text("Game Folders") } footer: {
                Text("Your folders stay where they are: FMLAB only reads them. Swipe left to remove a folder from the list (the files are not touched). DS games show their own icon; for the others put a picture with the same name next to the game (e.g. Zelda.png beside Zelda.sfc) or in Giochi/Copertine.")
            }
            Section {
                Picker("Controls Size", selection: $scala) { Text("Small").tag(0.85); Text("Normal").tag(1.0); Text("Large").tag(1.2) }
                VStack(alignment: .leading) { Text("Controls Opacity"); Slider(value: $opacita, in: 0.3...1) }
                Toggle("Vibration", isOn: $vibra)
                Toggle(isOn: $riprendi) { VStack(alignment: .leading, spacing: 3) { Text("Resume Where I Left Off"); Text("When you quit a game it is saved; next time you can continue from there.").font(.caption).foregroundColor(.secondary) } }
            } header: { Text("Controls and Saves") }
            if !FMLABDati.bios.isEmpty {
                Section {
                    ForEach(FMLABDati.bios, id: \.self) { b in
                        let nome = b["file"] ?? ""
                        HStack {
                            Image(systemName: statoBIOS[nome] == true ? "checkmark.seal.fill" : statoBIOS[nome] == false ? "exclamationmark.triangle.fill" : "circle.dashed")
                                .foregroundColor(statoBIOS[nome] == true ? .green : statoBIOS[nome] == false ? .orange : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(nome).font(.callout.monospaced())
                                Text(b[UserDefaults.standard.string(forKey: "FMLAB.lingua") == "it" ? "it" : "en"] ?? "").font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                } header: { Text("BIOS (optional)") } footer: {
                    Text("Put your own BIOS files in Files › FMLAB Linux › Giochi › BIOS. A green seal means the file is the right one (checked by its fingerprint); orange means a file with that name is there but it is different.")
                }
            }
            Section {
                Toggle(isOn: $modoSoloGiochi) { VStack(alignment: .leading, spacing: 3) { Text("Games Only"); Text("FMLAB Linux opens straight into the Game Emulator. The Linux button brings back everything else.").font(.caption).foregroundColor(.secondary) } }
                ForEach(FMLABEmulatore.core(), id: \.nome) { c in
                    HStack { Text(LF(c.console)); Spacer(); Text(c.estensioni.map { "." + $0 }.joined(separator: " ")).font(.caption).foregroundColor(.secondary).lineLimit(1) }
                }
            } header: { Text("Consoles") } footer: {
                Text(String(format: LF("Engine data %@ from fmlab-retro: updated by itself, without a new app."), FMLABDati.versione)) + Text("\n") + Text("Native emulators (libretro cores), no JIT needed. Saves go to Giochi/Salvataggi; BIOS files, if a console needs them, go to Giochi/BIOS. On-screen controls follow the rotation; game controllers and hardware keyboards work too.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Game Emulator")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Menu {
            Button { FMLABSceltaFile.apri(cartella: true) { aggiungiCartella($0.first) } } label: { Label("Choose Games Folder…", systemImage: "folder.badge.plus") }
            Button { FMLABSceltaFile.apri(cartella: false) { importaFile($0) } } label: { Label("Import Games…", systemImage: "square.and.arrow.down") }
        } label: { Image(systemName: "plus") }.accessibilityLabel(LF("Add Games")) } }
        .onAppear { aggiorna(); controllaBIOS(); FMLABDati.aggiorna { aggiorna() } }
        .refreshable { FMLABDati.aggiorna(forza: true) { aggiorna() }; aggiorna(); controllaBIOS() }
        .fullScreenCover(item: $inGioco) { gioco in FMLABGiocoSchermo(gioco: gioco).ignoresSafeArea() }
        .alert(String(format: LF("Delete %@?"), daTogliere?.nome ?? ""), isPresented: Binding(get: { daTogliere != nil }, set: { if !$0 { daTogliere = nil } })) {
            Button("Delete", role: .destructive) { if let g = daTogliere { try? FileManager.default.removeItem(at: g.url) }; daTogliere = nil; aggiorna() }
            Button("Cancel", role: .cancel) { daTogliere = nil }
        } message: { Text("The game file is deleted. Its saves in Giochi/Salvataggi are kept.") }
        .alert("Game Emulator", isPresented: Binding(get: { errore != nil }, set: { if !$0 { errore = nil } })) { Button("OK") { errore = nil } } message: { Text(errore ?? "") }
    }

    private func riga(_ gioco: FMLABGioco) -> some View {
        Button { apri(gioco) } label: {
            HStack(spacing: 12) {
                FMLABRiquadroGioco(gioco: gioco)
                VStack(alignment: .leading, spacing: 2) {
                    Text(gioco.nome).foregroundColor(.primary).lineLimit(2)
                    Text(gioco.inDownload ? LF("In iCloud: tap to download") : (gioco.nomeCartella ?? "FMLAB Linux › Giochi")).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Text(gioco.url.pathExtension.uppercased()).font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func controllaBIOS() {
        let elenco = FMLABDati.bios, cartella = FMLABEmulatore.cartellaBIOS()
        DispatchQueue.global(qos: .utility).async {
            var esito: [String: Bool] = [:]
            for b in elenco {
                guard let nome = b["file"], let atteso = b["md5"],
                      let d = try? Data(contentsOf: cartella.appendingPathComponent(nome), options: .mappedIfSafe) else { continue }
                esito[nome] = Insecure.MD5.hash(data: d).map { String(format: "%02x", $0) }.joined() == atteso
            }
            DispatchQueue.main.async { statoBIOS = esito }
        }
    }

    private func apri(_ gioco: FMLABGioco) {
        guard gioco.inDownload else { FMLABRecenti.aggiungi(gioco); inGioco = gioco; return }
        let accesso = gioco.cartella?.startAccessingSecurityScopedResource() ?? false
        defer { if accesso { gioco.cartella?.stopAccessingSecurityScopedResource() } }
        do { try FileManager.default.startDownloadingUbiquitousItem(at: gioco.url); errore = LF("Downloading from iCloud. Pull down to refresh in a moment.") }
        catch { errore = error.localizedDescription }
    }

    private func aggiungiCartella(_ u: URL?) {
        guard let u else { return }
        let accesso = u.startAccessingSecurityScopedResource(); defer { if accesso { u.stopAccessingSecurityScopedResource() } }
        guard let dati = try? u.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) else { errore = LF("FMLAB could not keep access to this folder."); return }
        cartelle.removeAll { $0.url()?.standardizedFileURL == u.standardizedFileURL }
        cartelle.append(FMLABCartellaGiochi(nome: u.lastPathComponent, segnalibro: dati))
        FMLABCartellaGiochi.salva(cartelle)
        aggiorna()
    }
    private func togliCartella(_ c: FMLABCartellaGiochi) { cartelle.removeAll { $0.id == c.id }; FMLABCartellaGiochi.salva(cartelle); aggiorna() }

    private func importaFile(_ urls: [URL]) {
        let base = FMLABEmulatore.cartellaGiochi()
        DispatchQueue.global(qos: .userInitiated).async {
            var scartati: [String] = []
            for u in urls {
                guard FMLABEmulatore.core(per: u.lastPathComponent) != nil else { scartati.append(u.lastPathComponent); continue }
                let dest = base.appendingPathComponent(u.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                // asCopy: iOS ci ha già dato una copia nostra, basta spostarla
                do { try FileManager.default.moveItem(at: u, to: dest) } catch {
                    do { try FileManager.default.copyItem(at: u, to: dest) } catch { DispatchQueue.main.async { errore = error.localizedDescription } }
                }
            }
            DispatchQueue.main.async {
                if !scartati.isEmpty { errore = String(format: LF("Not a supported game file (unzip it first): %@"), scartati.joined(separator: ", ")) }
                aggiorna()
            }
        }
    }

    private func aggiorna() {
        FMLABEmulatore.preparaCartelle()
        let elenco = cartelle
        cercando = true
        DispatchQueue.global(qos: .userInitiated).async {
            var tutti = FMLABArchivioGiochi.cerca(in: FMLABEmulatore.cartellaGiochi(), cartella: nil, nomeCartella: nil)
            for c in elenco {
                guard let u = c.url() else { continue }
                let accesso = u.startAccessingSecurityScopedResource(); defer { if accesso { u.stopAccessingSecurityScopedResource() } }
                tutti += FMLABArchivioGiochi.cerca(in: u, cartella: u, nomeCartella: c.nome)
            }
            var visti = Set<String>()
            tutti = tutti.filter { visti.insert($0.url.standardizedFileURL.path).inserted }
            DispatchQueue.main.async { giochi = tutti; cercando = false }
        }
    }
}

/// Selettore di iOS (file o cartella), presentato sopra quello che c'è a schermo.
/// Il .fileImporter di SwiftUI qui non funziona: più in alto nell'app ce n'è già un altro (file di Linux).
final class FMLABSceltaFile: NSObject, UIDocumentPickerDelegate {
    private static var attivo: FMLABSceltaFile?
    private let fatto: ([URL]) -> Void
    private init(_ fatto: @escaping ([URL]) -> Void) { self.fatto = fatto }
    static func apri(cartella: Bool, _ fatto: @escaping ([URL]) -> Void) {
        let scelta = FMLABSceltaFile(fatto); attivo = scelta
        let p = cartella ? UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
                         : UIDocumentPickerViewController(forOpeningContentTypes: [.data, .item], asCopy: true)
        p.allowsMultipleSelection = !cartella
        p.delegate = scelta
        guard var cima = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        while let sopra = cima.presentedViewController { cima = sopra }
        p.popoverPresentationController?.sourceView = cima.view
        cima.present(p, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { fatto(urls); Self.attivo = nil }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { Self.attivo = nil }
}

struct FMLABGiocoSchermo: UIViewControllerRepresentable {
    let gioco: FMLABGioco
    @Environment(\.dismiss) private var dismiss
    func makeUIViewController(context: Context) -> FMLABGiocoController { FMLABGiocoController(gioco: gioco) { dismiss() } }
    func updateUIViewController(_ c: FMLABGiocoController, context: Context) {}
}

// MARK: - Schermo di gioco: immagine + comandi che si adattano alla rotazione

final class FMLABGiocoController: UIViewController {
    private let gioco: FMLABGioco
    private let chiudi: () -> Void
    private var emulatore: FMLABEmulatore?
    private let pad = FMLABPad()
    private let avviso = UILabel()
    private var osservatori: [NSObjectProtocol] = []
    private var accessoCartella = false
    deinit { osservatori.forEach { NotificationCenter.default.removeObserver($0) } }

    init(gioco: FMLABGioco, chiudi: @escaping () -> Void) { self.gioco = gioco; self.chiudi = chiudi; super.init(nibName: nil, bundle: nil); modalPresentationStyle = .fullScreen }
    required init?(coder: NSCoder) { fatalError() }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .all }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        accessoCartella = gioco.cartella?.startAccessingSecurityScopedResource() ?? false
        do {
            let e = try FMLABEmulatore(conCore: gioco.core, gioco: gioco.url.path)
            emulatore = e
            view.addSubview(e.vista)
            pad.disposizione = e.disposizione
            pad.tasto = { [weak e] t, giu in e?.tasto(t, premuto: giu) }
        } catch {
            avviso.text = error.localizedDescription
        }
        pad.menu = { [weak self] in self?.apriMenu() }
        pad.veloce = { [weak self] attivo in self?.emulatore?.veloce = attivo }
        let controller: @Sendable (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.pad.soloMenu = !GCController.controllers().compactMap(\.extendedGamepad).isEmpty }
        }
        osservatori = [NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main, using: controller),
                       NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main, using: controller)]
        controller(Notification(name: .GCControllerDidConnect))
        view.addSubview(pad)
        avviso.textColor = .white; avviso.numberOfLines = 0; avviso.textAlignment = .center; avviso.font = .preferredFont(forTextStyle: .body)
        view.addSubview(avviso)
    }
    private var avviato = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !avviato else { return }; avviato = true
        guard let e = emulatore else { apriMenu(); return }
        let riprendi = UserDefaults.standard.object(forKey: "FMLAB.riprendi") as? Bool ?? true
        e.salvaUscita = riprendi
        guard riprendi, e.statoAutomaticoEsiste else { e.avvia(); return }
        let m = UIAlertController(title: gioco.nome, message: LF("Continue where you left off?"), preferredStyle: .alert)
        m.addAction(UIAlertAction(title: LF("Continue"), style: .default) { _ in e.avvia(); e.caricaAutomatico { _ in } })
        m.addAction(UIAlertAction(title: LF("Start Over"), style: .cancel) { _ in e.avvia() })
        present(m, animated: true)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); emulatore?.ferma()
        if accessoCartella { gioco.cartella?.stopAccessingSecurityScopedResource(); accessoCartella = false }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds, s = view.safeAreaLayoutGuide.layoutFrame
        let r = max(0.3, emulatore?.rapporto ?? 4.0 / 3.0)
        avviso.frame = s.insetBy(dx: 24, dy: 80)
        if b.height >= b.width {
            // verticale: gioco in alto, comandi sotto (come una console portatile)
            var w = s.width, h = w / r
            let massimo = s.height * (r < 1 ? 0.62 : 0.5)
            if h > massimo { h = massimo; w = h * r }
            let gioco = CGRect(x: s.midX - w / 2, y: s.minY + 8, width: w, height: h).integral
            emulatore?.vista.frame = gioco
            pad.modo = .verticale
            pad.frame = CGRect(x: 0, y: gioco.maxY, width: b.width, height: b.maxY - gioco.maxY)
            pad.areaSicura = UIEdgeInsets(top: 0, left: s.minX, bottom: b.maxY - s.maxY, right: b.maxX - s.maxX)
        } else {
            // orizzontale: gioco al centro a tutta altezza, comandi ai lati (sopra il gioco se lo spazio è poco)
            var h = s.height, w = h * r
            if w > s.width { w = s.width; h = w / r }
            emulatore?.vista.frame = CGRect(x: s.midX - w / 2, y: s.midY - h / 2, width: w, height: h).integral
            pad.modo = .orizzontale
            pad.frame = b
            pad.areaSicura = UIEdgeInsets(top: s.minY, left: s.minX, bottom: b.maxY - s.maxY, right: b.maxX - s.maxX)
            pad.spazioLato = (s.width - w) / 2
        }
        pad.setNeedsLayout()
    }

    private func apriMenu() {
        let e = emulatore
        e?.inPausa = true
        let m = UIAlertController(title: gioco.nome, message: e == nil ? avviso.text : nil, preferredStyle: .actionSheet)
        if let e {
            m.addAction(UIAlertAction(title: LF("Resume"), style: .default) { _ in e.inPausa = false })
            m.addAction(UIAlertAction(title: LF("Save State"), style: .default) { [weak self] _ in
                e.inPausa = false
                e.salvaStato { err in self?.mostra(err?.localizedDescription ?? LF("State saved")) }
            })
            let carica = UIAlertAction(title: LF("Load State"), style: .default) { [weak self] _ in
                e.inPausa = false
                e.caricaStato { err in self?.mostra(err?.localizedDescription ?? LF("State loaded")) }
            }
            carica.isEnabled = e.statoEsiste
            m.addAction(carica)
        }
        m.addAction(UIAlertAction(title: LF("Quit Game"), style: .destructive) { [weak self] _ in self?.emulatore?.ferma(); self?.chiudi() })
        if e != nil { m.addAction(UIAlertAction(title: LF("Cancel"), style: .cancel) { _ in e?.inPausa = false }) }
        m.popoverPresentationController?.sourceView = pad
        m.popoverPresentationController?.sourceRect = CGRect(x: pad.bounds.midX, y: pad.bounds.midY, width: 1, height: 1)
        present(m, animated: true)
    }
    private func mostra(_ testo: String) {
        let l = UILabel(); l.text = "  " + testo + "  "; l.textColor = .white; l.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        l.font = .preferredFont(forTextStyle: .callout); l.layer.cornerRadius = 10; l.clipsToBounds = true; l.sizeToFit()
        l.center = CGPoint(x: view.bounds.midX, y: view.safeAreaLayoutGuide.layoutFrame.minY + 30)
        view.addSubview(l)
        UIView.animate(withDuration: 0.3, delay: 1.6, options: []) { l.alpha = 0 } completion: { _ in l.removeFromSuperview() }
    }
}

// MARK: - Comandi a schermo (multi-tocco, croce a 8 direzioni)

final class FMLABPad: UIView {
    enum Modo { case verticale, orizzontale }
    var modo: Modo = .verticale { didSet { if modo != oldValue { setNeedsLayout() } } }
    var disposizione = 0 { didSet { costruisci() } }
    var areaSicura = UIEdgeInsets.zero
    var spazioLato: CGFloat = 0
    var tasto: ((FMLABTasto, Bool) -> Void)?
    var menu: (() -> Void)?
    var veloce: ((Bool) -> Void)?
    /// Con un controller collegato restano solo menu e avanti veloce.
    var soloMenu = false { didSet { setNeedsLayout() } }

    private struct Pulsante { let tasto: FMLABTasto?; let vista: UILabel }
    private var pulsanti: [Pulsante] = []
    private let croce = UIView()
    private let frecce = (0..<4).map { _ in UIImageView() }
    private let bottoneMenu = UIButton(type: .system)
    private let bottoneVeloce = UIButton(type: .system)
    private var premuti = Set<Int>()        // FMLABTasto.rawValue
    private let vibra = UIImpactFeedbackGenerator(style: .light)
    private let rosso = UIColor(red: 0.85, green: 0.27, blue: 0.27, alpha: 1)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        croce.isUserInteractionEnabled = false
        croce.layer.cornerRadius = 18
        addSubview(croce)
        for (i, nome) in ["chevron.up", "chevron.down", "chevron.left", "chevron.right"].enumerated() {
            frecce[i].image = UIImage(systemName: nome, withConfiguration: UIImage.SymbolConfiguration(weight: .bold)); frecce[i].tintColor = .white; frecce[i].contentMode = .scaleAspectFit
            croce.addSubview(frecce[i])
        }
        bottoneMenu.setImage(UIImage(systemName: "line.3.horizontal"), for: .normal)
        bottoneMenu.tintColor = .white
        bottoneMenu.backgroundColor = UIColor(white: 0.2, alpha: 0.8)
        bottoneMenu.accessibilityLabel = LF("Menu")
        bottoneMenu.addAction(UIAction { [weak self] _ in self?.menu?() }, for: .touchUpInside)
        addSubview(bottoneMenu)
        bottoneVeloce.setImage(UIImage(systemName: "forward.fill"), for: .normal)
        bottoneVeloce.tintColor = .white
        bottoneVeloce.backgroundColor = UIColor(white: 0.2, alpha: 0.8)
        bottoneVeloce.accessibilityLabel = LF("Fast Forward")
        bottoneVeloce.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.bottoneVeloce.isSelected.toggle()
            self.bottoneVeloce.tintColor = self.bottoneVeloce.isSelected ? self.rosso : .white
            self.veloce?(self.bottoneVeloce.isSelected)
        }, for: .touchUpInside)
        addSubview(bottoneVeloce)
        costruisci()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func costruisci() {
        pulsanti.forEach { $0.vista.removeFromSuperview() }
        var lista: [(FMLABTasto, String)] = [(.a, "A"), (.b, "B")]
        if disposizione >= 2 { lista += [(.x, "X"), (.y, "Y")] }
        if disposizione >= 1 { lista += [(.l, "L"), (.r, "R")] }
        lista += [(.select, "SELECT"), (.start, "START")]
        pulsanti = lista.map { t, testo in
            let l = UILabel(); l.text = testo; l.textAlignment = .center; l.textColor = .white
            l.font = .systemFont(ofSize: testo.count > 1 ? 11 : 22, weight: .bold)
            l.clipsToBounds = true; addSubview(l)
            return Pulsante(tasto: t, vista: l)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        // misura dei comandi in proporzione allo schermo: iPhone SE/mini, Pro Max, iPad (anche in Split View)
        let lato0 = min(window?.bounds.width ?? w, window?.bounds.height ?? h)
        let utente = UserDefaults.standard.object(forKey: "FMLAB.comandi.scala") as? Double ?? 1
        let opacita = CGFloat(UserDefaults.standard.object(forKey: "FMLAB.comandi.opacita") as? Double ?? 0.9)
        let k = min(max(lato0 / 390, 0.85), 1.5) * CGFloat(utente)
        let alfa: CGFloat = modo == .orizzontale && spazioLato < 150 * k ? opacita * 0.5 : opacita
        let fondo = UIColor(white: 0.22, alpha: alfa)
        let pillola = CGSize(width: 72 * k, height: 26 * k), spalla = CGSize(width: 76 * k, height: 30 * k), tondo = CGSize(width: 44 * k, height: 30 * k)
        var centroCroce: CGPoint, centroTasti: CGPoint, lato: CGFloat
        if modo == .verticale {
            let utile = CGRect(x: areaSicura.left, y: 0, width: w - areaSicura.left - areaSicura.right, height: h - areaSicura.bottom)
            lato = min(utile.width * 0.36, utile.height * 0.5, 170 * k)
            centroCroce = CGPoint(x: utile.minX + utile.width * 0.25, y: utile.minY + utile.height * 0.48)
            centroTasti = CGPoint(x: utile.minX + utile.width * 0.75, y: centroCroce.y)
            posa(.select, CGRect(x: utile.midX - pillola.width - 8, y: utile.maxY - pillola.height - 14, width: pillola.width, height: pillola.height), fondo)
            posa(.start, CGRect(x: utile.midX + 8, y: utile.maxY - pillola.height - 14, width: pillola.width, height: pillola.height), fondo)
            posa(.l, CGRect(x: utile.minX + 12, y: 10, width: spalla.width, height: spalla.height), fondo)
            posa(.r, CGRect(x: utile.maxX - 12 - spalla.width, y: 10, width: spalla.width, height: spalla.height), fondo)
            bottoneMenu.frame = CGRect(x: utile.midX - tondo.width - 5, y: 10, width: tondo.width, height: tondo.height)
            bottoneVeloce.frame = CGRect(x: utile.midX + 5, y: 10, width: tondo.width, height: tondo.height)
        } else {
            let sinistra = areaSicura.left, destra = w - areaSicura.right
            lato = min(max(spazioLato - 20, 120 * k), h * 0.42, 170 * k)
            let margine = max(spazioLato / 2, lato / 2 + 12)
            centroCroce = CGPoint(x: sinistra + margine, y: h * 0.62)
            centroTasti = CGPoint(x: destra - margine, y: h * 0.62)
            let alto = areaSicura.top + 12
            posa(.l, CGRect(x: sinistra + 12, y: alto, width: spalla.width, height: spalla.height), fondo)
            posa(.r, CGRect(x: destra - 12 - spalla.width, y: alto, width: spalla.width, height: spalla.height), fondo)
            posa(.select, CGRect(x: centroCroce.x - pillola.width / 2, y: h - areaSicura.bottom - pillola.height - 8, width: pillola.width, height: pillola.height), fondo)
            posa(.start, CGRect(x: centroTasti.x - pillola.width / 2, y: h - areaSicura.bottom - pillola.height - 8, width: pillola.width, height: pillola.height), fondo)
            // menu e avanti veloce in alto, accanto alle spalle (o al centro del lato se non ci sono L/R)
            let xMenu = disposizione >= 1 ? destra - 12 - spalla.width - 10 - tondo.width : centroTasti.x - tondo.width / 2
            bottoneMenu.frame = CGRect(x: xMenu, y: alto, width: tondo.width, height: tondo.height)
            let xVeloce = disposizione >= 1 ? sinistra + 12 + spalla.width + 10 : centroCroce.x - tondo.width / 2
            bottoneVeloce.frame = CGRect(x: xVeloce, y: alto, width: tondo.width, height: tondo.height)
        }
        for b in [bottoneMenu, bottoneVeloce] { b.layer.cornerRadius = 10 * k; b.alpha = alfa < 0.5 ? 0.6 : 1 }
        croce.isHidden = soloMenu
        pulsanti.forEach { $0.vista.isHidden = soloMenu; $0.vista.font = .systemFont(ofSize: ($0.vista.text?.count ?? 1) > 1 ? 11 * k : 22 * k, weight: .bold) }
        // croce
        croce.frame = CGRect(x: centroCroce.x - lato / 2, y: centroCroce.y - lato / 2, width: lato, height: lato)
        croce.backgroundColor = fondo
        croce.layer.cornerRadius = 18 * k
        let f = lato / 3
        frecce[0].frame = CGRect(x: f, y: 4, width: f, height: f - 8); frecce[1].frame = CGRect(x: f, y: lato - f + 4, width: f, height: f - 8)
        frecce[2].frame = CGRect(x: 4, y: f, width: f - 8, height: f); frecce[3].frame = CGRect(x: lato - f + 4, y: f, width: f - 8, height: f)
        // A B (X Y): a rombo come le console Nintendo
        let d = min(lato * 0.42, 74 * k), passo = lato * 0.34
        if disposizione >= 2 {
            posaTondo(.x, CGPoint(x: centroTasti.x, y: centroTasti.y - passo), d, fondo)
            posaTondo(.a, CGPoint(x: centroTasti.x + passo, y: centroTasti.y), d, fondo)
            posaTondo(.b, CGPoint(x: centroTasti.x, y: centroTasti.y + passo), d, fondo)
            posaTondo(.y, CGPoint(x: centroTasti.x - passo, y: centroTasti.y), d, fondo)
        } else {
            posaTondo(.a, CGPoint(x: centroTasti.x + passo * 0.75, y: centroTasti.y - passo * 0.45), d * 1.1, fondo)
            posaTondo(.b, CGPoint(x: centroTasti.x - passo * 0.75, y: centroTasti.y + passo * 0.45), d * 1.1, fondo)
        }
        colora()
    }
    private func vista(_ t: FMLABTasto) -> UILabel? { pulsanti.first { $0.tasto == t }?.vista }
    private func posa(_ t: FMLABTasto, _ r: CGRect, _ fondo: UIColor) { guard let v = vista(t) else { return }; v.frame = r; v.layer.cornerRadius = r.height / 2; v.backgroundColor = fondo }
    private func posaTondo(_ t: FMLABTasto, _ c: CGPoint, _ d: CGFloat, _ fondo: UIColor) { posa(t, CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d), fondo) }

    private func colora() {
        for p in pulsanti { guard let t = p.tasto else { continue }
            p.vista.layer.borderWidth = premuti.contains(t.rawValue) ? 0 : 1
            p.vista.layer.borderColor = UIColor(white: 1, alpha: 0.15).cgColor
            if premuti.contains(t.rawValue) { p.vista.backgroundColor = rosso } else if p.vista.backgroundColor == rosso { setNeedsLayout() }
        }
        for (i, t) in [FMLABTasto.su, .giu, .sinistra, .destra].enumerated() { frecce[i].tintColor = premuti.contains(t.rawValue) ? rosso : .white }
    }

    // Quali tasti tiene premuti un dito in quel punto (la croce dà fino a due direzioni: diagonali)
    private func tasti(in p: CGPoint) -> Set<Int> {
        if soloMenu { return [] }
        let c = croce.frame
        if c.insetBy(dx: -c.width * 0.25, dy: -c.height * 0.25).contains(p) {
            let dx = p.x - c.midX, dy = p.y - c.midY
            if hypot(dx, dy) < c.width * 0.12 { return [] }
            let a = atan2(-dy, dx) * 180 / .pi   // 0 = destra, 90 = su
            var s = Set<Int>()
            if a > 22.5 && a < 157.5 { s.insert(FMLABTasto.su.rawValue) }
            if a < -22.5 && a > -157.5 { s.insert(FMLABTasto.giu.rawValue) }
            if abs(a) > 112.5 { s.insert(FMLABTasto.sinistra.rawValue) }
            if abs(a) < 67.5 { s.insert(FMLABTasto.destra.rawValue) }
            return s
        }
        var migliore: (Int, CGFloat)?
        for b in pulsanti { guard let t = b.tasto else { continue }
            let r = b.vista.frame.insetBy(dx: -12, dy: -12)
            if r.contains(p) { let dist = hypot(p.x - r.midX, p.y - r.midY); if migliore == nil || dist < migliore!.1 { migliore = (t.rawValue, dist) } }
        }
        return migliore.map { [$0.0] } ?? []
    }
    private var tocchi: [ObjectIdentifier: Set<Int>] = [:]
    private func aggiornaTocchi(_ eventi: UIEvent?) {
        var nuovi = Set<Int>()
        for s in tocchi.values { nuovi.formUnion(s) }
        let giu = nuovi.subtracting(premuti), su = premuti.subtracting(nuovi)
        for t in giu { if let k = FMLABTasto(rawValue: t) { tasto?(k, true) } }
        for t in su { if let k = FMLABTasto(rawValue: t) { tasto?(k, false) } }
        if !giu.isEmpty, UserDefaults.standard.object(forKey: "FMLAB.comandi.vibra") as? Bool ?? true { vibra.impactOccurred() }
        premuti = nuovi
        if !giu.isEmpty || !su.isEmpty { colora() }
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // in orizzontale il pad è grande quanto lo schermo: i tocchi fuori dai comandi vanno al gioco (DS)
        if bottoneMenu.frame.contains(point) || bottoneVeloce.frame.contains(point) { return true }
        if soloMenu { return false }
        return !tasti(in: point).isEmpty || croce.frame.insetBy(dx: -30, dy: -30).contains(point)
    }
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { for x in t { tocchi[ObjectIdentifier(x)] = tasti(in: x.location(in: self)) }; aggiornaTocchi(e) }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { for x in t { tocchi[ObjectIdentifier(x)] = tasti(in: x.location(in: self)) }; aggiornaTocchi(e) }
    override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { for x in t { tocchi[ObjectIdentifier(x)] = nil }; aggiornaTocchi(e) }
    override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { for x in t { tocchi[ObjectIdentifier(x)] = nil }; aggiornaTocchi(e) }
}
