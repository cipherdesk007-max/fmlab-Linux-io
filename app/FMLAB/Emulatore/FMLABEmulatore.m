// FMLAB Game Emulator: un piccolo "frontend" libretro nativo, scritto per FMLAB Linux.
// I core (fceumm, gambatte, mgba, bsnes, pcsx_rearmed, desmume) arrivano compilati per iPhone
// dal progetto fmlab-retro e stanno in Frameworks/FMLAB<core>.framework: niente Linux, niente JIT.
//   - un filo per il core (retro_run al ritmo del gioco), l'immagine passa alla vista a ogni schermata
//   - suono con AVAudioEngine, alla frequenza del core
//   - tasti a schermo, controller MFi/Xbox/PlayStation (GameController), tocco per il DS
//   - memoria del gioco (.srm) e uno stato veloce (.state) in Documenti/Giochi/Salvataggi
#import "FMLABEmulatore.h"
#import <AVFoundation/AVFoundation.h>
#import <GameController/GameController.h>
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <mach/mach_time.h>
#include <stdatomic.h>
#include <os/lock.h>
#include "libretro.h"

#pragma mark - Core disponibili

@implementation FMLABCore
- (instancetype)initNome:(NSString *)nome console:(NSString *)console percorso:(NSString *)percorso estensioni:(NSArray *)estensioni {
    if ((self = [super init])) { _nome = nome; _console = console; _percorso = percorso; _estensioni = estensioni; }
    return self;
}
@end

static NSDictionary<NSString *, NSArray<NSString *> *> *FMLABEstensioni(void) {
    return @{ @"fceumm": @[@"nes", @"fds", @"unf", @"unif"], @"gambatte": @[@"gb", @"gbc", @"dmg"], @"mgba": @[@"gba"],
              @"bsnes": @[@"sfc", @"smc", @"bs"], @"pcsx_rearmed": @[@"cue", @"pbp", @"chd", @"m3u", @"iso", @"img", @"bin"],
              @"desmume": @[@"nds"] };
}
// Opzioni dei core: tutto senza JIT (iOS non lo permette senza StikDebug) e regolato per l'iPhone.
static NSDictionary<NSString *, NSString *> *FMLABOpzioniFisse(void) {
    return @{ @"pcsx_rearmed_drc": @"disabled", @"pcsx_rearmed_frameskip": @"0",
              @"desmume_cpu_mode": @"interpreter", @"desmume_internal_resolution": @"256x192",
              @"desmume_screens_layout": @"top/bottom", @"desmume_pointer_type": @"touch",
              @"desmume_frameskip": @"0", @"mgba_skip_bios": @"ON", @"fceumm_aspect": @"8:7 PAR" };
}

#pragma mark - Stato del core attivo (libretro chiama funzioni C senza contesto: un solo gioco alla volta)

typedef struct {
    void *lib;
    void (*init)(void); void (*deinit)(void); unsigned (*api)(void);
    void (*info)(struct retro_system_info *); void (*av)(struct retro_system_av_info *);
    void (*setEnv)(retro_environment_t); void (*setVideo)(retro_video_refresh_t); void (*setAudio)(retro_audio_sample_t);
    void (*setAudioBatch)(retro_audio_sample_batch_t); void (*setPoll)(retro_input_poll_t); void (*setState)(retro_input_state_t);
    void (*setPort)(unsigned, unsigned); void (*reset)(void); void (*run)(void);
    size_t (*serSize)(void); bool (*ser)(void *, size_t); bool (*unser)(const void *, size_t);
    bool (*load)(const struct retro_game_info *); void (*unload)(void);
    void *(*memData)(unsigned); size_t (*memSize)(unsigned);
} FMLABFunzioni;

static FMLABFunzioni F;
static enum retro_pixel_format G_formato = RETRO_PIXEL_FORMAT_0RGB1555;
static char G_sistema[1024], G_salvataggi[1024];
static NSMutableDictionary<NSString *, NSString *> *G_opzioni;
static _Atomic uint32_t G_tasti, G_tastiController;
static _Atomic int G_px, G_py, G_ptocco;
static struct retro_system_av_info G_av;
static BOOL G_avCambiato;

