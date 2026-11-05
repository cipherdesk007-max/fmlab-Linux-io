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
#include <archive.h>
#include <archive_entry.h>
#include <CommonCrypto/CommonDigest.h>
#define GLES_SILENCE_DEPRECATION 1
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES3/gl.h>
#import <Accelerate/Accelerate.h>

#pragma mark - Core disponibili

@implementation FMLABCore
- (instancetype)initNome:(NSString *)nome console:(NSString *)console percorso:(NSString *)percorso estensioni:(NSArray *)estensioni {
    if ((self = [super init])) { _nome = nome; _console = console; _percorso = percorso; _estensioni = estensioni; }
    return self;
}
@end

// Valori di partenza: gli stessi di dati/emulatore.json di fmlab-retro; l'app li sostituisce con quelli scaricati.
static NSDictionary<NSString *, NSArray<NSString *> *> *G_estensioni;
static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *G_opzioniCore;
static NSArray *G_tuttiCore;
static NSDictionary<NSString *, NSString *> *G_opzioniUtente;
static NSDictionary<NSString *, NSArray<NSString *> *> *FMLABEstensioni(void) {
    if (!G_estensioni) G_estensioni = @{ @"fceumm": @[@"nes", @"fds", @"unf", @"unif"], @"gambatte": @[@"gb", @"gbc", @"dmg"], @"mgba": @[@"gba"],
              @"bsnes": @[@"sfc", @"smc", @"bs"], @"pcsx_rearmed": @[@"cue", @"pbp", @"chd", @"m3u", @"iso", @"img", @"bin"],
              @"desmume": @[@"nds"], @"ppsspp": @[@"cso", @"iso", @"pbp", @"elf", @"prx"] };
    return G_estensioni;
}
// Opzioni dei core: tutto senza JIT (iOS non lo permette senza StikDebug) e regolato per l'iPhone.
static NSDictionary<NSString *, NSString *> *FMLABOpzioniFisse(NSString *core) {
    if (G_opzioniCore[core]) return G_opzioniCore[core];
    return @{ @"pcsx_rearmed_drc": @"disabled", @"pcsx_rearmed_frameskip": @"0",
              @"desmume_cpu_mode": @"interpreter", @"desmume_internal_resolution": @"256x192",
              @"desmume_screens_layout": @"top/bottom", @"desmume_pointer_type": @"touch",
              @"desmume_frameskip": @"0", @"mgba_skip_bios": @"ON", @"fceumm_aspect": @"8:7 PAR",
              @"ppsspp_cpu_core": @"IR JIT", @"ppsspp_backend": @"none", @"ppsspp_fast_memory": @"enabled" };
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
static _Atomic bool G_varNuove;   // un'opzione è cambiata mentre il gioco gira
static retro_audio_buffer_status_callback_t G_statoAudio;   // il core vuole sapere quanto suono c'è in coda (salto fotogrammi automatico)
static _Atomic uint32_t G_fotogrammi;              // fotogrammi emulati (per la velocità vera a schermo)
static _Atomic uint32_t G_vibra;                    // ultima forza di vibrazione chiesta dal core (0-65535)

// immagine: l'ultima schermata in BGRX 32 bit, presa dalla vista a ogni giro dello schermo
static os_unfair_lock G_lockImmagine = OS_UNFAIR_LOCK_INIT;
static uint32_t *G_pixel; static unsigned G_w, G_h; static size_t G_cap; static BOOL G_nuova;

// suono: anello di campioni stereo a 16 bit
#define FMLAB_ANELLO (1 << 15)
static int16_t G_anello[FMLAB_ANELLO * 2];
static _Atomic uint32_t G_scrivi, G_leggi;

static bool fmlabVibra(unsigned port, enum retro_rumble_effect effetto, uint16_t forza) {
    if (port == 0) atomic_store(&G_vibra, forza);
    return true;
}

static void fmlabLog(enum retro_log_level level, const char *fmt, ...) {
    if (level < RETRO_LOG_WARN) return;
    char riga[512]; va_list ap; va_start(ap, fmt); vsnprintf(riga, sizeof riga, fmt, ap); va_end(ap);
    NSLog(@"[FMLAB Emulatore] %s", riga);
}

#pragma mark - Grafica su GPU (OpenGL ES): il core disegna sulla scheda grafica, qui si legge l'immagine finita

// Il core (es. PPSSPP) disegna 3D e effetti sulla GPU, a risoluzione più alta; a ogni schermata l'immagine si
// copia nel solito buffer, così schermi DS, TV esterna, filtri e foto restano uguali.
static struct retro_hw_render_callback G_hw;
static bool G_hwAttivo;
static EAGLContext *G_gl;
static GLuint G_fbo, G_coloreRB, G_profRB;
static unsigned G_fboW, G_fboH;
static uint8_t *G_letti; static size_t G_lettiCap;
static uintptr_t fmlabFBO(void) { return G_fbo; }
static retro_proc_address_t fmlabProc(const char *nome) { return (retro_proc_address_t)dlsym(RTLD_DEFAULT, nome); }
static void fmlabPreparaFBO(unsigned w, unsigned h) {
    if (w <= G_fboW && h <= G_fboH && G_fbo) return;
    w = MAX(w, G_fboW); h = MAX(h, G_fboH);
    if (G_fbo) { glDeleteFramebuffers(1, &G_fbo); glDeleteRenderbuffers(1, &G_coloreRB); glDeleteRenderbuffers(1, &G_profRB); }
    glGenFramebuffers(1, &G_fbo); glBindFramebuffer(GL_FRAMEBUFFER, G_fbo);
    glGenRenderbuffers(1, &G_coloreRB); glBindRenderbuffer(GL_RENDERBUFFER, G_coloreRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8, (GLsizei)w, (GLsizei)h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, G_coloreRB);
    glGenRenderbuffers(1, &G_profRB); glBindRenderbuffer(GL_RENDERBUFFER, G_profRB);
    glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, (GLsizei)w, (GLsizei)h);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER, G_profRB);
    G_fboW = w; G_fboH = h;
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) NSLog(@"[FMLAB Emulatore] FBO incompleto %ux%u", w, h);
}
static void fmlabAvviaGPU(void) {
    if (!G_hwAttivo || G_gl) return;
    G_gl = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES3];
    if (!G_gl) G_gl = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
    [EAGLContext setCurrentContext:G_gl];
    fmlabPreparaFBO(MAX(G_av.geometry.max_width, 480), MAX(G_av.geometry.max_height, 272));
    if (G_hw.context_reset) G_hw.context_reset();
}
static void fmlabFermaGPU(void) {
    if (!G_gl) return;
    [EAGLContext setCurrentContext:G_gl];
    if (G_hw.context_destroy) G_hw.context_destroy();
}
static void fmlabChiudiGPU(void) {
    if (!G_gl) return;
    [EAGLContext setCurrentContext:G_gl];
    if (G_fbo) { glDeleteFramebuffers(1, &G_fbo); glDeleteRenderbuffers(1, &G_coloreRB); glDeleteRenderbuffers(1, &G_profRB); }
    G_fbo = G_coloreRB = G_profRB = 0; G_fboW = G_fboH = 0;
    [EAGLContext setCurrentContext:nil]; G_gl = nil; G_hwAttivo = NO; memset(&G_hw, 0, sizeof G_hw);
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
        case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE & ~RETRO_ENVIRONMENT_EXPERIMENTAL: *(bool *)data = atomic_exchange(&G_varNuove, false); return true;
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
        case RETRO_ENVIRONMENT_SET_AUDIO_BUFFER_STATUS_CALLBACK & ~RETRO_ENVIRONMENT_EXPERIMENTAL: {
            const struct retro_audio_buffer_status_callback *c = data; G_statoAudio = c ? c->callback : NULL; return true;
        }
        case RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
            ((struct retro_rumble_interface *)data)->set_rumble_state = fmlabVibra; return true;
        case RETRO_ENVIRONMENT_SET_MESSAGE & ~RETRO_ENVIRONMENT_EXPERIMENTAL: {
            const struct retro_message *m = data; if (m && m->msg) NSLog(@"[FMLAB Emulatore] %s", m->msg); return true;
        }
        case RETRO_ENVIRONMENT_GET_PREFERRED_HW_RENDER & ~RETRO_ENVIRONMENT_EXPERIMENTAL:
            *(unsigned *)data = RETRO_HW_CONTEXT_OPENGLES3; return true;
        case RETRO_ENVIRONMENT_SET_HW_RENDER & ~RETRO_ENVIRONMENT_EXPERIMENTAL: {
            // solo OpenGL ES (l'unico OpenGL dell'iPhone); Vulkan/OpenGL desktop no: il core ripiega sul software
            struct retro_hw_render_callback *cb = data;
            if (!cb || !(cb->context_type == RETRO_HW_CONTEXT_OPENGLES2 || cb->context_type == RETRO_HW_CONTEXT_OPENGLES3 ||
                         cb->context_type == RETRO_HW_CONTEXT_OPENGLES_VERSION)) return false;
            cb->get_current_framebuffer = fmlabFBO; cb->get_proc_address = fmlabProc;
            G_hw = *cb; G_hwAttivo = true; return true;
        }
        default: return false;   // niente Vulkan, niente opzioni v1/v2: il core usa le sue scelte semplici
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

static void fmlabVideoGPU(unsigned w, unsigned h) {
    if (!G_gl || !G_fbo) return;
    w = MIN(w, G_fboW); h = MIN(h, G_fboH);
    size_t serve = (size_t)w * h * 4;
    if (serve > G_lettiCap) { G_lettiCap = serve; G_letti = realloc(G_letti, serve); }
    glBindFramebuffer(GL_FRAMEBUFFER, G_fbo);
    glReadPixels(0, 0, (GLsizei)w, (GLsizei)h, GL_RGBA, GL_UNSIGNED_BYTE, G_letti);
    os_unfair_lock_lock(&G_lockImmagine);
    if ((size_t)w * h > G_cap) { G_cap = (size_t)w * h; G_pixel = realloc(G_pixel, G_cap * 4); }
    vImage_Buffer da = { G_letti, h, w, w * 4 }, a = { G_pixel, h, w, w * 4 };
    const uint8_t mappa[4] = { 2, 1, 0, 3 };   // RGBA → BGRA (come XRGB8888)
    vImagePermuteChannels_ARGB8888(&da, &a, mappa, kvImageNoFlags);
    if (G_hw.bottom_left_origin) vImageVerticalReflect_ARGB8888(&a, &a, kvImageNoFlags);   // GL parte dal basso
    G_w = w; G_h = h; G_nuova = YES;
    os_unfair_lock_unlock(&G_lockImmagine);
}

static void fmlabVideo(const void *data, unsigned w, unsigned h, size_t pitch) {
    if (data == RETRO_HW_FRAME_BUFFER_VALID) { if (w && h) fmlabVideoGPU(w, h); return; }
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
static bool G_croceAnalogica;   // PSP: la croce muove anche la levetta analogica (molti giochi camminano solo con quella)
static int16_t fmlabStato(unsigned port, unsigned device, unsigned index, unsigned id) {
    if (port != 0) return 0;
    if (device == RETRO_DEVICE_ANALOG && G_croceAnalogica && index == RETRO_DEVICE_INDEX_ANALOG_LEFT) {
        uint32_t t = atomic_load(&G_tasti) | atomic_load(&G_tastiController);
        if (id == RETRO_DEVICE_ID_ANALOG_X) return (int16_t)(((t >> RETRO_DEVICE_ID_JOYPAD_RIGHT) & 1) * 32767 - ((t >> RETRO_DEVICE_ID_JOYPAD_LEFT) & 1) * 32767);
        if (id == RETRO_DEVICE_ID_ANALOG_Y) return (int16_t)(((t >> RETRO_DEVICE_ID_JOYPAD_DOWN) & 1) * 32767 - ((t >> RETRO_DEVICE_ID_JOYPAD_UP) & 1) * 32767);
    }
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
        // ProMotion: i giochi a 50 Hz (PAL) su uno schermo a 60 alternano 1 e 2 giri (scatti); a 120 Hz alternano 2 e 3,
        // molto più regolare. 60 Hz (NTSC) resta a 60 esatti; con l'avanti veloce si chiede 120.
        double f = self.emulatore.fps;
        BOOL esatto = fabs(f - 60) < 0.6 || fabs(f - 30) < 0.4;
        if (@available(iOS 15.0, *)) _giro.preferredFrameRateRange = esatto && !self.emulatore.veloce ? CAFrameRateRangeMake(30, 120, 60) : CAFrameRateRangeMake(60, 120, 120);
        [_giro addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
}
- (void)aggiorna {
    os_unfair_lock_lock(&G_lockImmagine);
    if (!G_nuova || !G_pixel) { os_unfair_lock_unlock(&G_lockImmagine); return; }
    unsigned w = G_w, h = G_h;
    static unsigned vecchiaW, vecchiaH;
    if (w != vecchiaW || h != vecchiaH) { vecchiaW = w; vecchiaH = h; dispatch_async(dispatch_get_main_queue(), ^{ [NSNotificationCenter.defaultCenter postNotificationName:@"FMLABMisuraGioco" object:nil]; }); }
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

+ (void)preparaCartelle {
    (void)self.cartellaBIOS; (void)self.cartellaSalvataggi;
    [NSFileManager.defaultManager createDirectoryAtURL:[self.cartellaGiochi URLByAppendingPathComponent:@"Copertine" isDirectory:YES] withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *leggimi = [self.cartellaGiochi URLByAppendingPathComponent:@"LEGGIMI - README.txt"];
    if (![NSFileManager.defaultManager fileExistsAtPath:leggimi.path]) {
        NSString *t = @"FMLAB Linux · Game Emulator\n\n"
            "IT  Metti qui i tuoi giochi (anche in sottocartelle): NES .nes, Game Boy .gb .gbc, GBA .gba, SNES .sfc .smc,\n"
            "    PlayStation .cue/.bin .chd .pbp, Nintendo DS .nds. Gli zip vanno decompressi. I BIOS (se servono) in BIOS,\n"
            "    i salvataggi finiscono in Salvataggi, le copertine (stesso nome del gioco, .png/.jpg) in Copertine.\n    FMLAB non include né scarica giochi: usa solo file che possiedi.\n\n"
            "EN  Put your games here (subfolders are fine): NES .nes, Game Boy .gb .gbc, GBA .gba, SNES .sfc .smc,\n"
            "    PlayStation .cue/.bin .chd .pbp, Nintendo DS .nds. Unzip zipped games. BIOS files (if needed) go in BIOS,\n"
            "    saves go to Salvataggi, covers (same name as the game, .png/.jpg) go in Copertine.\n    FMLAB neither ships nor downloads games: only use files you own.\n";
        [t writeToURL:leggimi atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

+ (void)usaOpzioniUtente:(NSDictionary<NSString *, NSString *> *)opzioni { @synchronized (self) { G_opzioniUtente = [opzioni copy]; } }
+ (void)usaDati:(NSDictionary<NSString *, NSDictionary *> *)core {
    NSMutableDictionary *est = [FMLABEstensioni() mutableCopy], *opz = [NSMutableDictionary dictionary];
    for (NSString *n in core) {
        NSDictionary *c = core[n]; if (![c isKindOfClass:NSDictionary.class]) continue;
        NSArray *e = c[@"estensioni"]; if ([e isKindOfClass:NSArray.class] && e.count) est[n] = e;
        NSDictionary *o = c[@"opzioni"]; if ([o isKindOfClass:NSDictionary.class]) opz[n] = o;
    }
    @synchronized (self) { G_estensioni = est; G_opzioniCore = opz; G_tuttiCore = nil; }
}

static NSError *fmlabErrore(NSString *messaggio);
static BOOL fmlabArchivio(struct archive *a) {
    archive_read_support_filter_all(a);
    archive_read_support_format_zip(a); archive_read_support_format_7zip(a);
    archive_read_support_format_rar(a); archive_read_support_format_rar5(a);
    return YES;
}
+ (FMLABCore *)coreDentroArchivio:(NSString *)archivio {
    struct archive *a = archive_read_new(); fmlabArchivio(a);
    FMLABCore *trovato = nil;
    if (archive_read_open_filename(a, archivio.fileSystemRepresentation, 1 << 16) == ARCHIVE_OK) {
        struct archive_entry *e; int giri = 0;
        while (!trovato && giri++ < 64 && archive_read_next_header(a, &e) == ARCHIVE_OK) {
            const char *n = archive_entry_pathname(e); if (!n || archive_entry_filetype(e) != AE_IFREG) continue;
            NSString *nome = @(n).lastPathComponent; if ([nome hasPrefix:@"."]) continue;
            trovato = [self corePer:nome];
            if ([nome.pathExtension.lowercaseString isEqual:@"bin"]) trovato = nil;   // da solo non basta: serve il .cue
            NSString *est = nome.pathExtension.lowercaseString;
            if (trovato && [@[@"iso", @"pbp", @"cso"] containsObject:est]) {
                // si legge l'inizio del file dentro l'archivio (fino a 1 MB) per capire se è PSP o PlayStation
                NSMutableData *inizio = [NSMutableData data]; char b[1 << 16]; la_ssize_t k;
                while (inizio.length < (1 << 20) && (k = archive_read_data(a, b, sizeof b)) > 0) [inizio appendBytes:b length:(NSUInteger)k];
                NSString *n = fmlabSistemaDa(est, inizio, ^NSData *(uint64_t da, NSUInteger q) {
                    return da + q <= inizio.length ? [inizio subdataWithRange:NSMakeRange((NSUInteger)da, q)] : nil; });
                FMLABCore *c = n ? [self coreNome:n] : nil;
                if (c && [c.estensioni containsObject:est]) trovato = c;
            }
        }
    }
    archive_read_free(a);
    return trovato;
}
+ (NSString *)nomeDentroArchivio:(NSString *)archivio {
    struct archive *a = archive_read_new(); fmlabArchivio(a);
    NSString *trovato = nil, *disco = nil;
    if (archive_read_open_filename(a, archivio.fileSystemRepresentation, 1 << 16) == ARCHIVE_OK) {
        struct archive_entry *e; int giri = 0;
        while (giri++ < 64 && archive_read_next_header(a, &e) == ARCHIVE_OK) {
            const char *n = archive_entry_pathname(e); if (!n || archive_entry_filetype(e) != AE_IFREG) continue;
            NSString *nome = @(n).lastPathComponent, *est = nome.pathExtension.lowercaseString; if ([nome hasPrefix:@"."]) continue;
            if ([est isEqual:@"cue"] || [est isEqual:@"m3u"]) { disco = nome.stringByDeletingPathExtension; break; }
            if (!trovato && ![est isEqual:@"bin"] && [self corePer:nome]) trovato = nome.stringByDeletingPathExtension;
        }
    }
    archive_read_free(a);
    return disco ?: trovato;
}
+ (NSString *)preparaArchivio:(NSString *)archivio error:(NSError **)error {
    NSDictionary *at = [NSFileManager.defaultManager attributesOfItemAtPath:archivio error:nil];
    // cartella nella cache: nome + dimensione + data (se il file cambia si estrae di nuovo)
    NSString *chiave = [NSString stringWithFormat:@"%@|%@|%@", archivio.lastPathComponent, at[NSFileSize], at[NSFileModificationDate]];
    unsigned char h[CC_SHA256_DIGEST_LENGTH]; NSData *d = [chiave dataUsingEncoding:NSUTF8StringEncoding]; CC_SHA256(d.bytes, (CC_LONG)d.length, h);
    NSMutableString *sigla = [NSMutableString string]; for (int i = 0; i < 8; i++) [sigla appendFormat:@"%02x", h[i]];
    NSURL *cache = [[NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"FMLAB-Giochi" isDirectory:YES];
    NSURL *dest = [cache URLByAppendingPathComponent:sigla isDirectory:YES];
    NSURL *fatto = [dest URLByAppendingPathComponent:@".pronto"];
    if (![NSFileManager.defaultManager fileExistsAtPath:fatto.path]) {
        [NSFileManager.defaultManager removeItemAtURL:cache error:nil];   // si tiene solo l'ultimo gioco estratto: niente spazio sprecato
        [NSFileManager.defaultManager createDirectoryAtURL:dest withIntermediateDirectories:YES attributes:nil error:nil];
        struct archive *a = archive_read_new(); fmlabArchivio(a);
        if (archive_read_open_filename(a, archivio.fileSystemRepresentation, 1 << 16) != ARCHIVE_OK) {
            archive_read_free(a); if (error) *error = fmlabErrore(@"The archive could not be opened."); return nil;
        }
        struct archive_entry *e; int r = ARCHIVE_OK; char buf[1 << 16];
        while ((r = archive_read_next_header(a, &e)) == ARCHIVE_OK) {
            const char *n = archive_entry_pathname(e);
            if (!n || archive_entry_filetype(e) != AE_IFREG) continue;
            NSString *nome = @(n).lastPathComponent;   // solo il nome: niente cartelle, niente "../"
            if (nome.length == 0 || [nome hasPrefix:@"."]) continue;
            FILE *f = fopen([dest URLByAppendingPathComponent:nome].fileSystemRepresentation, "wb"); if (!f) { r = ARCHIVE_FATAL; break; }
            la_ssize_t k; while ((k = archive_read_data(a, buf, sizeof buf)) > 0) fwrite(buf, 1, (size_t)k, f);
            fclose(f); if (k < 0) { r = ARCHIVE_FATAL; break; }
        }
        archive_read_free(a);
        if (r != ARCHIVE_EOF) { [NSFileManager.defaultManager removeItemAtURL:dest error:nil]; if (error) *error = fmlabErrore(@"The archive could not be extracted (damaged or protected by a password)."); return nil; }
        [@"" writeToURL:fatto atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    // il file da aprire: prima .cue/.m3u (dischi), poi il primo che un emulatore riconosce
    NSArray *files = [[NSFileManager.defaultManager contentsOfDirectoryAtPath:dest.path error:nil] sortedArrayUsingSelector:@selector(compare:)];
    for (NSArray *preferite in @[@[@"m3u", @"cue"], @[]]) for (NSString *n in files) {
        NSString *e = n.pathExtension.lowercaseString; if ([n hasPrefix:@"."]) continue;
        if (preferite.count ? [preferite containsObject:e] : ([self corePer:n] && ![e isEqual:@"bin"])) return [dest URLByAppendingPathComponent:n].path;
    }
    if (error) *error = fmlabErrore(@"There is no game this emulator can open inside the archive.");
    return nil;
}

+ (NSArray<FMLABCore *> *)core {
    @synchronized (self) {
    if (G_tuttiCore) return G_tuttiCore;
    NSArray *tutti;
    {
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
        // in ordine di uscita delle console
        NSArray *ordine = @[@"fceumm", @"gambatte", @"bsnes", @"pcsx_rearmed", @"mgba", @"desmume", @"ppsspp"];
        [a sortUsingComparator:^NSComparisonResult(FMLABCore *x, FMLABCore *y) {
            NSUInteger i = [ordine indexOfObject:x.nome], j = [ordine indexOfObject:y.nome];
            return i < j ? NSOrderedAscending : i > j ? NSOrderedDescending : NSOrderedSame;
        }];
        tutti = a;
    }
    G_tuttiCore = tutti;
    return tutti;
    }
}
+ (FMLABCore *)corePer:(NSString *)file {
    NSString *e = file.pathExtension.lowercaseString;
    // .bin da solo è ambiguo: lo prende la PlayStation solo se non c'è un .cue accanto
    for (FMLABCore *c in self.core) if ([c.estensioni containsObject:e]) return c;
    return nil;
}

// .iso e .pbp esistono sia per PlayStation sia per PSP: si guarda dentro.
//   ISO PSP: identificativo di sistema "PSP GAME" nel descrittore del volume (0x8008)
//   PBP: se i dati (DATA.PSAR) iniziano con PSISOIMG/PSTITLEIMG è un gioco PlayStation convertito, se no è PSP
static NSString *fmlabSistemaDa(NSString *est, NSData *testa, NSData *(^leggi)(uint64_t da, NSUInteger n)) {
    if ([est isEqual:@"cso"]) return @"ppsspp";
    if ([est isEqual:@"iso"]) { NSData *d = leggi(0x8008, 8); return d && memcmp(d.bytes, "PSP GAME", 8) == 0 ? @"ppsspp" : @"pcsx_rearmed"; }
    if ([est isEqual:@"pbp"]) {
        NSData *h = leggi(0, 0x28); if (h.length < 0x28 || memcmp(h.bytes, "\0PBP", 4) != 0) return @"pcsx_rearmed";
        uint32_t psar; memcpy(&psar, (const uint8_t *)h.bytes + 0x24, 4); psar = CFSwapInt32LittleToHost(psar);
        NSData *p = leggi(psar, 8);
        return p.length == 8 && (memcmp(p.bytes, "PSISOIMG", 8) == 0 || memcmp(p.bytes, "PSTITLEI", 8) == 0) ? @"pcsx_rearmed" : @"ppsspp";
    }
    return nil;
}
+ (FMLABCore *)coreNome:(NSString *)n { for (FMLABCore *c in self.core) if ([c.nome isEqual:n]) return c; return nil; }
+ (FMLABCore *)corePerFile:(NSString *)percorso {
    NSString *e = percorso.pathExtension.lowercaseString;
    if ([@[@"iso", @"pbp", @"cso"] containsObject:e]) {
        NSFileHandle *h = [NSFileHandle fileHandleForReadingAtPath:percorso];
        NSString *n = fmlabSistemaDa(e, nil, ^NSData *(uint64_t da, NSUInteger k) {
            if (!h) return nil; @try { [h seekToFileOffset:da]; return [h readDataOfLength:k]; } @catch (id x) { return nil; } });
        [h closeFile];
        FMLABCore *c = n ? [self coreNome:n] : nil;
        if (c && [c.estensioni containsObject:e]) return c;
    }
    return [self corePer:percorso.lastPathComponent];
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
    if ([core.nome isEqual:@"ppsspp"]) {
        // i file di sistema di PPSSPP (font del firmware, compat.ini) viaggiano dentro il core: si copiano una volta
        NSFileManager *fm = NSFileManager.defaultManager;
        NSURL *sis = [[fm URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"FMLAB/Sistema" isDirectory:YES];
        NSString *sorgente = [core.percorso.stringByDeletingLastPathComponent stringByAppendingPathComponent:@"PPSSPP"];
        NSURL *dest = [sis URLByAppendingPathComponent:@"PPSSPP" isDirectory:YES], *segno = [dest URLByAppendingPathComponent:@".fmlab"];
        NSString *versione = [NSString stringWithFormat:@"%@", [fm attributesOfItemAtPath:core.percorso error:nil][NSFileSize]];
        NSString *ce = [NSString stringWithContentsOfURL:segno encoding:NSUTF8StringEncoding error:nil];
        if ([fm fileExistsAtPath:sorgente] && ![ce isEqual:versione]) {
            [fm createDirectoryAtURL:dest withIntermediateDirectories:YES attributes:nil error:nil];
            for (NSString *n in [fm contentsOfDirectoryAtPath:sorgente error:nil]) {
                NSURL *u = [dest URLByAppendingPathComponent:n]; [fm removeItemAtURL:u error:nil];
                [fm copyItemAtPath:[sorgente stringByAppendingPathComponent:n] toPath:u.path error:nil];
            }
            [versione writeToURL:segno atomically:YES encoding:NSUTF8StringEncoding error:nil];
        }
        strlcpy(G_sistema, sis.fileSystemRepresentation, sizeof G_sistema);
    }
    strlcpy(G_salvataggi, FMLABEmulatore.cartellaSalvataggi.fileSystemRepresentation, sizeof G_salvataggi);
    G_opzioni = [FMLABOpzioniFisse(core.nome) mutableCopy];
    @synchronized (FMLABEmulatore.class) { for (NSString *k in G_opzioniUtente) if ([k hasPrefix:[core.nome componentsSeparatedByString:@"_"].firstObject]) G_opzioni[k] = G_opzioniUtente[k]; }
    _salvaUscita = YES;
    G_croceAnalogica = [core.nome isEqual:@"ppsspp"];
    G_hwAttivo = NO; memset(&G_hw, 0, sizeof G_hw);
    G_formato = RETRO_PIXEL_FORMAT_0RGB1555; G_statoAudio = NULL; atomic_store(&G_vibra, 0);
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
- (void)opzione:(NSString *)chiave valore:(NSString *)valore {
    [self lavoro:^{
        if ([G_opzioni[chiave] isEqual:valore]) return;
        G_opzioni[chiave] = valore; atomic_store(&G_varNuove, true);
    }];
}
- (FMLABCore *)coreUsato { return _core; }
- (NSInteger)disposizione {
    if ([@[@"fceumm", @"gambatte"] containsObject:_core.nome]) return 0;
    if ([_core.nome isEqual:@"mgba"]) return 1;
    if ([@[@"pcsx_rearmed", @"ppsspp"] containsObject:_core.nome]) return 3;   // simboli PlayStation
    return 2;
}
- (CGSize)misuraImmagine { os_unfair_lock_lock(&G_lockImmagine); CGSize m = CGSizeMake(G_w, G_h); os_unfair_lock_unlock(&G_lockImmagine); return m; }
- (double)fps { return G_av.timing.fps > 1 ? G_av.timing.fps : 60; }
- (double)fpsVeri {
    static uint64_t prima; static uint32_t contati; static double ultimo;
    uint64_t ora = mach_absolute_time(); mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    double dt = (double)(ora - prima) * tb.numer / tb.denom / 1e9;
    if (dt >= 0.5) { uint32_t n = atomic_load(&G_fotogrammi); if (prima) ultimo = (n - contati) / dt; contati = n; prima = ora; }
    return ultimo;
}
- (CGFloat)rapporto {
    if (self.tocco) { os_unfair_lock_lock(&G_lockImmagine); unsigned w = G_w, h = G_h; os_unfair_lock_unlock(&G_lockImmagine); if (w && h) return (CGFloat)w / h; }
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

static uint32_t fmlabTastiera(void) {
    if (@available(iOS 14.0, *)) {
        GCKeyboardInput *k = GCKeyboard.coalescedKeyboard.keyboardInput; if (!k) return 0;
        uint32_t t = 0;
        #define K(codice, id) if ([k buttonForKeyCode:codice].pressed) t |= 1u << id;
        K(GCKeyCodeUpArrow, RETRO_DEVICE_ID_JOYPAD_UP) K(GCKeyCodeDownArrow, RETRO_DEVICE_ID_JOYPAD_DOWN)
        K(GCKeyCodeLeftArrow, RETRO_DEVICE_ID_JOYPAD_LEFT) K(GCKeyCodeRightArrow, RETRO_DEVICE_ID_JOYPAD_RIGHT)
        K(GCKeyCodeKeyX, RETRO_DEVICE_ID_JOYPAD_A) K(GCKeyCodeKeyZ, RETRO_DEVICE_ID_JOYPAD_B)
        K(GCKeyCodeKeyS, RETRO_DEVICE_ID_JOYPAD_X) K(GCKeyCodeKeyA, RETRO_DEVICE_ID_JOYPAD_Y)
        K(GCKeyCodeKeyQ, RETRO_DEVICE_ID_JOYPAD_L) K(GCKeyCodeKeyW, RETRO_DEVICE_ID_JOYPAD_R)
        K(GCKeyCodeReturnOrEnter, RETRO_DEVICE_ID_JOYPAD_START) K(GCKeyCodeSpacebar, RETRO_DEVICE_ID_JOYPAD_SELECT)
        K(GCKeyCodeRightShift, RETRO_DEVICE_ID_JOYPAD_SELECT)
        #undef K
        return t;
    }
    return 0;
}

- (void)giro {
    mach_timebase_info_data_t tb; mach_timebase_info(&tb);
    double secondi = (double)tb.numer / tb.denom / 1e9;
    double periodo = 1.0 / self.fps;
    uint64_t prossimo = mach_absolute_time();
    fmlabAvviaGPU();   // se il core disegna su GPU: contesto e framebuffer su questo filo, prima del primo retro_run
    while (!atomic_load(&_ferma)) {
        os_unfair_lock_lock(&_lockLavori); NSArray *da = [_lavori copy]; [_lavori removeAllObjects]; os_unfair_lock_unlock(&_lockLavori);
        for (dispatch_block_t b in da) b();
        if (self.inPausa) { usleep(20000); prossimo = mach_absolute_time(); continue; }
        uint32_t pad = 0;
        for (GCController *c in GCController.controllers) pad |= fmlabPad(c.extendedGamepad);
        pad |= fmlabTastiera();
        atomic_store(&G_tastiController, pad);
        uint32_t inCoda = atomic_load(&G_scrivi) - atomic_load(&G_leggi);
        double hz = G_av.timing.sample_rate > 1000 ? G_av.timing.sample_rate : 44100;
        if (G_statoAudio) {   // 100% = 0,1 s di suono pronto; sotto il 25% il core può saltare un fotogramma
            unsigned occ = (unsigned)MIN(100.0, inCoda / (hz * 0.1) * 100.0);
            G_statoAudio(true, occ, occ < 25);
        }
        @autoreleasepool { F.run(); }
        atomic_fetch_add(&G_fotogrammi, 1);
        uint32_t forza = atomic_exchange(&G_vibra, 0);
        NSUserDefaults *preferenze = NSUserDefaults.standardUserDefaults;
        if (forza > 8000 && ([preferenze objectForKey:@"FMLAB.comandi.vibra"] ? [preferenze boolForKey:@"FMLAB.comandi.vibra"] : YES)) {
            static uint64_t ultima; uint64_t ora = mach_absolute_time();
            if ((ora - ultima) * secondi > 0.12) { ultima = ora;
                CGFloat i = MIN(1.0, forza / 65535.0);
                dispatch_async(dispatch_get_main_queue(), ^{ UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleHeavy]; [g impactOccurredWithIntensity:i]; });
            }
        }
        if (G_avCambiato) { G_avCambiato = NO; periodo = 1.0 / self.fps; }
        // se il suono è molto avanti, si aspetta un po' di più (resta in pari con l'audio)
        // ritmo legato al suono: troppo avanti si aspetta un po' di più, quasi vuoto si va un filo più svelti
        uint32_t coda = atomic_load(&G_scrivi) - atomic_load(&G_leggi);
        // correzione dolce (come il "dynamic rate control" di RetroArch): al massimo ±1,5% per fotogramma, così ogni
        // fotogramma dura quasi uguale e il movimento resta fluido; solo con il suono molto avanti si frena di più
        double scarto = coda / hz - 0.06;
        double extra = coda > (uint32_t)(hz * 0.3) ? periodo * 0.25 : periodo * MAX(-0.015, MIN(0.015, scarto * 0.4));
        if (self.veloce) { double v = self.velocita >= 1.5 ? MIN(self.velocita, 8) : 3; extra = -periodo * (1 - 1 / v); }   // avanti veloce (il suono in più si scarta)
        prossimo += (uint64_t)((periodo + extra) / secondi);
        uint64_t ora = mach_absolute_time();
        if (ora < prossimo) mach_wait_until(prossimo);
        else if ((ora - prossimo) * secondi > 0.25) prossimo = ora;   // troppo indietro: si riparte da adesso
    }
    os_unfair_lock_lock(&_lockLavori); NSArray *rimasti = [_lavori copy]; [_lavori removeAllObjects]; os_unfair_lock_unlock(&_lockLavori);
    for (dispatch_block_t b in rimasti) b();
    if (_salvaUscita) {   // "riprendi da dove eri"
        size_t n = F.serSize(); NSMutableData *d = [NSMutableData dataWithLength:n];
        if (n && F.ser(d.mutableBytes, n)) [d writeToURL:[self fileSalvataggio:@"auto.state"] atomically:YES];
    }
    [self scriviMemoria];
    fmlabFermaGPU();
    F.unload(); F.deinit();
    fmlabChiudiGPU();
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

- (UIImage *)fotografia {
    os_unfair_lock_lock(&G_lockImmagine);
    if (!G_pixel || !G_w || !G_h) { os_unfair_lock_unlock(&G_lockImmagine); return nil; }
    unsigned w = G_w, h = G_h; NSData *copia = [NSData dataWithBytes:G_pixel length:(size_t)w * h * 4];
    os_unfair_lock_unlock(&G_lockImmagine);
    CGDataProviderRef dati = CGDataProviderCreateWithCFData((__bridge CFDataRef)copia);
    CGColorSpaceRef spazio = CGColorSpaceCreateDeviceRGB();
    CGImageRef img = CGImageCreate(w, h, 8, 32, w * 4, spazio, kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst, dati, NULL, false, kCGRenderingIntentDefault);
    // più grande e a pixel netti, come si vede sul telefono (con le proporzioni giuste del gioco)
    CGFloat r = self.rapporto > 0.1 ? self.rapporto : (CGFloat)w / h, scala = MAX(1, floor(720.0 / h));
    CGSize misura = CGSizeMake(round(h * scala * r), h * scala);
    UIGraphicsImageRendererFormat *f = [UIGraphicsImageRendererFormat preferredFormat]; f.scale = 1;
    UIImage *foto = [[[UIGraphicsImageRenderer alloc] initWithSize:misura format:f] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        CGContextSetInterpolationQuality(c.CGContext, kCGInterpolationNone);
        CGContextTranslateCTM(c.CGContext, 0, misura.height); CGContextScaleCTM(c.CGContext, 1, -1);
        CGContextDrawImage(c.CGContext, CGRectMake(0, 0, misura.width, misura.height), img);
    }];
    CGImageRelease(img); CGColorSpaceRelease(spazio); CGDataProviderRelease(dati);
    return foto;
}
- (NSString *)nomePosto:(NSInteger)posto { return posto <= 1 ? @"state" : [NSString stringWithFormat:@"state%ld", (long)posto]; }
- (void)salvaStato:(NSInteger)posto fatto:(void (^)(NSError *))fatto {
    UIImage *foto = [self fotografia];
    [self lavoro:^{
        size_t n = F.serSize(); NSMutableData *d = [NSMutableData dataWithLength:n];
        NSError *e = nil;
        if (!n || !F.ser(d.mutableBytes, n)) e = fmlabErrore(@"This game cannot be saved right now.");
        else [d writeToURL:[self fileSalvataggio:[self nomePosto:posto]] options:NSDataWritingAtomic error:&e];
        if (!e && foto) [UIImagePNGRepresentation(foto) writeToURL:[self fileSalvataggio:[[self nomePosto:posto] stringByAppendingString:@".png"]] atomically:YES];
        [self scriviMemoria];
        dispatch_async(dispatch_get_main_queue(), ^{ fatto(e); });
    }];
}
- (void)caricaStato:(NSInteger)posto fatto:(void (^)(NSError *))fatto {
    [self lavoro:^{
        NSData *d = [NSData dataWithContentsOfURL:[self fileSalvataggio:[self nomePosto:posto]]];
        NSError *e = (!d || !F.unser(d.bytes, d.length)) ? fmlabErrore(@"The saved state could not be loaded.") : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ fatto(e); });
    }];
}
- (NSDate *)dataStato:(NSInteger)posto {
    return [NSFileManager.defaultManager attributesOfItemAtPath:[self fileSalvataggio:[self nomePosto:posto]].path error:nil][NSFileModificationDate];
}
- (UIImage *)fotoStato:(NSInteger)posto {
    return [UIImage imageWithContentsOfFile:[self fileSalvataggio:[[self nomePosto:posto] stringByAppendingString:@".png"]].path];
}
- (BOOL)statoAutomaticoEsiste { return [NSFileManager.defaultManager fileExistsAtPath:[self fileSalvataggio:@"auto.state"].path]; }
- (void)caricaAutomatico:(void (^)(NSError *))fatto {
    [self lavoro:^{
        NSData *d = [NSData dataWithContentsOfURL:[self fileSalvataggio:@"auto.state"]];
        NSError *e = (!d || !F.unser(d.bytes, d.length)) ? fmlabErrore(@"The saved state could not be loaded.") : nil;
        dispatch_async(dispatch_get_main_queue(), ^{ fatto(e); });
    }];
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
