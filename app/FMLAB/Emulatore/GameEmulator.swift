import SwiftUI
import Combine
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
    /// .zip/.7z/.rar: si estrae al momento di giocare (nella cache dell'app, l'archivio resta com'è).
    var archivio: Bool { ["zip", "7z", "rar"].contains(url.pathExtension.lowercased()) }
    /// Titolo vero letto dal gioco (DS: dal banner, nella lingua dell'app).
    var titolo: String? = nil
    var nomeFile: String { url.deletingPathExtension().lastPathComponent }
    /// Il nome che si vede: quello scelto dall'utente, se no il titolo del gioco, se no il nome del file.
    var nome: String { FMLABNomi.nome(per: url) ?? titolo ?? nomeFile }
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

/// Nomi scelti dall'utente (Rinomina): si salvano per nome di file, così valgono anche se la cartella cambia.
/// Il file non si tocca, e salvataggi e copertine restano legati al file.
enum FMLABNomi {
    static let chiave = "FMLAB.nomi"
    static func nome(per u: URL) -> String? { (UserDefaults.standard.dictionary(forKey: chiave) as? [String: String])?[u.lastPathComponent] }
    static func imposta(_ n: String?, per u: URL) {
        var d = (UserDefaults.standard.dictionary(forKey: chiave) as? [String: String]) ?? [:]
        let pulito = n?.trimmingCharacters(in: .whitespacesAndNewlines)
        d[u.lastPathComponent] = (pulito?.isEmpty == false) ? pulito : nil
        UserDefaults.standard.set(d, forKey: chiave)
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
            let est = vero.pathExtension.lowercased()
            let archivio = ["zip", "7z", "rar"].contains(est)
            guard let c = archivio ? (scaricare ? nil : FMLABEmulatore.core(dentroArchivio: vero.path)) : FMLABEmulatore.core(per: vero.lastPathComponent) else { continue }
            // le tracce .bin di un disco con .cue accanto non sono giochi a sé
            if est == "bin", (try? FileManager.default.contentsOfDirectory(atPath: vero.deletingLastPathComponent().path))?.contains(where: { $0.lowercased().hasSuffix(".cue") }) == true { continue }
            trovati.append(FMLABGioco(url: vero, core: c, cartella: cartella, nomeCartella: nomeCartella, inDownload: scaricare,
                                      icona: scaricare ? nil : FMLABIcona.per(vero, core: c.nome),
                                      titolo: scaricare || archivio ? nil : FMLABIcona.titolo(vero, core: c.nome)))
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
    /// Titolo del gioco: DS dal banner (italiano se l'app è in italiano, se no inglese), GBA e SNES dall'intestazione.
    static func titolo(_ url: URL, core: String) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        func leggi(_ da: UInt64, _ n: Int) -> Data? { try? h.seek(toOffset: da); let d = h.readData(ofLength: n); return d.count == n ? d : nil }
        func ascii(_ d: Data) -> String? {
            let t = String(decoding: d.filter { $0 >= 32 && $0 < 127 }, as: UTF8.self).trimmingCharacters(in: .whitespaces)
            return t.count >= 3 ? t.capitalized : nil
        }
        switch core {
        case "desmume":
            guard let testa = leggi(0x68, 4) else { return nil }
            let banner = UInt64(testa.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
            let lingua = UserDefaults.standard.string(forKey: "FMLAB.lingua") == "it" ? 4 : 1   // 1 inglese, 4 italiano
            guard banner > 0x200, let d = leggi(banner + 0x240 + UInt64(lingua) * 0x100, 0x100) else { return nil }
            let righe = (String(data: d, encoding: .utf16LittleEndian) ?? "").replacingOccurrences(of: "\0", with: "")
                .components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            // ultima riga = editore: si tiene il titolo (una o due righe)
            let t = (righe.count > 1 ? righe.dropLast() : righe[...]).joined(separator: " ")
            return t.isEmpty ? nil : t
        case "mgba": return leggi(0xA0, 12).flatMap(ascii)
        case "bsnes":
            let dim = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let base: UInt64 = dim % 1024 == 512 ? 512 : 0   // intestazione dei copiatori
            return leggi(base + 0x7FC0, 21).flatMap(ascii) ?? leggi(base + 0xFFC0, 21).flatMap(ascii)
        default: return nil
        }
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

/// Copertine automatiche dalla raccolta pubblica libretro-thumbnails (la stessa di RetroArch), cercate col nome del
/// file (funziona coi nomi standard No-Intro/Redump, es. "Super Mario World (USA)"). Si salvano in Giochi/Copertine;
/// un gioco senza copertina trovata non si ricerca più.
enum FMLABCopertine {
    static let chiaveAttive = "FMLAB.copertine.automatiche", chiaveMancanti = "FMLAB.copertine.mancanti"
    static var attive: Bool { UserDefaults.standard.object(forKey: chiaveAttive) as? Bool ?? true }
    static func sistema(_ g: FMLABGioco) -> String? {
        switch g.core.nome {
        case "fceumm": return "Nintendo_-_Nintendo_Entertainment_System"
        case "gambatte": return g.url.pathExtension.lowercased() == "gbc" ? "Nintendo_-_Game_Boy_Color" : "Nintendo_-_Game_Boy"
        case "mgba": return "Nintendo_-_Game_Boy_Advance"
        case "bsnes": return "Nintendo_-_Super_Nintendo_Entertainment_System"
        case "pcsx_rearmed": return "Sony_-_PlayStation"
        case "desmume": return "Nintendo_-_Nintendo_DS"
        default: return nil
        }
    }
    /// Cerca le copertine che mancano; chiama `fatto` se ne ha trovata almeno una.
    static func cerca(_ giochi: [FMLABGioco], fatto: @escaping () -> Void) {
        guard attive else { return }
        var mancanti = Set(UserDefaults.standard.stringArray(forKey: chiaveMancanti) ?? [])
        let cartella = FMLABEmulatore.cartellaGiochi().appendingPathComponent("Copertine")
        let daCercare = giochi.filter { $0.icona == nil && !$0.inDownload && !mancanti.contains($0.nome) }.prefix(24)
        guard !daCercare.isEmpty else { return }
        let gruppo = DispatchGroup(); var trovate = 0; let lock = NSLock()
        for g in daCercare {
            guard let sis = sistema(g) else { continue }
            // regola di libretro-thumbnails: questi caratteri diventano _
            let nome = String(g.nome.map { "&*/:`<>?\\|\"".contains($0) ? "_" : $0 })
            guard let n = nome.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let u = URL(string: "https://raw.githubusercontent.com/libretro-thumbnails/\(sis)/master/Named_Boxarts/\(n).png") else { continue }
            gruppo.enter()
            URLSession.shared.dataTask(with: u) { d, risposta, _ in
                defer { gruppo.leave() }
                lock.lock(); defer { lock.unlock() }
                if (risposta as? HTTPURLResponse)?.statusCode == 200, let d, UIImage(data: d) != nil {
                    try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
                    try? d.write(to: cartella.appendingPathComponent(g.nome).appendingPathExtension("png")); trovate += 1
                } else if (risposta as? HTTPURLResponse)?.statusCode == 404 { mancanti.insert(g.nome) }
            }.resume()
        }
        gruppo.notify(queue: .main) {
            UserDefaults.standard.set(Array(mancanti), forKey: chiaveMancanti)
            if trovate > 0 { fatto() }
        }
    }
}

/// Sigla e colore di ogni console (riquadri dei giochi senza icona e righe delle console).
func fmlabSigla(_ core: String, gbc: Bool = false) -> (String, Color) {
    switch core {
    case "fceumm": return ("NES", Color(red: 0.75, green: 0.15, blue: 0.15))
    case "gambatte": return (gbc ? "GBC" : "GB", Color(red: 0.35, green: 0.45, blue: 0.25))
    case "mgba": return ("GBA", Color(red: 0.35, green: 0.25, blue: 0.6))
    case "bsnes": return ("SNES", Color(red: 0.45, green: 0.42, blue: 0.6))
    case "pcsx_rearmed": return ("PS1", Color(red: 0.3, green: 0.3, blue: 0.35))
    case "desmume": return ("DS", Color(red: 0.25, green: 0.4, blue: 0.6))
    default: return ("?", .gray)
    }
}

/// Riquadro del gioco: l'icona vera se c'è, altrimenti il colore e la sigla della console.
struct FMLABRiquadroGioco: View {
    let gioco: FMLABGioco
    private var sigla: (String, Color) { fmlabSigla(gioco.core.nome, gbc: gioco.url.pathExtension.lowercased() == "gbc") }
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

/// Cosa sta facendo l'aggiornamento dei dati del motore, per la barra (Game Emulator e Distribuzioni).
final class FMLABStatoDati: ObservableObject {
    static let shared = FMLABStatoDati()
    enum Fase { case controllo, scarico, verifico, disponibili, applico, aggiornati, giaAggiornati, errore }
    @Published var fase: Fase?
    @Published var frazione: Double = 0
    private var chiudi: DispatchWorkItem?
    func imposta(_ f: Fase?, _ x: Double) {
        chiudi?.cancel(); fase = f; frazione = x
        if let f, [.aggiornati, .giaAggiornati, .errore, .disponibili].contains(f) {   // l'esito resta qualche secondo, poi la barra sparisce
            let w = DispatchWorkItem { [weak self] in self?.fase = nil }
            chiudi = w; DispatchQueue.main.asyncAfter(deadline: .now() + (f == .aggiornati ? 6 : 3), execute: w)
        }
    }
    var testo: String {
        switch fase {
        case .controllo: return LF("Checking engine data on fmlab-retro…")
        case .scarico: return LF("Downloading engine data…")
        case .verifico: return LF("Verifying engine data…")
        case .disponibili: return String(format: LF("New engine data found: %@"), FMLABDati.inAttesaVersione ?? "?")
        case .applico: return LF("Updating engine data and cleaning up…")
        case .aggiornati: return String(format: LF("Engine data updated: %@"), FMLABDati.versione)
        case .giaAggiornati: return String(format: LF("Engine data already up to date (%@)"), FMLABDati.versione)
        case .errore: return LF("Could not check engine data: using the saved copy")
        case nil: return ""
        }
    }
}

/// La barra: compare mentre controlla/scarica/verifica e mostra l'esito per qualche secondo.
struct FMLABBarraDati: View {
    @ObservedObject private var stato = FMLABStatoDati.shared
    var body: some View {
        if let f = stato.fase {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: f == .aggiornati || f == .giaAggiornati ? "checkmark.circle.fill" : f == .errore ? "exclamationmark.triangle.fill" : f == .disponibili ? "sparkles" : "arrow.down.circle")
                        .foregroundColor(f == .errore ? .orange : f == .aggiornati || f == .giaAggiornati ? .green : .accentColor)
                    Text(stato.testo).font(.caption.weight(.semibold)).lineLimit(2)
                }
                ProgressView(value: stato.frazione).tint(f == .errore ? .orange : f == .aggiornati || f == .giaAggiornati ? .green : .accentColor)
            }.padding(.vertical, 4).animation(.easeInOut(duration: 0.25), value: stato.frazione)
        }
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
    /// Dati nuovi già scaricati e controllati, in attesa del sì dell'utente.
    private static var attesa: URL { copia.deletingLastPathComponent().appendingPathComponent("emulatore.nuovo.json") }
    private static var datiInAttesa: [String: Any]? { (try? Data(contentsOf: attesa)).flatMap(valido) }
    static var inAttesaVersione: String? { datiInAttesa?["versione"] as? String }
    static var inAttesaNovita: String? {
        let t = (datiInAttesa?["novita"] as? [String: String])?[lingua]; return (t?.isEmpty == false) ? t : nil
    }
    /// Sì: usa i dati nuovi e pulisce quello che non serve più (copia in attesa, giochi estratti dagli archivi,
    /// copie di sicurezza temporanee). Dà quanto spazio ha liberato.
    @discardableResult static func applica() -> Int64 {
        guard let data = try? Data(contentsOf: attesa), let d = valido(data) else { try? FileManager.default.removeItem(at: attesa); return 0 }
        FMLABStatoDati.shared.imposta(.applico, 0.9)
        try? data.write(to: copia, options: .atomic); usa(d)
        try? FileManager.default.removeItem(at: attesa)
        UserDefaults.standard.set("nuovi", forKey: "FMLAB.dati.esito")
        UserDefaults.standard.set(versione, forKey: chiaveNuovi)
        let liberati = pulisci()
        FMLABStatoDati.shared.imposta(.aggiornati, 1)
        return liberati
    }
    /// File inutili del Game Emulator: estratti degli archivi nella cache, copie di sicurezza temporanee.
    static func pulisci() -> Int64 {
        let fm = FileManager.default; var liberati: Int64 = 0
        func peso(_ u: URL) -> Int64 {
            var t: Int64 = 0
            if let e = fm.enumerator(at: u, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) { for case let f as URL in e { t += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) } }
            return t + Int64((try? u.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        var via: [URL] = []
        if let c = fm.urls(for: .cachesDirectory, in: .userDomainMask).first { via.append(c.appendingPathComponent("FMLAB-Giochi")) }
        via += ((try? fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []).filter { $0.lastPathComponent.hasPrefix("FMLAB Game Emulator ") }
        for u in via where fm.fileExists(atPath: u.path) { let p = peso(u); if (try? fm.removeItem(at: u)) != nil { liberati += p } }
        UserDefaults.standard.removeObject(forKey: "FMLAB.copertine.mancanti")   // con dati nuovi si riprova a cercare le copertine
        return liberati
    }
    /// Ultimo controllo su GitHub e com'è andato (si vede nella sezione Console).
    static var ultimoControllo: Date? { let t = UserDefaults.standard.double(forKey: "FMLAB.dati.ultimoTentativo"); return t > 0 ? Date(timeIntervalSince1970: t) : nil }
    static var esito: String { UserDefaults.standard.string(forKey: "FMLAB.dati.esito") ?? "" }
    private static var lingua: String { UserDefaults.standard.string(forKey: "FMLAB.lingua") == "it" ? "it" : "en" }
    private static func testo(_ core: String, _ campo: String) -> String? {
        let c = (attuali["core"] as? [String: [String: Any]])?[core]
        let t = (c?[campo] as? [String: String])?[lingua]
        return (t?.isEmpty == false) ? t : nil
    }
    static func nome(_ core: FMLABCore) -> String { testo(core.nome, "nome") ?? LF(core.console) }
    static func nota(_ core: FMLABCore) -> String? { testo(core.nome, "nota") }
    static var versione: String { attuali["versione"] as? String ?? "?" }
    static var bios: [[String: String]] { (attuali["bios"] as? [[String: Any]] ?? []).compactMap { $0 as? [String: String] } }
    static var avviso: String? {
        let a = attuali["avviso"] as? [String: String]; let t = a?[lingua]
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
            for campo in ["nome", "nota"] where c[campo] != nil { guard c[campo] is [String: String] else { return nil } }
        }
        if d["novita"] != nil { guard d["novita"] is [String: String] else { return nil } }
        if d["urgente"] != nil { guard d["urgente"] is Bool else { return nil } }
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
    /// Novità dell'ultimo aggiornamento non ancora viste (versione), e il testo "cosa è cambiato".
    static let chiaveNuovi = "FMLAB.dati.novitaDaVedere"
    static var novita: String? {
        let t = (attuali["novita"] as? [String: String])?[lingua]
        return (t?.isEmpty == false) ? t : nil
    }
    /// All'apertura dell'app e del Game Emulator, al massimo ogni 10 minuti (o subito con forza):
    /// scarica, controlla e usa i dati nuovi. Il file è di pochi KB.
    static func aggiorna(forza: Bool = false, fatto: (() -> Void)? = nil) {
        let chiave = "FMLAB.dati.ultimoControllo"
        if !forza, Date().timeIntervalSince1970 - UserDefaults.standard.double(forKey: "FMLAB.dati.ultimoTentativo") < 2 * 60 { fatto?(); return }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "FMLAB.dati.ultimoTentativo")
        let stato = FMLABStatoDati.shared
        stato.imposta(.controllo, 0.1)
        var r = URLRequest(url: indirizzo, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        r.setValue("FMLAB-Linux", forHTTPHeaderField: "User-Agent")
        var osserva: NSKeyValueObservation?
        let compito = URLSession.shared.dataTask(with: r) { data, risposta, _ in
            DispatchQueue.main.async {
                osserva?.invalidate()
                defer { fatto?() }
                guard (risposta as? HTTPURLResponse)?.statusCode == 200, let data else {
                    UserDefaults.standard.set("rete", forKey: "FMLAB.dati.esito"); stato.imposta(.errore, 1); return
                }
                stato.imposta(.verifico, 0.85)
                guard data.count < 512 * 1024, let d = valido(data) else {
                    UserDefaults.standard.set("scartati", forKey: "FMLAB.dati.esito"); stato.imposta(.errore, 1); return
                }
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: chiave)
                if (d["versione"] as? String) != versione, d["urgente"] as? Bool == true {
                    // correzione grave (es. un'opzione che blocca un gioco): si applica subito e lo si dice
                    try? data.write(to: attesa, options: .atomic)
                    applica()
                    UserDefaults.standard.set("urgente", forKey: "FMLAB.dati.esito")
                } else if (d["versione"] as? String) != versione {
                    // non si cambia niente da soli: si tiene da parte e si chiede
                    try? data.write(to: attesa, options: .atomic)
                    UserDefaults.standard.set("disponibili", forKey: "FMLAB.dati.esito")
                    stato.imposta(.disponibili, 1)
                } else {
                    try? FileManager.default.removeItem(at: attesa)   // niente in attesa se è già quella in uso
                    UserDefaults.standard.set("uguali", forKey: "FMLAB.dati.esito")
                    stato.imposta(.giaAggiornati, 1)
                }
            }
        }
        // avanzamento vero del download (il file è piccolo: spesso va da 10% a 80% in un attimo)
        osserva = compito.progress.observe(\.fractionCompleted) { p, _ in
            DispatchQueue.main.async { if stato.fase == .controllo || stato.fase == .scarico { stato.imposta(.scarico, 0.1 + p.fractionCompleted * 0.7) } }
        }
        compito.resume()
    }
}

/// Copia di sicurezza del Game Emulator: una cartella con Salvataggi, BIOS, Copertine e impostazioni (niente giochi).
enum FMLABCopia {
    static let chiavi = ["FMLAB.comandi.scala", "FMLAB.comandi.opacita", "FMLAB.comandi.vibra", "FMLAB.riprendi", "FMLAB.soloGiochi"]
    static func esporta(_ errore: @escaping (String?) -> Void) {
        let fm = FileManager.default, base = FMLABEmulatore.cartellaGiochi()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm"
        let cartella = fm.temporaryDirectory.appendingPathComponent("FMLAB Game Emulator \(f.string(from: Date()))", isDirectory: true)
        try? fm.removeItem(at: cartella)
        do {
            try fm.createDirectory(at: cartella, withIntermediateDirectories: true)
            for n in ["Salvataggi", "BIOS", "Copertine"] where fm.fileExists(atPath: base.appendingPathComponent(n).path) {
                try fm.copyItem(at: base.appendingPathComponent(n), to: cartella.appendingPathComponent(n))
            }
            var imp: [String: Any] = [:]; for k in chiavi { imp[k] = UserDefaults.standard.object(forKey: k) }
            imp["FMLAB.recenti.nomi"] = FMLABRecenti.elenco.map { URL(fileURLWithPath: $0).lastPathComponent }
            let d = try JSONSerialization.data(withJSONObject: ["schema": 1, "impostazioni": imp], options: [.prettyPrinted, .sortedKeys])
            try d.write(to: cartella.appendingPathComponent("impostazioni.json"))
        } catch { errore(error.localizedDescription); return }
        let p = UIDocumentPickerViewController(forExporting: [cartella], asCopy: true)
        guard var cima = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        while let sopra = cima.presentedViewController { cima = sopra }
        cima.present(p, animated: true)
    }
    /// Rimette Salvataggi, BIOS e Copertine (i file con lo stesso nome vengono sostituiti) e le impostazioni.
    static func ripristina(da u: URL) -> String {
        let fm = FileManager.default, base = FMLABEmulatore.cartellaGiochi()
        let accesso = u.startAccessingSecurityScopedResource(); defer { if accesso { u.stopAccessingSecurityScopedResource() } }
        guard fm.fileExists(atPath: u.appendingPathComponent("impostazioni.json").path) else { return LF("This is not a Game Emulator backup folder.") }
        var n = 0
        for c in ["Salvataggi", "BIOS", "Copertine"] {
            let da = u.appendingPathComponent(c), a = base.appendingPathComponent(c)
            try? fm.createDirectory(at: a, withIntermediateDirectories: true)
            for f in (try? fm.contentsOfDirectory(atPath: da.path)) ?? [] where !f.hasPrefix(".") {
                try? fm.removeItem(at: a.appendingPathComponent(f))
                if (try? fm.copyItem(at: da.appendingPathComponent(f), to: a.appendingPathComponent(f))) != nil { n += 1 }
            }
        }
        if let d = try? Data(contentsOf: u.appendingPathComponent("impostazioni.json")),
           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let imp = j["impostazioni"] as? [String: Any] {
            for k in chiavi { if let v = imp[k] { UserDefaults.standard.set(v, forKey: k) } }
        }
        return String(format: LF("Backup restored: %ld files."), n)
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
    @State private var controllando = false
    @State private var estraendo: String?
    @State private var inAttesa: String? = FMLABDati.inAttesaVersione
    @State private var rimandato = false
    @Environment(\.scenePhase) private var fase
    @State private var versioneDati = FMLABDati.versione
    @AppStorage(FMLABDati.chiaveNuovi) private var nuovi = ""
    @ObservedObject private var stato = FMLABStatoDati.shared
    @AppStorage("FMLAB.comandi.scala") private var scala = 1.0
    @AppStorage("FMLAB.comandi.opacita") private var opacita = 0.9
    @AppStorage("FMLAB.comandi.vibra") private var vibra = true
    @AppStorage("FMLAB.riprendi") private var riprendi = true
    @AppStorage("FMLAB.veloce.velocita") private var velocita = 3.0
    @AppStorage("FMLAB.comandi.sopra") private var sopra = true
    @AppStorage("FMLAB.grafica.migliorata") private var graficaMigliorata = true
    @AppStorage("FMLAB.grafica.filtro") private var filtro = "netti"
    @AppStorage("FMLAB.giochi.esterno") private var usaEsterno = true
    @State private var schermoEsterno = FMLABGiocoController.nomeSchermoEsterno()
    @AppStorage(FMLABCopertine.chiaveAttive) private var copertine = true

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
                        Text("Choose the folder where you keep your games (On My iPhone, iCloud Drive, a USB drive…): FMLAB reads them from there and sorts them by console. Or import single files, or put them in Files › FMLAB Linux › Giochi. Zipped games (.zip, .7z, .rar) work as they are.").font(.callout).foregroundColor(.secondary)
                        Text("No games are included or downloaded by FMLAB: only use files you own or free homebrew.").font(.footnote).foregroundColor(.secondary)
                    }.padding(.vertical, 6)
                }
            }
            if let n = estraendo { Section { HStack(spacing: 12) { ProgressView(); Text(String(format: LF("Opening the archive of %@…"), n)) } } }
            if stato.fase != nil { Section { FMLABBarraDati() } }
            if let nuova = inAttesa, !rimandato {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(String(format: LF("Engine data update available: %@"), nuova), systemImage: "arrow.down.circle.fill").font(.callout.weight(.semibold))
                        if let n = FMLABDati.inAttesaNovita { Text(n).font(.callout) }
                        Text(String(format: LF("In use now: %@. Only settings, no code: nothing else changes. Old files that are no longer needed are cleaned up."), versioneDati)).font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 4)
                    Button { let l = FMLABDati.applica(); versioneDati = FMLABDati.versione; inAttesa = nil
                        if l > 0 { errore = String(format: LF("Engine data updated. Freed %@."), ByteCountFormatter.string(fromByteCount: l, countStyle: .file)) }
                        aggiorna() } label: { Label("Update Now", systemImage: "checkmark.circle") }
                    Button("Later") { rimandato = true }
                }
            }
            if !nuovi.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(String(format: LF("Engine data updated: %@"), nuovi), systemImage: "sparkles").font(.callout.weight(.semibold)).foregroundColor(.green)
                        if FMLABDati.esito == "urgente" { Text("Urgent fix: applied straight away without asking. Normal updates always ask first.").font(.caption).foregroundColor(.orange) }
                        if let n = FMLABDati.novita { Text(n).font(.callout) }
                        Text("Valid from the next game you open. Nothing to install.").font(.caption).foregroundColor(.secondary)
                    }.padding(.vertical, 4)
                    Button("OK") { nuovi = "" }
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
                            .contextMenu {
                                Button { rinomina(gioco) } label: { Label("Rename…", systemImage: "pencil") }
                                if FMLABNomi.nome(per: gioco.url) != nil { Button { FMLABNomi.imposta(nil, per: gioco.url); aggiorna() } label: { Label("Original Name", systemImage: "arrow.uturn.backward") } }
                                if gioco.cartella == nil { Button(role: .destructive) { daTogliere = gioco } label: { Label("Delete", systemImage: "trash") } }
                            }
                        .swipeActions {
                            if gioco.cartella == nil { Button(role: .destructive) { daTogliere = gioco } label: { Label("Delete", systemImage: "trash") } }
                            Button { rinomina(gioco) } label: { Label("Rename…", systemImage: "pencil") }.tint(.accentColor)
                        }
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
                Toggle(isOn: $sopra) { VStack(alignment: .leading, spacing: 3) { Text("Bigger Screen"); Text("The game takes all the space it can and the controls sit on top, see-through (above all on DS and in landscape).").font(.caption).foregroundColor(.secondary) } }
                Picker("Controls Size", selection: $scala) { Text("Small").tag(0.85); Text("Normal").tag(1.0); Text("Large").tag(1.2) }
                VStack(alignment: .leading) { Text("Controls Opacity"); Slider(value: $opacita, in: 0.3...1) }
                Toggle("Vibration", isOn: $vibra)
                Picker("Fast Forward Speed", selection: $velocita) { Text("2×").tag(2.0); Text("3×").tag(3.0); Text("4×").tag(4.0) }
                Toggle(isOn: $copertine) { VStack(alignment: .leading, spacing: 3) { Text("Automatic Covers"); Text("Box art from the public libretro-thumbnails collection, found by file name (standard names like \"Super Mario World (USA)\").").font(.caption).foregroundColor(.secondary) } }
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
                Toggle(isOn: $graficaMigliorata) { VStack(alignment: .leading, spacing: 3) { Text("Enhanced Graphics"); Text("DS 3D and PlayStation at double resolution, SNES Mode 7 in HD. Turn it off if a game slows down.").font(.caption).foregroundColor(.secondary) } }
                Picker("Picture", selection: $filtro) {
                    Text("Sharp Pixels").tag("netti"); Text("Smooth").tag("morbido"); Text("TV (scanlines)").tag("tv"); Text("Handheld LCD").tag("lcd")
                }
            } header: { Text("Graphics") } footer: { Text("Sharp Pixels is the most faithful; TV draws the lines of an old television, LCD the grid of a Game Boy screen. Valid from the next game you open.") }
            Section {
                Toggle("Use the External Screen for Games", isOn: $usaEsterno)
                HStack { Label("External screen", systemImage: "airplayvideo"); Spacer(); Text(schermoEsterno ?? LF("None")).foregroundColor(schermoEsterno == nil ? .secondary : .green) }
            } header: { Text("AirPlay and TV") } footer: {
                Text("Control Center › Screen Mirroring › your Apple TV or AirPlay TV (or a USB-C/HDMI cable). With a game open, it goes full screen on the TV and the iPhone becomes the controller (on DS the iPhone keeps the screens for touch). The Linux desktop has its own setting in Settings › Desktop.")
            }
            Section {
                Button { FMLABCopia.esporta { errore = $0 } } label: { Label("Export Backup…", systemImage: "square.and.arrow.up") }
                Button { FMLABSceltaFile.apri(cartella: true) { u in if let u = u.first { errore = FMLABCopia.ripristina(da: u); aggiorna(); controllaBIOS() } } } label: { Label("Restore Backup…", systemImage: "arrow.counterclockwise") }
            } header: { Text("Backup") } footer: {
                Text("A folder with your game saves, states, BIOS, covers and Game Emulator settings, to keep in Files or iCloud or to move to another iPhone. Games are not included.")
            }
            Section {
                Toggle(isOn: $modoSoloGiochi) { VStack(alignment: .leading, spacing: 3) { Text("Games Only"); Text("FMLAB Linux opens straight into the Game Emulator. The Linux button brings back everything else.").font(.caption).foregroundColor(.secondary) } }
            }
            Section {
                ForEach(FMLABEmulatore.core(), id: \.nome) { c in
                    let quanti = giochi.filter { $0.core.nome == c.nome }.count
                    HStack(spacing: 12) {
                        let sg = fmlabSigla(c.nome)
                        Text(sg.0).font(.system(size: 11, weight: .heavy, design: .rounded)).foregroundColor(.white).minimumScaleFactor(0.6)
                            .frame(width: 40, height: 40).background(sg.1).clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(FMLABDati.nome(c)).font(.callout.weight(.semibold)); Spacer(); Text(quanti == 1 ? LF("1 game") : String(format: LF("%ld games"), quanti)).font(.caption).foregroundColor(.secondary) }
                            if let n = FMLABDati.nota(c) { Text(n).font(.caption).foregroundColor(.secondary) }
                            Text(c.estensioni.map { "." + $0 }.joined(separator: " ")).font(.caption2.monospaced()).foregroundColor(.secondary).lineLimit(1)
                        }
                    }.padding(.vertical, 2)
                }
            } header: { Text("Consoles") } footer: {
                Text("Native emulators (libretro cores), no JIT needed. Saves go to Giochi/Salvataggi; BIOS files, if a console needs them, go to Giochi/BIOS. On-screen controls follow the rotation; game controllers and hardware keyboards work too.")
            }
            Section {
                HStack { Text("Version"); Spacer(); Text(versioneDati).font(.callout.monospaced()).foregroundColor(.secondary) }
                HStack {
                    Text("Last check"); Spacer()
                    Text(FMLABDati.ultimoControllo.map { DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short) } ?? LF("Never")).foregroundColor(.secondary)
                }
                if !FMLABDati.esito.isEmpty {
                    let e = FMLABDati.esito
                    Label(LF(e == "nuovi" ? "Updated from fmlab-retro" : e == "uguali" ? "Already up to date" : e == "disponibili" ? "New data ready: tap Update Now above" : e == "scartati" ? "The downloaded data was not valid and was ignored" : "No connection: using the saved copy"),
                          systemImage: e == "nuovi" || e == "uguali" ? "checkmark.circle.fill" : e == "disponibili" ? "sparkles" : "exclamationmark.triangle.fill")
                        .foregroundColor(e == "nuovi" || e == "uguali" ? .green : e == "disponibili" ? .accentColor : .orange).font(.callout)
                }
                Button {
                    controllando = true
                    rimandato = false
                    FMLABDati.aggiorna(forza: true) { controllando = false; inAttesa = FMLABDati.inAttesaVersione }
                } label: { HStack { Label("Check Now", systemImage: "arrow.triangle.2.circlepath"); if controllando { Spacer(); ProgressView() } } }.disabled(controllando)
            } header: { Text("Engine Data") } footer: {
                Text("Extensions, emulator options, BIOS list and notices come from fmlab-retro (dati/emulatore.json), without a new app: when there is something new FMLAB asks before using it, then cleans up files that are no longer needed. The emulators themselves arrive with app updates.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Game Emulator")
        .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Menu {
            Button { FMLABSceltaFile.apri(cartella: true) { aggiungiCartella($0.first) } } label: { Label("Choose Games Folder…", systemImage: "folder.badge.plus") }
            Button { FMLABSceltaFile.apri(cartella: false) { importaFile($0) } } label: { Label("Import Games…", systemImage: "square.and.arrow.down") }
        } label: { Image(systemName: "plus") }.accessibilityLabel(LF("Add Games")) } }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.didActivateNotification)) { _ in schermoEsterno = FMLABGiocoController.nomeSchermoEsterno() }
        .onReceive(NotificationCenter.default.publisher(for: UIScene.didDisconnectNotification)) { _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { schermoEsterno = FMLABGiocoController.nomeSchermoEsterno() } }
        .onAppear { schermoEsterno = FMLABGiocoController.nomeSchermoEsterno(); aggiorna(); controllaBIOS(); inAttesa = FMLABDati.inAttesaVersione; FMLABDati.aggiorna { inAttesa = FMLABDati.inAttesaVersione } }
        .onChange(of: fase) { f in if f == .active { FMLABDati.aggiorna { inAttesa = FMLABDati.inAttesaVersione } } }
        .refreshable { rimandato = false; FMLABDati.aggiorna(forza: true) { inAttesa = FMLABDati.inAttesaVersione }; aggiorna(); controllaBIOS() }
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
                    Text(gioco.inDownload ? LF("In iCloud: tap to download") : ((gioco.nome != gioco.nomeFile ? gioco.url.lastPathComponent + " · " : "") + (gioco.nomeCartella ?? "FMLAB Linux › Giochi"))).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                Text(gioco.url.pathExtension.uppercased()).font(.caption2).foregroundColor(.secondary)
            }
        }
    }

    private func rinomina(_ g: FMLABGioco) {
        let m = UIAlertController(title: LF("Rename"), message: String(format: LF("File: %@. The file is not changed: saves and covers stay linked to it."), g.url.lastPathComponent), preferredStyle: .alert)
        m.addTextField { $0.text = g.nome; $0.clearButtonMode = .always; $0.autocapitalizationType = .words }
        m.addAction(UIAlertAction(title: LF("Cancel"), style: .cancel))
        m.addAction(UIAlertAction(title: LF("Save"), style: .default) { _ in FMLABNomi.imposta(m.textFields?.first?.text, per: g.url); aggiorna() })
        guard var cima = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        while let sopra = cima.presentedViewController { cima = sopra }
        cima.present(m, animated: true)
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
        if !gioco.inDownload && gioco.archivio {
            FMLABRecenti.aggiungi(gioco); estraendo = gioco.nome
            DispatchQueue.global(qos: .userInitiated).async {
                let accesso = gioco.cartella?.startAccessingSecurityScopedResource() ?? false
                defer { if accesso { gioco.cartella?.stopAccessingSecurityScopedResource() } }
                let esito = Result { try FMLABEmulatore.prepara(archivio: gioco.url.path) }
                DispatchQueue.main.async {
                    estraendo = nil
                    switch esito {
                    case .success(let p): var g = gioco; g = FMLABGioco(url: URL(fileURLWithPath: p), core: FMLABEmulatore.core(per: p) ?? gioco.core, cartella: nil, nomeCartella: gioco.nomeCartella, inDownload: false, icona: gioco.icona); inGioco = g
                    case .failure(let e): errore = e.localizedDescription
                    }
                }
            }
            return
        }
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
                guard FMLABEmulatore.core(per: u.lastPathComponent) != nil || FMLABEmulatore.core(dentroArchivio: u.path) != nil else { scartati.append(u.lastPathComponent); continue }
                let dest = base.appendingPathComponent(u.lastPathComponent)
                try? FileManager.default.removeItem(at: dest)
                // asCopy: iOS ci ha già dato una copia nostra, basta spostarla
                do { try FileManager.default.moveItem(at: u, to: dest) } catch {
                    do { try FileManager.default.copyItem(at: u, to: dest) } catch { DispatchQueue.main.async { errore = error.localizedDescription } }
                }
            }
            DispatchQueue.main.async {
                if !scartati.isEmpty { errore = String(format: LF("Not a supported game file: %@"), scartati.joined(separator: ", ")) }
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
            DispatchQueue.main.async { giochi = tutti; cercando = false; FMLABCopertine.cerca(tutti) { aggiorna() } }
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
    private var scambiati = false            // DS: schermo di sotto sopra (o a sinistra)
    private let filtroVista = UIView()       // scanline / griglia LCD sopra l'immagine
    // DS in orizzontale: un'immagine sola (schermi uno sopra l'altro) divisa in due viste, così ognuno va dove serve
    private let secondoSchermo = UIView()
    private let toccoDS = FMLABToccoDS()
    private var giroDS: CADisplayLink?
    private var filtroPer: CGSize = .zero
    private var tenuto: FMLABTasto?          // "tieni premuto": un tasto sempre giù (es. correre)
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
        // grafica migliorata: opzioni dei core sopra a quelle dei dati (si possono spegnere nella scheda Giochi)
        let hd = UserDefaults.standard.object(forKey: "FMLAB.grafica.migliorata") as? Bool ?? true
        FMLABEmulatore.usaOpzioniUtente(hd ? ["desmume_internal_resolution": "512x384", "bsnes_mode7_scale": "2x",
                                              "pcsx_rearmed_neon_enhancement_enable": "enabled", "pcsx_rearmed_neon_enhancement_no_main": "enabled"] : [:])
        do {
            let e = try FMLABEmulatore(conCore: gioco.core, gioco: gioco.url.path)
            emulatore = e
            view.addSubview(e.vista)
            view.addSubview(filtroVista)
            filtroVista.isUserInteractionEnabled = false
            secondoSchermo.isUserInteractionEnabled = false; secondoSchermo.isHidden = true; secondoSchermo.backgroundColor = .black
            view.addSubview(secondoSchermo)
            toccoDS.emulatore = e; toccoDS.isHidden = true
            view.addSubview(toccoDS)
            pad.disposizione = e.disposizione
            pad.nomeCore = gioco.core.nome
            pad.tasto = { [weak e, weak self] t, giu in
                if !giu, t == self?.tenuto { return }   // il tasto "tenuto" resta giù anche se lo tocchi
                e?.tasto(t, premuto: giu)
            }
        } catch {
            avviso.text = error.localizedDescription
        }
        pad.menu = { [weak self] in self?.apriMenu() }
        pad.inModifica = { [weak self] attivo in
            self?.emulatore?.inPausa = attivo
            if !attivo { self?.mostra(LF("Buttons saved for this console")) }
        }
        pad.veloce = { [weak self] attivo in self?.emulatore?.veloce = attivo }
        let controller: @Sendable (Notification) -> Void = { [weak self] _ in
            DispatchQueue.main.async { self?.pad.soloMenu = !GCController.controllers().compactMap(\.extendedGamepad).isEmpty }
        }
        osservatori = [NotificationCenter.default.addObserver(forName: Notification.Name("FMLABMisuraGioco"), object: nil, queue: .main) { [weak self] _ in
                           self?.view.setNeedsLayout(); UIView.animate(withDuration: 0.2) { self?.view.layoutIfNeeded() } },
                       NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main, using: controller),
                       NotificationCenter.default.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main, using: controller)]
        controller(Notification(name: .GCControllerDidConnect))
        view.addSubview(pad)
        for nome in [UIScene.didActivateNotification, UIScene.didDisconnectNotification, UIScene.willConnectNotification] {
            osservatori.append(NotificationCenter.default.addObserver(forName: nome, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.collegaEsterno() } })
        }
        avviso.textColor = .white; avviso.numberOfLines = 0; avviso.textAlignment = .center; avviso.font = .preferredFont(forTextStyle: .body)
        view.addSubview(avviso)
    }
    private var avviato = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !avviato else { return }; avviato = true
        collegaEsterno()
        guard let e = emulatore else { apriMenu(); return }
        let riprendi = UserDefaults.standard.object(forKey: "FMLAB.riprendi") as? Bool ?? true
        e.salvaUscita = riprendi
        e.velocita = UserDefaults.standard.object(forKey: "FMLAB.veloce.velocita") as? Double ?? 3
        guard riprendi, e.statoAutomaticoEsiste else { e.avvia(); return }
        let m = UIAlertController(title: gioco.nome, message: LF("Continue where you left off?"), preferredStyle: .alert)
        m.addAction(UIAlertAction(title: LF("Continue"), style: .default) { _ in e.avvia(); e.caricaAutomatico { _ in } })
        m.addAction(UIAlertAction(title: LF("Start Over"), style: .cancel) { _ in e.avvia() })
        present(m, animated: true)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated); emulatore?.ferma(); staccaEsterno(); giroDS?.invalidate(); giroDS = nil
        if accessoCartella { gioco.cartella?.stopAccessingSecurityScopedResource(); accessoCartella = false }
    }

    // MARK: schermo esterno (AirPlay, monitor, TV): il gioco va lì, il telefono fa da controller
    private var esterno: UIView?
    private var specchio: CALayer?
    private var giroEsterno: CADisplayLink?
    private static func scenaEsterna() -> UIWindowScene? {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.session.role.rawValue.contains("ExternalDisplay") }
    }
    /// Nome dello schermo esterno collegato (AirPlay/cavo), per la scheda Giochi.
    static func nomeSchermoEsterno() -> String? {
        guard let s = scenaEsterna() else { return nil }
        let m = s.screen.bounds.size, k = s.screen.scale
        return String(format: LF("Connected · %.0f×%.0f"), m.width * k, m.height * k)
    }
    private func finestraEsterna() -> UIWindow? {
        guard UserDefaults.standard.object(forKey: "FMLAB.giochi.esterno") as? Bool ?? true else { return nil }
        return Self.scenaEsterna()?.windows.first
    }
    private func collegaEsterno() {
        guard emulatore != nil else { return }
        if let w = finestraEsterna() {
            if esterno == nil {
                let v = UIView(frame: w.bounds); v.backgroundColor = .black; v.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                let l = CALayer(); l.magnificationFilter = .nearest; l.contentsGravity = .resizeAspect; v.layer.addSublayer(l)
                w.addSubview(v); esterno = v; specchio = l
                let g = CADisplayLink(target: self, selector: #selector(copiaSuEsterno)); g.add(to: .main, forMode: .common); giroEsterno = g
                mostra(LF("Game on the external screen: the iPhone is the controller"))
            }
        } else { staccaEsterno() }
        view.setNeedsLayout()
    }
    private func staccaEsterno() {
        giroEsterno?.invalidate(); giroEsterno = nil
        esterno?.removeFromSuperview(); esterno = nil; specchio = nil
    }
    @objc private func copiaSuEsterno() {
        guard let e = esterno, let l = specchio, let v = emulatore?.vista else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        l.contents = v.layer.contents
        let r = max(0.3, emulatore?.rapporto ?? 4.0 / 3.0), b = e.bounds
        var w = b.width, h = w / r; if h > b.height { h = b.height; w = h * r }
        l.frame = CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
        CATransaction.commit()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds, s = view.safeAreaLayoutGuide.layoutFrame
        let sopra = UserDefaults.standard.object(forKey: "FMLAB.comandi.sopra") as? Bool ?? true
        let ds = emulatore?.tocco == true
        pad.sopra = false
        // con lo schermo esterno il gioco è lì: sul telefono solo i comandi, grandi (il DS tiene gli schermi per il tocco)
        if esterno != nil && !ds {
            emulatore?.vista.isHidden = true
            avviso.frame = .zero
            pad.modo = b.height >= b.width ? .verticale : .orizzontale
            pad.frame = b
            pad.areaSicura = UIEdgeInsets(top: s.minY, left: s.minX, bottom: b.maxY - s.maxY, right: b.maxX - s.maxX)
            pad.spazioLato = b.width / 3
            if pad.modo == .verticale { pad.frame = CGRect(x: 0, y: b.height * 0.25, width: b.width, height: b.height * 0.75) }
            pad.setNeedsLayout(); return
        }
        emulatore?.vista.isHidden = false
        let r = max(0.3, emulatore?.rapporto ?? 4.0 / 3.0)
        avviso.frame = s.insetBy(dx: 24, dy: 80)
        // Nintendo DS: il core dà sempre gli schermi uno sopra l'altro; in orizzontale l'app li divide
        if ds {
            let v = b.height >= b.width
            emulatore?.opzione("desmume_screens_layout", valore: v && scambiati ? "bottom/top" : "top/bottom")
            if !v { dsOrizzontale(b, s); return }
        }
        dividiDS(false)
        if b.height >= b.width {
            // verticale: gioco in alto, comandi sotto (come una console portatile)
            var w = s.width, h = w / r
            // DS: lo schermo di sotto si tocca, quindi i comandi non ci vanno mai sopra; si lascia loro il 30%
            let massimo = ds ? (b.height * 0.70 - s.minY - 8) : s.height * (r < 1 ? 0.7 : 0.5)
            if h > massimo { h = massimo; w = h * r }
            let gioco = CGRect(x: s.midX - w / 2, y: s.minY + 8, width: w, height: h).integral
            emulatore?.vista.frame = gioco
            pad.modo = .verticale
            // i comandi si prendono almeno un terzo dello schermo: se il gioco arriva lì, ci stanno sopra trasparenti
            let alto = ds ? gioco.maxY : min(gioco.maxY, b.maxY - b.height * 0.34)
            pad.frame = CGRect(x: 0, y: alto, width: b.width, height: b.maxY - alto)
            pad.sopra = gioco.maxY > alto + 1 && sopra
            pad.areaSicura = UIEdgeInsets(top: 0, left: s.minX, bottom: b.maxY - s.maxY, right: b.maxX - s.maxX)
        } else {
            // orizzontale: gioco al centro a tutta altezza, comandi ai lati (sopra il gioco se lo spazio è poco)
            var h = s.height, w = h * r
            // DS affiancati: ai lati resta lo spazio giusto per croce e tasti, così non coprono gli schermi
            // DS affiancati: lo schermo di destra si tocca, i comandi restano ai lati e non lo coprono
            let laterale: CGFloat = ds ? 128 : 0
            if w > s.width - 2 * laterale { w = s.width - 2 * laterale; h = w / r }
            emulatore?.vista.frame = CGRect(x: s.midX - w / 2, y: s.midY - h / 2, width: w, height: h).integral
            pad.modo = .orizzontale
            pad.frame = b
            pad.areaSicura = UIEdgeInsets(top: s.minY, left: s.minX, bottom: b.maxY - s.maxY, right: b.maxX - s.maxX)
            pad.spazioLato = (s.width - w) / 2
        }
        pad.chiavePosizioni = "FMLAB.tasti.\(gioco.core.nome).\(b.height >= b.width ? "v" : "o")"
        aggiornaFiltro()
        pad.setNeedsLayout()
    }

    /// Disposizione DS in orizzontale (menu del gioco › Schermi DS):
    /// "grande" = schermo principale a tutta altezza e l'altro più piccolo accanto; "affiancati" = uguali, da bordo a bordo.
    private var modoDS: String { UserDefaults.standard.string(forKey: "FMLAB.ds.orizzontale") ?? "grande" }
    private func dsOrizzontale(_ b: CGRect, _ s: CGRect) {
        guard let e = emulatore else { return }
        dividiDS(true)
        let q: CGFloat = 4.0 / 3.0, m: CGFloat = 6
        var grande: CGRect, piccolo: CGRect
        if modoDS == "affiancati" {
            let w = (s.width - m) / 2, h = min(s.height, w / q), ww = h * q
            let y = s.midY - h / 2, x0 = s.midX - ww - m / 2
            grande = CGRect(x: x0, y: y, width: ww, height: h); piccolo = CGRect(x: s.midX + m / 2, y: y, width: ww, height: h)
        } else {
            // principale a tutta altezza; l'altro nello spazio che resta a destra (in alto, sotto L/R: sotto ci vanno i tasti)
            var h = s.height, w = h * q
            let restoMin: CGFloat = min(220, s.width * 0.3)
            if s.width - w < restoMin { w = s.width - restoMin; h = w / q }
            grande = CGRect(x: s.minX, y: s.midY - h / 2, width: w, height: h)
            let pw = s.maxX - grande.maxX - m, ph = pw / q
            piccolo = CGRect(x: grande.maxX + m, y: max(s.minY + 52, s.midY - ph / 2 - ph * 0.35), width: pw, height: ph)
        }
        // "Scambia gli schermi": il touch va in grande
        let alto = scambiati ? piccolo : grande, basso = scambiati ? grande : piccolo
        e.vista.frame = alto.integral
        secondoSchermo.frame = basso.integral
        toccoDS.frame = basso.integral
        pad.modo = .orizzontale
        pad.frame = b
        pad.areaSicura = UIEdgeInsets(top: s.minY, left: s.minX, bottom: b.maxY - s.maxY, right: b.maxX - s.maxX)
        pad.spazioLato = max(0, grande.minX - s.minX)
        pad.sopra = true
        pad.chiavePosizioni = "FMLAB.tasti.\(gioco.core.nome).o.\(modoDS)"
        aggiornaFiltro()
        pad.setNeedsLayout()
    }
    private func dividiDS(_ attivo: Bool) {
        guard let v = emulatore?.vista else { return }
        v.layer.contentsRect = attivo ? CGRect(x: 0, y: 0, width: 1, height: 0.5) : CGRect(x: 0, y: 0, width: 1, height: 1)
        v.isUserInteractionEnabled = !attivo          // il tocco lo prende toccoDS, sopra lo schermo di sotto
        secondoSchermo.isHidden = !attivo; toccoDS.isHidden = !attivo
        secondoSchermo.layer.contentsRect = CGRect(x: 0, y: 0.5, width: 1, height: 0.5)
        secondoSchermo.layer.magnificationFilter = v.layer.magnificationFilter
        if attivo, giroDS == nil {
            let g = CADisplayLink(target: FMLABDebole(self), selector: #selector(FMLABDebole.giro)); g.add(to: .main, forMode: .common); giroDS = g
        } else if !attivo { giroDS?.invalidate(); giroDS = nil }
    }
    @objc fileprivate func copiaSecondo() {
        guard let v = emulatore?.vista, v.layer.contents != nil else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        secondoSchermo.layer.contents = v.layer.contents
        CATransaction.commit()
    }

    /// Filtri dell'immagine: pixel netti, morbido, scanline da TV, griglia LCD (allineati ai pixel del gioco).
    private func aggiornaFiltro() {
        guard let e = emulatore else { return }
        let f = UserDefaults.standard.string(forKey: "FMLAB.grafica.filtro") ?? "netti"
        e.vista.layer.magnificationFilter = f == "morbido" ? .linear : .nearest
        secondoSchermo.layer.magnificationFilter = e.vista.layer.magnificationFilter
        filtroVista.frame = e.vista.frame
        let m = e.misuraImmagine
        guard (f == "tv" || f == "lcd"), m.width > 0, m.height > 0, e.vista.bounds.height > 0 else { filtroVista.backgroundColor = .clear; return }
        let divisa = !secondoSchermo.isHidden
        let px = e.vista.bounds.height / (divisa ? m.height / 2 : m.height), py = px
        let chiave = CGSize(width: px * (f == "lcd" ? 1 : 0), height: py)
        if chiave == filtroPer { return }
        filtroPer = chiave
        let scala = UIScreen.main.scale
        let cella = CGSize(width: f == "lcd" ? max(1, px) : 1, height: max(1, py))
        let img = UIGraphicsImageRenderer(size: cella).image { c in
            UIColor(white: 0, alpha: f == "tv" ? 0.32 : 0.22).setFill()
            let riga = max(1 / scala, cella.height * (f == "tv" ? 0.4 : 0.18))
            c.fill(CGRect(x: 0, y: cella.height - riga, width: cella.width, height: riga))
            if f == "lcd" { c.fill(CGRect(x: cella.width - max(1 / scala, cella.width * 0.18), y: 0, width: max(1 / scala, cella.width * 0.18), height: cella.height)) }
        }
        filtroVista.backgroundColor = UIColor(patternImage: img)
    }
    private func scegliModoDS() {
        let m = UIAlertController(title: LF("DS Screens in Landscape"), message: nil, preferredStyle: .actionSheet)
        for (k, t) in [("grande", LF("Big Main Screen")), ("affiancati", LF("Side by Side"))] {
            m.addAction(UIAlertAction(title: (modoDS == k ? "✓ " : "") + t, style: .default) { [weak self] _ in
                UserDefaults.standard.set(k, forKey: "FMLAB.ds.orizzontale"); self?.emulatore?.inPausa = false; self?.view.setNeedsLayout() })
        }
        m.addAction(UIAlertAction(title: LF("Cancel"), style: .cancel) { [weak self] _ in self?.emulatore?.inPausa = false })
        m.popoverPresentationController?.sourceView = view
        m.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(m, animated: true)
    }

    private func apriMenu() {
        let e = emulatore
        e?.inPausa = true
        let m = UIAlertController(title: gioco.nome, message: e == nil ? avviso.text : nil, preferredStyle: .actionSheet)
        if let e {
            m.addAction(UIAlertAction(title: LF("Resume"), style: .default) { _ in e.inPausa = false })
            m.addAction(UIAlertAction(title: LF("Save State…"), style: .default) { [weak self] _ in self?.scegliPosto(salva: true) })
            let carica = UIAlertAction(title: LF("Load State…"), style: .default) { [weak self] _ in self?.scegliPosto(salva: false) }
            carica.isEnabled = (1...3).contains { e.dataStato($0) != nil }
            m.addAction(carica)
            m.addAction(UIAlertAction(title: LF("Take Screenshot"), style: .default) { [weak self] _ in e.inPausa = false; self?.fotografa() })
            m.addAction(UIAlertAction(title: tenuto == nil ? LF("Hold a Button…") : String(format: LF("Release %@"), nomeTasto(tenuto!)), style: .default) { [weak self] _ in self?.scegliTenuto() })
            m.addAction(UIAlertAction(title: LF("Move Buttons…"), style: .default) { [weak self] _ in self?.pad.modifica = true })
            if e.tocco {
                m.addAction(UIAlertAction(title: LF("Swap Screens"), style: .default) { [weak self] _ in
                    guard let self else { return }; e.inPausa = false; self.scambiati.toggle(); self.view.setNeedsLayout()
                })
                if view.bounds.width > view.bounds.height {
                    m.addAction(UIAlertAction(title: LF("DS Screens in Landscape…"), style: .default) { [weak self] _ in self?.scegliModoDS() })
                }
            }
        }
        if e == nil {
            m.addAction(UIAlertAction(title: LF("Copy Report"), style: .default) { [weak self] _ in
                guard let self else { return }
                UIPasteboard.general.string = self.rapporto()
                self.mostra(LF("Report copied: paste it in a message to FMLAB"))
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { self.apriMenu() }
            })
        }
        m.addAction(UIAlertAction(title: LF("Quit Game"), style: .destructive) { [weak self] _ in self?.emulatore?.ferma(); self?.chiudi() })
        if e != nil { m.addAction(UIAlertAction(title: LF("Cancel"), style: .cancel) { _ in e?.inPausa = false }) }
        m.popoverPresentationController?.sourceView = pad
        m.popoverPresentationController?.sourceRect = CGRect(x: pad.bounds.midX, y: pad.bounds.midY, width: 1, height: 1)
        present(m, animated: true)
    }
    private func nomeTasto(_ t: FMLABTasto) -> String {
        switch t { case .a: return "A"; case .b: return "B"; case .x: return "X"; case .y: return "Y"; case .l: return "L"; case .r: return "R"; default: return "?" }
    }
    private func scegliPosto(salva: Bool) {
        guard let e = emulatore else { return }
        let f = DateFormatter(); f.dateStyle = .short; f.timeStyle = .short
        let m = UIAlertController(title: LF(salva ? "Save State" : "Load State"), message: nil, preferredStyle: .actionSheet)
        for posto in 1...3 {
            let quando = e.dataStato(posto).map { f.string(from: $0) }
            let titolo = String(format: LF("Slot %ld"), posto) + " · " + (quando ?? LF("empty"))
            let a = UIAlertAction(title: titolo, style: .default) { [weak self] _ in
                e.inPausa = false
                if salva { e.salvaStato(posto: posto) { err in self?.mostra(err?.localizedDescription ?? String(format: LF("Saved in slot %ld"), posto)) } }
                else { e.caricaStato(posto: posto) { err in self?.mostra(err?.localizedDescription ?? LF("State loaded")) } }
            }
            if let foto = e.fotoStato(posto) { a.setValue(foto.preparingThumbnail(of: CGSize(width: 64, height: 48))?.withRenderingMode(.alwaysOriginal), forKey: "image") }
            a.isEnabled = salva || quando != nil
            m.addAction(a)
        }
        m.addAction(UIAlertAction(title: LF("Cancel"), style: .cancel) { _ in e.inPausa = false })
        m.popoverPresentationController?.sourceView = pad
        m.popoverPresentationController?.sourceRect = CGRect(x: pad.bounds.midX, y: pad.bounds.midY, width: 1, height: 1)
        present(m, animated: true)
    }
    private func fotografa() {
        guard let foto = emulatore?.fotografia(), let png = foto.pngData() else { return }
        let cartella = FMLABEmulatore.cartellaGiochi().appendingPathComponent("Foto", isDirectory: true)
        try? FileManager.default.createDirectory(at: cartella, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let file = cartella.appendingPathComponent("\(gioco.nome) \(f.string(from: Date())).png")
        do { try png.write(to: file); mostra(LF("Screenshot saved in Giochi › Foto")) } catch { mostra(error.localizedDescription) }
    }
    private func scegliTenuto() {
        guard let e = emulatore else { return }
        if let t = tenuto { e.tasto(t, premuto: false); tenuto = nil; e.inPausa = false; mostra(LF("Button released")); return }
        let m = UIAlertController(title: LF("Hold a Button"), message: LF("The button stays pressed until you release it from the menu (e.g. run in platform games)."), preferredStyle: .actionSheet)
        var tasti: [FMLABTasto] = [.a, .b]
        if e.disposizione >= 2 { tasti += [.x, .y] }
        if e.disposizione >= 1 { tasti += [.l, .r] }
        for t in tasti {
            m.addAction(UIAlertAction(title: nomeTasto(t), style: .default) { [weak self] _ in
                self?.tenuto = t; e.tasto(t, premuto: true); e.inPausa = false
                self?.mostra(String(format: LF("%@ held down"), self?.nomeTasto(t) ?? ""))
            })
        }
        m.addAction(UIAlertAction(title: LF("Cancel"), style: .cancel) { _ in e.inPausa = false })
        m.popoverPresentationController?.sourceView = pad
        m.popoverPresentationController?.sourceRect = CGRect(x: pad.bounds.midX, y: pad.bounds.midY, width: 1, height: 1)
        present(m, animated: true)
    }

    /// Quello che serve per capire perché un gioco non parte (niente percorsi personali, solo nome ed estensione).
    private func rapporto() -> String {
        let info = Bundle.main.infoDictionary
        let dim = (try? gioco.url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "?"
        return """
        FMLAB Linux \(info?["CFBundleShortVersionString"] as? String ?? "?") · Game Emulator
        iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)
        Console: \(gioco.core.console) · core \(gioco.core.nome)
        File: .\(gioco.url.pathExtension) · \(dim) · \(gioco.cartella == nil ? "Giochi" : "cartella collegata")
        Dati del motore: \(FMLABDati.versione)
        Errore: \(avviso.text ?? "-")
        """
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
    /// In verticale i comandi stanno sopra il gioco (schermo più grande): più trasparenti.
    var sopra = false
    var nomeCore = ""
    /// Dove sono salvate le posizioni dei tasti: per console e per verticale/orizzontale.
    var chiavePosizioni = "" { didSet { if chiavePosizioni != oldValue { if modifica && !oldValue.isEmpty { UserDefaults.standard.set(posizioni, forKey: oldValue) }; posizioni = (UserDefaults.standard.dictionary(forKey: chiavePosizioni) as? [String: [Double]]) ?? [:]; setNeedsLayout() } } }
    /// Posizioni personalizzate: elemento -> [spostamento x, spostamento y, ingrandimento]
    private var posizioni: [String: [Double]] = [:]
    var inModifica: ((Bool) -> Void)?
    /// Modalità "sposta i tasti": trascina per spostare, pizzica per ingrandire o rimpicciolire.
    var modifica = false {
        didSet {
            guard modifica != oldValue else { return }
            barraModifica.isHidden = !modifica
            bottoneMenu.isUserInteractionEnabled = !modifica; bottoneVeloce.isUserInteractionEnabled = !modifica; pizzicoGesto.isEnabled = modifica
            if modifica { for t in premuti { if let k = FMLABTasto(rawValue: t) { tasto?(k, false) } }; premuti = []; tocchi = [:] }
            else { UserDefaults.standard.set(posizioni, forKey: chiavePosizioni) }
            inModifica?(modifica); setNeedsLayout()
        }
    }
    private let barraModifica = UIStackView()
    private lazy var pizzicoGesto = UIPinchGestureRecognizer(target: self, action: #selector(pizzico(_:)))
    private var trascinato: String?
    private var ultimoPunto: CGPoint = .zero
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
        let spiega = UILabel(); spiega.text = LF("Drag to move · pinch to resize"); spiega.textColor = .white; spiega.font = .preferredFont(forTextStyle: .footnote)
        let ripristina = UIButton(type: .system); ripristina.setTitle(LF("Reset"), for: .normal); ripristina.tintColor = .white
        ripristina.addAction(UIAction { [weak self] _ in self?.posizioni = [:]; self?.setNeedsLayout() }, for: .touchUpInside)
        let fine = UIButton(type: .system); fine.setTitle(LF("Done"), for: .normal); fine.titleLabel?.font = .boldSystemFont(ofSize: 17); fine.tintColor = rosso
        fine.addAction(UIAction { [weak self] _ in self?.modifica = false }, for: .touchUpInside)
        for v in [spiega, ripristina, fine] { barraModifica.addArrangedSubview(v) }
        barraModifica.spacing = 16; barraModifica.alignment = .center; barraModifica.isLayoutMarginsRelativeArrangement = true
        barraModifica.layoutMargins = UIEdgeInsets(top: 6, left: 14, bottom: 6, right: 14)
        barraModifica.backgroundColor = UIColor(white: 0.1, alpha: 0.9); barraModifica.layer.cornerRadius = 14; barraModifica.isHidden = true
        addSubview(barraModifica)
        pizzicoGesto.isEnabled = false   // solo in modifica: mentre si gioca non deve mai annullare i tocchi
        addGestureRecognizer(pizzicoGesto)
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
        let alfa: CGFloat = (modo == .orizzontale && spazioLato < 150 * k) || sopra ? opacita * 0.5 : opacita
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
        applicaPosizioni()
        let bm = barraModifica.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        barraModifica.frame = CGRect(x: (w - bm.width) / 2, y: max(areaSicura.top + 50, h * 0.12), width: bm.width, height: bm.height)
        for v in [croce, bottoneMenu, bottoneVeloce] { v.layer.borderWidth = 0 }
        colora()
        if modifica { for v in elementi.values { v.layer.borderColor = rosso.cgColor; v.layer.borderWidth = 2 } }
    }
    private var elementi: [String: UIView] {
        var e: [String: UIView] = ["croce": croce, "menu": bottoneMenu, "veloce": bottoneVeloce]
        for p in pulsanti { if let t = p.tasto { e["t\(t.rawValue)"] = p.vista } }
        return e
    }
    private func applicaPosizioni() {
        for (k, v) in elementi {
            guard let p = posizioni[k], p.count == 3 else { continue }
            let c = CGPoint(x: v.center.x + p[0], y: v.center.y + p[1]), z = CGFloat(p[2])
            let f = CGRect(x: c.x - v.bounds.width * z / 2, y: c.y - v.bounds.height * z / 2, width: v.bounds.width * z, height: v.bounds.height * z)
            v.frame = f
            if v === croce { let l = f.width, t = l / 3
                frecce[0].frame = CGRect(x: t, y: 4, width: t, height: t - 8); frecce[1].frame = CGRect(x: t, y: l - t + 4, width: t, height: t - 8)
                frecce[2].frame = CGRect(x: 4, y: t, width: t - 8, height: t); frecce[3].frame = CGRect(x: l - t + 4, y: t, width: t - 8, height: t) }
            else if v is UILabel { v.layer.cornerRadius = f.height / 2 }
            else { v.layer.cornerRadius *= z }
        }
    }
    private func elemento(in p: CGPoint) -> String? {
        elementi.filter { !$0.value.isHidden && $0.value.alpha > 0.01 && $0.value.frame.insetBy(dx: -10, dy: -10).contains(p) }.min { hypot(p.x - $0.value.center.x, p.y - $0.value.center.y) < hypot(p.x - $1.value.center.x, p.y - $1.value.center.y) }?.key
    }
    @objc private func pizzico(_ g: UIPinchGestureRecognizer) {
        guard modifica else { return }
        if g.state == .began { trascinato = elemento(in: g.location(in: self)) }
        guard let k = trascinato else { return }
        var p = posizioni[k] ?? [0, 0, 1]
        p[2] = min(2.2, max(0.5, p[2] * Double(g.scale))); g.scale = 1
        posizioni[k] = p; setNeedsLayout()
        if g.state == .ended || g.state == .cancelled { trascinato = nil }
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
        if modifica { return true }
        // in orizzontale il pad è grande quanto lo schermo: i tocchi fuori dai comandi vanno al gioco (DS)
        if bottoneMenu.frame.contains(point) || bottoneVeloce.frame.contains(point) { return true }
        if soloMenu { return false }
        return !tasti(in: point).isEmpty || croce.frame.insetBy(dx: -30, dy: -30).contains(point)
    }
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) {
        if modifica { if let x = t.first, t.count == 1 { ultimoPunto = x.location(in: self); trascinato = elemento(in: ultimoPunto) }; return }
        for x in t { tocchi[ObjectIdentifier(x)] = tasti(in: x.location(in: self)) }; aggiornaTocchi(e) }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) {
        if modifica {
            guard let x = t.first, let k = trascinato, (e?.allTouches?.count ?? 1) == 1 else { return }
            let q = x.location(in: self); var p = posizioni[k] ?? [0, 0, 1]
            p[0] += Double(q.x - ultimoPunto.x); p[1] += Double(q.y - ultimoPunto.y); ultimoPunto = q
            posizioni[k] = p; setNeedsLayout(); return
        }
        for x in t { tocchi[ObjectIdentifier(x)] = tasti(in: x.location(in: self)) }; aggiornaTocchi(e) }
    override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) {
        if modifica { trascinato = nil; return }
        for x in t { tocchi[ObjectIdentifier(x)] = nil }; aggiornaTocchi(e) }
    override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { for x in t { tocchi[ObjectIdentifier(x)] = nil }; aggiornaTocchi(e) }
}


/// Evita che il CADisplayLink tenga in vita il gioco chiuso.
final class FMLABDebole: NSObject {
    weak var c: FMLABGiocoController?
    init(_ c: FMLABGiocoController) { self.c = c }
    @objc func giro() { c?.copiaSecondo() }
}

/// DS in orizzontale: superficie trasparente sopra lo schermo di sotto, che manda il tocco al gioco
/// (nell'immagine del core lo schermo di sotto è la metà bassa).
final class FMLABToccoDS: UIView {
    weak var emulatore: FMLABEmulatore?
    private func manda(_ t: Set<UITouch>, _ giu: Bool) {
        guard let x = t.first?.location(in: self), bounds.width > 0, bounds.height > 0 else { return }
        emulatore?.toccoX(x.x / bounds.width, y: 0.5 + 0.5 * min(1, max(0, x.y / bounds.height)), premuto: giu)
    }
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { manda(t, true) }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { manda(t, true) }
    override func touchesEnded(_ t: Set<UITouch>, with e: UIEvent?) { manda(t, false) }
    override func touchesCancelled(_ t: Set<UITouch>, with e: UIEvent?) { manda(t, false) }
}