// immagine: l'ultima schermata in BGRX 32 bit, presa dalla vista a ogni giro dello schermo
static os_unfair_lock G_lockImmagine = OS_UNFAIR_LOCK_INIT;
static uint32_t *G_pixel; static unsigned G_w, G_h; static size_t G_cap; static BOOL G_nuova;

// suono: anello di campioni stereo a 16 bit
#define FMLAB_ANELLO (1 << 15)
static int16_t G_anello[FMLAB_ANELLO * 2];
static _Atomic uint32_t G_scrivi, G_leggi;

static void fmlabLog(enum retro_log_level level, const char *fmt, ...) {
    if (level < RETRO_LOG_WARN) return;
    char riga[512]; va_list ap; va_start(ap, fmt); vsnprintf(riga, sizeof riga, fmt, ap); va_end(ap);
    NSLog(@"[FMLAB Emulatore] %s", riga);
}

static bool fmlabAmbiente(unsigned cmd, void *data) {
    switch (cmd & ~RETRO_ENVIRONMENT_EXPERIMENTAL) {
        case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY & ~RETRO_ENVIRONMENT_EXPERIMENTAL: *(const char **)data = G_sistema; return true;
        case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY & ~RETRO_ENVIRONMENT_EXPERIMENTAL: *(const char **)data = G_salvataggi; return true;
        case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT & ~RETRO_ENVIRONMENT_EXPERIMENTAL: {
            enum retro_pixel_format f = *(enum retro_pixel_format *)data;
            if (f > RETRO_PIXEL_FORMAT_RGB565) return false;
            G_formato = f; return true;
        }
        case RETRO_ENVIRONMENT_GET_LOG_INTERFACE & ~RETRO_ENVIRONMENT_EXPERIMENTAL: ((struct retro_log_callback *)data)->log = fmlabLog; return true;
        case RETRO_ENVIRONMENT_GET_CAN_DUPE & ~RETRO_ENVIRONMENT_EXPERIMENTAL: *(bool *)data = true; return true;
        case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS & ~RETRO_ENVIRONMENT_EXPERIMENTAL: return true;
        case RETRO_ENVIRONMENT_GET_LANGUAGE & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
            *(unsigned *)data = [NSLocale.preferredLanguages.firstObject hasPrefix:@"it"] ? RETRO_LANGUAGE_ITALIAN : RETRO_LANGUAGE_ENGLISH; return true;
        case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE & ~RETRO_ENVIRONMENT_EXPERIMENTAL: if (data) *(int *)data = 3; return true;
        case RETRO_ENVIRONMENT_GET_FASTFORWARDING & ~RETRO_ENVIRONMENT_EXPERIMENTAL: if (data) *(bool *)data = false; return true;
        case RETRO_ENVIRONMENT_SET_VARIABLES & ~RETRO_ENVIRONMENT_EXPERIMENTAL: {
            // "Descrizione; primo|secondo|...": se non l'abbiamo fissata, vale la prima scelta
            for (const struct retro_variable *v = data; v && v->key; v++) {
                NSString *k = @(v->key); if (G_opzioni[k] || !v->value) continue;
                NSString *val = @(v->value); NSRange s = [val rangeOfString:@"; "];
                if (s.location == NSNotFound) continue;
                G_opzioni[k] = [[val substringFromIndex:NSMaxRange(s)] componentsSeparatedByString:@"|"].firstObject;
            }
            return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE & ~RETRO_ENVIRONMENT_EXPERIMENTAL: {
            struct retro_variable *v = data; if (!v || !v->key) return false;
            NSString *val = G_opzioni[@(v->key)]; if (!val) return false;
            static char tenuti[64][128]; static int giro;   // le stringhe restano valide per il core
            char *s = tenuti[giro++ % 64]; strlcpy(s, val.UTF8String, 128); v->value = s; return true;
        }
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE & ~RETRO_ENVIRONMENT_EXPERIMENTAL: *(bool *)data = false; return true;
        case RETRO_ENVIRONMENT_SET_GEOMETRY & ~RETRO_ENVIRONMENT_EXPERIMENTAL: G_av.geometry = *(const struct retro_game_geometry *)data; G_avCambiato = YES; return true;
        case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO & ~RETRO_ENVIRONMENT_EXPERIMENTAL: G_av = *(const struct retro_system_av_info *)data; G_avCambiato = YES; return true;
        case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
        case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
        case RETRO_ENVIRONMENT_SET_MEMORY_MAPS & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
        case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
        case RETRO_ENVIRONMENT_SET_SUPPORT_ACHIEVEMENTS & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
        case RETRO_ENVIRONMENT_SET_PERFORMANCE_LEVEL & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
        case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
        case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
        case RETRO_ENVIRONMENT_SET_CONTENT_INFO_OVERRIDE & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
            return true;
        case RETRO_ENVIRONMENT_SET_MESSAGE & ~RETRO_ENVIRONMENT_EXPERIMENTAL: {
            const struct retro_message *m = data; if (m && m->msg) NSLog(@"[FMLAB Emulatore] %s", m->msg); return true;
        }
        default: return false;   // niente GL/Vulkan, niente opzioni v1/v2: il core usa le sue scelte semplici
    }
}

static inline uint32_t fmlab565(uint16_t p) {
    uint32_t r = (p >> 11) & 31, g = (p >> 5) & 63, b = p & 31;
    return 0xFF000000u | ((r << 3 | r >> 2) << 16) | ((g << 2 | g >> 4) << 8) | (b << 3 | b >> 2);
}
static inline uint32_t fmlab1555(uint16_t p) {
    uint32_t r = (p >> 10) & 31, g = (p >> 5) & 31, b = p & 31;
    return 0xFF000000u | ((r << 3 | r >> 2) << 16) | ((g << 3 | g >> 2) << 8) | (b << 3 | b >> 2);
}

static void fmlabVideo(const void *data, unsigned w, unsigned h, size_t pitch) {
    if (!data || !w || !h) return;   // stessa schermata di prima
    os_unfair_lock_lock(&G_lockImmagine);
    if ((size_t)w * h > G_cap) { G_cap = (size_t)w * h; G_pixel = realloc(G_pixel, G_cap * 4); }
    for (unsigned y = 0; y < h; y++) {
        const uint8_t *riga = (const uint8_t *)data + y * pitch; uint32_t *fuori = G_pixel + (size_t)y * w;
        if (G_formato == RETRO_PIXEL_FORMAT_XRGB8888) memcpy(fuori, riga, w * 4);
        else if (G_formato == RETRO_PIXEL_FORMAT_RGB565) { const uint16_t *p = (const uint16_t *)riga; for (unsigned x = 0; x < w; x++) fuori[x] = fmlab565(p[x]); }
        else { const uint16_t *p = (const uint16_t *)riga; for (unsigned x = 0; x < w; x++) fuori[x] = fmlab1555(p[x]); }
    }
    G_w = w; G_h = h; G_nuova = YES;
    os_unfair_lock_unlock(&G_lockImmagine);
}

static size_t fmlabSuoni(const int16_t *data, size_t frames) {
    uint32_t s = atomic_load(&G_scrivi), l = atomic_load(&G_leggi);
    size_t liberi = FMLAB_ANELLO - 1 - (size_t)(s - l);
    if (frames > liberi) frames = liberi;   // pieno: si perde un pezzetto invece di rallentare
    for (size_t i = 0; i < frames; i++) {
        uint32_t k = (s + (uint32_t)i) & (FMLAB_ANELLO - 1);
        G_anello[k * 2] = data[i * 2]; G_anello[k * 2 + 1] = data[i * 2 + 1];
    }
    atomic_store(&G_scrivi, s + (uint32_t)frames);
    return frames;
}
static void fmlabSuono(int16_t l, int16_t r) { int16_t c[2] = { l, r }; fmlabSuoni(c, 1); }
static void fmlabPoll(void) {}
static int16_t fmlabStato(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port != 0) return 0;
    if (device == RETRO_DEVICE_JOYPAD) {
        uint32_t t = atomic_load(&G_tasti) | atomic_load(&G_tastiController);
        if (id == RETRO_DEVICE_ID_JOYPAD_MASK) return (int16_t)t;
        return (t >> id) & 1;
    }
    if (device == RETRO_DEVICE_POINTER) {
        if (id == RETRO_DEVICE_ID_POINTER_X) return atomic_load(&G_px);
        if (id == RETRO_DEVICE_ID_POINTER_Y) return atomic_load(&G_py);
        if (id == RETRO_DEVICE_ID_POINTER_PRESSED) return atomic_load(&G_ptocco);
        if (id == RETRO_DEVICE_ID_POINTER_COUNT) return atomic_load(&G_ptocco) ? 1 : 0;
    }
    return 0;
}

