// FMLAB Game Emulator: motore nativo (core libretro dentro l'app, arm64, senza JIT).
// Non passa da Linux: il core gira direttamente sull'iPhone come nelle app di emulazione.
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Tasti del controller (stessi numeri di libretro, RETRO_DEVICE_ID_JOYPAD_*).
typedef NS_ENUM(NSInteger, FMLABTasto) {
    FMLABTastoB NS_SWIFT_NAME(b) = 0, FMLABTastoY NS_SWIFT_NAME(y) = 1, FMLABTastoSelect NS_SWIFT_NAME(select) = 2, FMLABTastoStart NS_SWIFT_NAME(start) = 3,
    FMLABTastoSu NS_SWIFT_NAME(su) = 4, FMLABTastoGiu NS_SWIFT_NAME(giu) = 5, FMLABTastoSinistra NS_SWIFT_NAME(sinistra) = 6, FMLABTastoDestra NS_SWIFT_NAME(destra) = 7,
    FMLABTastoA NS_SWIFT_NAME(a) = 8, FMLABTastoX NS_SWIFT_NAME(x) = 9, FMLABTastoL NS_SWIFT_NAME(l) = 10, FMLABTastoR NS_SWIFT_NAME(r) = 11,
    FMLABTastoL2 NS_SWIFT_NAME(l2) = 12, FMLABTastoR2 NS_SWIFT_NAME(r2) = 13, FMLABTastoL3 NS_SWIFT_NAME(l3) = 14, FMLABTastoR3 NS_SWIFT_NAME(r3) = 15,
};

@interface FMLABCore : NSObject
@property (readonly) NSString *nome;          // fceumm, gambatte, ...
@property (readonly) NSString *console;       // NES, Game Boy / Color, ...
@property (readonly) NSString *percorso;      // binario dentro Frameworks/
@property (readonly) NSArray<NSString *> *estensioni;
@end

@interface FMLABEmulatore : NSObject
/// Dati del motore (da fmlab-retro, dati/emulatore.json): per ogni core "estensioni" e "opzioni".
/// Si possono cambiare mentre l'app gira: valgono dal prossimo gioco aperto.
+ (void)usaDati:(NSDictionary<NSString *, NSDictionary *> *)core NS_SWIFT_NAME(usaDati(_:));
/// Core presenti nell'app (Frameworks/FMLAB*.framework).
+ (NSArray<FMLABCore *> *)core NS_SWIFT_NAME(core());
/// Il core giusto per un file, dall'estensione (nil se nessuno).
+ (nullable FMLABCore *)corePer:(NSString *)file NS_SWIFT_NAME(core(per:));
/// Cartelle in Documenti (visibili nell'app File): Giochi, Giochi/BIOS, Giochi/Salvataggi.
+ (NSURL *)cartellaGiochi;
+ (NSURL *)cartellaBIOS;
+ (NSURL *)cartellaSalvataggi;
/// Crea Giochi, Giochi/BIOS, Giochi/Salvataggi e un LEGGIMI, così la cartella si vede subito nell'app File.
+ (void)preparaCartelle;

- (nullable instancetype)initConCore:(FMLABCore *)core gioco:(NSString *)gioco error:(NSError **)error NS_SWIFT_NAME(init(conCore:gioco:));
/// La vista con l'immagine del gioco (si ingrandisce a pixel netti).
@property (readonly) UIView *vista;
/// Larghezza/altezza dell'immagine del gioco.
@property (readonly) CGFloat rapporto;
/// Quanti tasti servono: 0 = NES/GB (A B), 1 = GBA (A B L R), 2 = SNES/PS1/DS (A B X Y L R).
@property (readonly) NSInteger disposizione;
/// Il gioco usa il tocco sullo schermo (Nintendo DS).
@property (readonly) BOOL tocco;
@property (readonly) double fps;
@property (nonatomic) BOOL inPausa;
/// Avanti veloce (circa 3 volte) finché è attivo.
@property (nonatomic) BOOL veloce;

/// Cambia un'opzione del core mentre gira (es. disposizione degli schermi del DS quando giri il telefono).
- (void)opzione:(NSString *)chiave valore:(NSString *)valore NS_SWIFT_NAME(opzione(_:valore:));
- (void)avvia;
- (void)ferma;  // salva la memoria del gioco e chiude il core
- (void)tasto:(FMLABTasto)tasto premuto:(BOOL)premuto;
/// Tocco sullo schermo del gioco: x e y da 0 a 1 sull'immagine intera; premuto NO per alzare.
- (void)toccoX:(CGFloat)x y:(CGFloat)y premuto:(BOOL)premuto;
- (void)salvaStato:(void (^)(NSError * _Nullable))fatto;
- (void)caricaStato:(void (^)(NSError * _Nullable))fatto;
@property (readonly) BOOL statoEsiste;
/// Salvataggio automatico all'uscita (per "riprendi da dove eri"). Di base sì.
@property (nonatomic) BOOL salvaUscita;
@property (readonly) BOOL statoAutomaticoEsiste;
- (void)caricaAutomatico:(void (^)(NSError * _Nullable))fatto;
@end

NS_ASSUME_NONNULL_END