#pragma mark - Vista

@interface FMLABVistaGioco : UIView
@property (nonatomic, weak) FMLABEmulatore *emulatore;
@end

@implementation FMLABVistaGioco {
    CADisplayLink *_giro;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = UIColor.blackColor;
        self.layer.magnificationFilter = kCAFilterNearest;   // pixel netti
        self.layer.contentsGravity = kCAGravityResize;
        self.multipleTouchEnabled = NO;
    }
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_giro invalidate]; _giro = nil;
    if (self.window) {
        _giro = [CADisplayLink displayLinkWithTarget:self selector:@selector(aggiorna)];
        if (@available(iOS 15.0, *)) _giro.preferredFrameRateRange = CAFrameRateRangeMake(30, 60, 60);
        [_giro addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)aggiorna {
    os_unfair_lock_lock(&G_lockImmagine);
    if (!G_nuova || !G_pixel) { os_unfair_lock_unlock(&G_lockImmagine); return; }
    unsigned w = G_w, h = G_h;
    NSData *copia = [NSData dataWithBytes:G_pixel length:(size_t)w * h * 4];
    G_nuova = NO;
    os_unfair_lock_unlock(&G_lockImmagine);
    CGDataProviderRef dati = CGDataProviderCreateWithCFData((__bridge CFDataRef)copia);
    CGColorSpaceRef spazio = CGColorSpaceCreateDeviceRGB();
    CGImageRef img = CGImageCreate(w, h, 8, 32, w * 4, spazio, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, dati, NULL, false, kCGRenderingIntentDefault);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    self.layer.contents = (__bridge id)img;
    [CATransaction commit];
    CGImageRelease(img); CGColorSpaceRelease(spazio); CGDataProviderRelease(dati);
}
// Nintendo DS: il tocco sullo schermo di sotto va al gioco
- (void)tocca:(NSSet<UITouch *> *)touches premuto:(BOOL)premuto {
    UITouch *t = touches.anyObject; if (!t || !self.emulatore.tocco) return;
    CGPoint p = [t locationInView:self];
    [self.emulatore toccoX:p.x / MAX(1, self.bounds.size.width) y:p.y / MAX(1, self.bounds.size.height) premuto:premuto];
}
- (void)touchesBegan:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self tocca:t premuto:YES]; }
- (void)touchesMoved:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self tocca:t premuto:YES]; }
- (void)touchesEnded:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self tocca:t premuto:NO]; }
- (void)touchesCancelled:(NSSet<UITouch *> *)t withEvent:(UIEvent *)e { [self tocca:t premuto:NO]; }
@end

#pragma mark - Emulatore

static __weak FMLABEmulatore *G_attivo;

@implementation FMLABEmulatore {
    FMLABCore *_core;
    NSString *_gioco, *_nomeGioco;
    NSData *_datiGioco;
    NSThread *_filo;
    _Atomic bool _ferma;
    NSMutableArray<dispatch_block_t> *_lavori;
    os_unfair_lock _lockLavori;
    AVAudioEngine *_motore;
    FMLABVistaGioco *_vista;
    BOOL _caricato, _fermoDaSfondo;
}

+ (NSURL *)cartellaGiochi {
    NSURL *d = [[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"Giochi" isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:nil];
    return d;
}
+ (NSURL *)cartellaBIOS { NSURL *d = [self.cartellaGiochi URLByAppendingPathComponent:@"BIOS" isDirectory:YES]; [NSFileManager.defaultManager createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:nil]; return d; }
+ (NSURL *)cartellaSalvataggi { NSURL *d = [self.cartellaGiochi URLByAppendingPathComponent:@"Salvataggi" isDirectory:YES]; [NSFileManager.defaultManager createDirectoryAtURL:d withIntermediateDirectories:YES attributes:nil error:nil]; return d; }

+ (NSArray<FMLABCore *> *)core {
    static NSArray *tutti; static dispatch_once_t una;
    dispatch_once(&una, ^{
        NSMutableArray *a = [NSMutableArray array];
        NSString *fw = NSBundle.mainBundle.privateFrameworksPath;
        for (NSString *n in [[NSFileManager.defaultManager contentsOfDirectoryAtPath:fw error:nil] sortedArrayUsingSelector:@selector(compare:)]) {
            if (![n hasPrefix:@"FMLAB"] || ![n hasSuffix:@".framework"]) continue;
            NSBundle *b = [NSBundle bundleWithPath:[fw stringByAppendingPathComponent:n]];
            NSString *nome = b.infoDictionary[@"FMLABCoreName"], *console = b.infoDictionary[@"FMLABCoreConsole"];
            NSArray *est = FMLABEstensioni()[nome ?: @""];
            if (!nome || !est || !b.executablePath) continue;
            [a addObject:[[FMLABCore alloc] initNome:nome console:console ?: nome percorso:b.executablePath estensioni:est]];
        }
        tutti = a;
    });
    return tutti;
}
+ (FMLABCore *)corePer:(NSString *)file {
    NSString *e = file.pathExtension.lowercaseString;
    // .bin da solo è ambiguo: lo prende la PlayStation solo se non c'è un .cue accanto
    for (FMLABCore *c in self.core) if ([c.estensioni containsObject:e]) return c;
    return nil;
}

static NSError *fmlabErrore(NSString *messaggio) {
    return [NSError errorWithDomain:@"FMLABEmulatore" code:1 userInfo:@{ NSLocalizedDescriptionKey: NSLocalizedString(messaggio, nil) }];
}

- (instancetype)initConCore:(FMLABCore *)core gioco:(NSString *)gioco error:(NSError **)error {
    if (!(self = [super init])) return nil;
    if (G_attivo) { [G_attivo ferma]; }
    _core = core; _gioco = gioco; _nomeGioco = gioco.lastPathComponent.stringByDeletingPathExtension;
    _lavori = [NSMutableArray array]; _lockLavori = OS_UNFAIR_LOCK_INIT;
    memset(&F, 0, sizeof F);
    F.lib = dlopen(core.percorso.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
    if (!F.lib) { if (error) *error = fmlabErrore([NSString stringWithFormat:NSLocalizedString(@"The emulator could not be loaded: %s", nil), dlerror()]); return nil; }
#define S(campo, nome) F.campo = dlsym(F.lib, nome); if (!F.campo) { if (error) *error = fmlabErrore(@"This emulator is incomplete."); dlclose(F.lib); F.lib = NULL; return nil; }
    S(init, "retro_init") S(deinit, "retro_deinit") S(api, "retro_api_version") S(info, "retro_get_system_info") S(av, "retro_get_system_av_info")
    S(setEnv, "retro_set_environment") S(setVideo, "retro_set_video_refresh") S(setAudio, "retro_set_audio_sample") S(setAudioBatch, "retro_set_audio_sample_batch")
    S(setPoll, "retro_set_input_poll") S(setState, "retro_set_input_state") S(setPort, "retro_set_controller_port_device") S(reset, "retro_reset") S(run, "retro_run")
    S(serSize, "retro_serialize_size") S(ser, "retro_serialize") S(unser, "retro_unserialize") S(load, "retro_load_game") S(unload, "retro_unload_game")
    S(memData, "retro_get_memory_data") S(memSize, "retro_get_memory_size")
#undef S
    strlcpy(G_sistema, FMLABEmulatore.cartellaBIOS.fileSystemRepresentation, sizeof G_sistema);
    strlcpy(G_salvataggi, FMLABEmulatore.cartellaSalvataggi.fileSystemRepresentation, sizeof G_salvataggi);
    G_opzioni = [FMLABOpzioniFisse() mutableCopy];
    G_formato = RETRO_PIXEL_FORMAT_0RGB1555;
    atomic_store(&G_tasti, 0); atomic_store(&G_tastiController, 0); atomic_store(&G_ptocco, 0);
    atomic_store(&G_scrivi, 0); atomic_store(&G_leggi, 0);
    os_unfair_lock_lock(&G_lockImmagine); G_nuova = NO; G_w = G_h = 0; os_unfair_lock_unlock(&G_lockImmagine);

    F.setEnv(fmlabAmbiente);
    F.init();
    F.setVideo(fmlabVideo); F.setAudio(fmlabSuono); F.setAudioBatch(fmlabSuoni); F.setPoll(fmlabPoll); F.setState(fmlabStato);
    struct retro_system_info si = {0}; F.info(&si);
    struct retro_game_info gi = { .path = gioco.fileSystemRepresentation };
    if (!si.need_fullpath) {
        _datiGioco = [NSData dataWithContentsOfFile:gioco options:NSDataReadingMappedIfSafe error:nil];
        if (!_datiGioco) { if (error) *error = fmlabErrore(@"The game file could not be read."); F.deinit(); dlclose(F.lib); F.lib = NULL; return nil; }
        gi.data = _datiGioco.bytes; gi.size = _datiGioco.length;
    }
    if (!F.load(&gi)) {
        if (error) *error = fmlabErrore(@"The emulator could not open this game. Check that the file is complete and not zipped; some consoles need their BIOS in Giochi/BIOS.");
        F.deinit(); dlclose(F.lib); F.lib = NULL; return nil;
    }
    F.setPort(0, RETRO_DEVICE_JOYPAD);
    memset(&G_av, 0, sizeof G_av); F.av(&G_av); G_avCambiato = NO;
    _caricato = YES;
    [self leggiMemoria];
    G_attivo = self;
    _vista = [[FMLABVistaGioco alloc] initWithFrame:CGRectZero]; _vista.emulatore = self;
    return self;
}

- (BOOL)tocco { return [_core.nome isEqual:@"desmume"]; }
- (FMLABCore *)coreUsato { return _core; }
- (NSInteger)disposizione {
    if ([@[@"fceumm", @"gambatte"] containsObject:_core.nome]) return 0;
    if ([_core.nome isEqual:@"mgba"]) return 1;
    return 2;
}
- (double)fps { return G_av.timing.fps > 1 ? G_av.timing.fps : 60; }
- (CGFloat)rapporto {
    struct retro_game_geometry g = G_av.geometry;
    if (g.aspect_ratio > 0.1) return g.aspect_ratio;
    return g.base_height ? (CGFloat)g.base_width / g.base_height : 4.0 / 3.0;
}
- (UIView *)vista { return _vista; }

- (NSURL *)fileSalvataggio:(NSString *)estensione {
    return [[FMLABEmulatore.cartellaSalvataggi URLByAppendingPathComponent:_nomeGioco] URLByAppendingPathExtension:estensione];
}
- (void)leggiMemoria {
    size_t n = F.memSize(RETRO_MEMORY_SAVE_RAM); void *p = F.memData(RETRO_MEMORY_SAVE_RAM);
    NSData *d = [NSData dataWithContentsOfURL:[self fileSalvataggio:@"srm"]];
    if (p && n && d.length) memcpy(p, d.bytes, MIN(n, d.length));
}
- (void)scriviMemoria {
    if (!_caricato) return;
    size_t n = F.memSize(RETRO_MEMORY_SAVE_RAM); void *p = F.memData(RETRO_MEMORY_SAVE_RAM);
    if (p && n) [[NSData dataWithBytes:p length:n] writeToURL:[self fileSalvataggio:@"srm"] atomically:YES];
}

- (void)lavoro:(dispatch_block_t)b { os_unfair_lock_lock(&_lockLavori); [_lavori addObject:b]; os_unfair_lock_unlock(&_lockLavori); }

- (void)avviaSuono {
    double hz = G_av.timing.sample_rate > 1000 ? G_av.timing.sample_rate : 44100;
    [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback withOptions:AVAudioSessionCategoryOptionMixWithOthers error:nil];
    [AVAudioSession.sharedInstance setActive:YES error:nil];
    AVAudioFormat *formato = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:hz channels:2 interleaved:NO];
    AVAudioSourceNode *fonte = [[AVAudioSourceNode alloc] initWithFormat:formato renderBlock:^OSStatus(BOOL *silenzio, const AudioTimeStamp *t, AVAudioFrameCount n, AudioBufferList *out) {
        float *l = out->mBuffers[0].mData, *r = out->mNumberBuffers > 1 ? out->mBuffers[1].mData : NULL;
        uint32_t s = atomic_load(&G_scrivi), le = atomic_load(&G_leggi);
        uint32_t disp = s - le;
        for (AVAudioFrameCount i = 0; i < n; i++) {
            float a = 0, b = 0;
            if (i < disp) { uint32_t k = (le + i) & (FMLAB_ANELLO - 1); a = G_anello[k * 2] / 32768.f; b = G_anello[k * 2 + 1] / 32768.f; }
            l[i] = a; if (r) r[i] = b;
        }
        atomic_store(&G_leggi, le + MIN(disp, n));
        return noErr;
    }];
    _motore = [AVAudioEngine new];
    [_motore attachNode:fonte];
    [_motore connect:fonte to:_motore.mainMixerNode format:formato];
    NSError *e = nil; if (![_motore startAndReturnError:&e]) NSLog(@"[FMLAB Emulatore] audio: %@", e);
}

- (void)avvia {
    if (_filo || !_caricato) return;
    [self avviaSuono];
    atomic_store(&_ferma, false);
    __weak typeof(self) debole = self;
    _filo = [[NSThread alloc] initWithBlock:^{ [debole giro]; }];
    _filo.qualityOfService = NSQualityOfServiceUserInteractive;
    _filo.name = @"FMLAB Emulatore";
    [_filo start];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(sfondo) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(primoPiano) name:UIApplicationDidBecomeActiveNotification object:nil];
}
// in sfondo si ferma e salva la memoria del gioco; tornando, riparte da solo se l'aveva fermato l'app
- (void)sfondo { if (!self.inPausa) { _fermoDaSfondo = YES; self.inPausa = YES; } [self lavoro:^{ [self scriviMemoria]; }]; }
- (void)primoPiano { if (_fermoDaSfondo) { _fermoDaSfondo = NO; self.inPausa = NO; } }

static uint32_t fmlabPad(GCExtendedGamepad *g) {
    if (!g) return 0;
    uint32_t t = 0;
    #define T(cond, id) if (cond) t |= 1u << id;
    T(g.dpad.up.pressed || g.leftThumbstick.yAxis.value > 0.5, RETRO_DEVICE_ID_JOYPAD_UP)
    T(g.dpad.down.pressed || g.leftThumbstick.yAxis.value < -0.5, RETRO_DEVICE_ID_JOYPAD_DOWN)
    T(g.dpad.left.pressed || g.leftThumbstick.xAxis.value < -0.5, RETRO_DEVICE_ID_JOYPAD_LEFT)
    T(g.dpad.right.pressed || g.leftThumbstick.xAxis.value > 0.5, RETRO_DEVICE_ID_JOYPAD_RIGHT)
    // disposizione Nintendo: A a destra, B in basso
    T(g.buttonB.pressed, RETRO_DEVICE_ID_JOYPAD_A) T(g.buttonA.pressed, RETRO_DEVICE_ID_JOYPAD_B)
    T(g.buttonY.pressed, RETRO_DEVICE_ID_JOYPAD_X) T(g.buttonX.pressed, RETRO_DEVICE_ID_JOYPAD_Y)
    T(g.leftShoulder.pressed, RETRO_DEVICE_ID_JOYPAD_L) T(g.rightShoulder.pressed, RETRO_DEVICE_ID_JOYPAD_R)
    T(g.leftTrigger.pressed, RETRO_DEVICE_ID_JOYPAD_L2) T(g.rightTrigger.pressed, RETRO_DEVICE_ID_JOYPAD_R2)
    T(g.buttonMenu.pressed, RETRO_DEVICE_ID_JOYPAD_START)
    if (@available(iOS 13.0, *)) { T(g.buttonOptions.pressed, RETRO_DEVICE_ID_JOYPAD_SELECT) }
    #undef T
    return t;
}

- (void)giro {
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    double secondi = (double)tb.numer / tb.denom / 1e9;
    double periodo = 1.0 / self.fps;
    uint64_t prossimo = mach_absolute_time();
    while (!atomic_load(&_ferma)) {
        os_unfair_lock_lock(&_lockLavori); NSArray *da = [_lavori copy]; [_lavori removeAllObjects]; os_unfair_lock_unlock(&_lockLavori);
        for (dispatch_block_t b in da) b();
        if (self.inPausa) { usleep(20000); prossimo = mach_absolute_time(); continue; }
        uint32_t pad = 0;
        for (GCController *c in GCController.controllers) pad |= fmlabPad(c.extendedGamepad);
        atomic_store(&G_tastiController, pad);
        @autoreleasepool { F.run(); }
        if (G_avCambiato) { G_avCambiato = NO; periodo = 1.0 / self.fps; }
        // se il suono è molto avanti, si aspetta un po' di più (resta in pari con l'audio)
        uint32_t coda = atomic_load(&G_scrivi) - atomic_load(&G_leggi);
        double extra = coda > (uint32_t)(G_av.timing.sample_rate * 0.15) ? periodo * 0.5 : 0;
        if (self.veloce) extra = -periodo * 2.0 / 3.0;   // avanti veloce: circa 3 volte (il suono in più si scarta)
        prossimo += (uint64_t)((periodo + extra) / secondi);
        uint64_t ora = mach_absolute_time();
        if (ora < prossimo) mach_wait_until(prossimo);
        else if ((ora - prossimo) * secondi > 0.25) prossimo = ora;   // troppo indietro: si riparte da adesso
    }
    [self scriviMemoria];
    F.unload(); F.deinit();
    _caricato = NO;
}

- (void)ferma {
    if (!_caricato && !_filo) return;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    if (_filo) {
        atomic_store(&_ferma, true);
        while (_caricato) usleep(5000);   // il filo salva e chiude il core
        _filo = nil;
    } else { [self scriviMemoria]; F.unload(); F.deinit(); _caricato = NO; }
    [_motore stop]; _motore = nil;
    if (F.lib) { dlclose(F.lib); F.lib = NULL; }
    [AVAudioSession.sharedInstance setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:nil];
}
- (void)dealloc { [self ferma]; }

- (void)tasto:(FMLABTasto)tasto premuto:(BOOL)premuto {
    if (premuto) atomic_fetch_or(&G_tasti, 1u << tasto); else atomic_fetch_and(&G_tasti, ~(1u << tasto));
}
- (void)toccoX:(CGFloat)x y:(CGFloat)y premuto:(BOOL)premuto {
    atomic_store(&G_px, (int)(MAX(0, MIN(1, x)) * 65534 - 32767));
    atomic_store(&G_py, (int)(MAX(0, MIN(1, y)) * 65534 - 32767));
    atomic_store(&G_ptocco, premuto ? 1 : 0);
}

- (BOOL)statoEsiste { return [NSFileManager.defaultManager fileExistsAtPath:[self fileSalvataggio:@"state"].path]; }
- (void)salvaStato:(void (^)(NSError *))fatto {
    [self lavoro:^{
        size_t n = F.serSize(); NSMutableData *d = [NSMutableData dataWithLength:n];
        NSError *e = nil;
        if (!n || !F.ser(d.mutableBytes, n)) e = fmlabErrore(@"This game cannot be saved right now.");
        else if (![d writeToURL:[self fileSalvataggio:@"state"] options:NSDataWritingAtomic error:&e]) {}
        [self scriviMemoria];
        dispatch_async(dispatch_get_main_queue(), ^{ fatto(e); });
    }];
}
- (void)caricaStato:(void (^)(NSError *))fatto {
    [self lavoro:^{
        NSData *d = [NSData dataWithContentsOfURL:[self fileSalvataggio:@"state"]];
        NSError *e = (!d || !F.unser(d.bytes, d.length)) ? fmlabErrore(@"The saved state could not be loaded.") : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ fatto(e); });
    }];
}
@end
