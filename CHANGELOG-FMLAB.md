# Changelog — FMLAB Linux

Storico delle versioni FMLAB. Le novità di LinuxRunner originale sono in [CHANGELOG.md](CHANGELOG.md).

## 0.10.6
- **AirPlay con i giochi, come per Linux**: con un gioco aperto l'app chiede a iOS lo schermo esterno separato
  (lo stesso meccanismo del desktop Linux) anche se l'*Uscita desktop esterna* è spenta. Con Duplica schermo attiva
  la TV mostra solo il gioco e il telefono diventa **solo il controller** (sul DS il telefono tiene gli schermi per
  il tocco). Se colleghi la TV mentre giochi, o si stacca, se ne accorge da solo entro un secondo e mezzo.
- Scheda Giochi › AirPlay e TV: con la sola duplicazione attiva scrive *Duplicazione attiva: apri un gioco*.
- DS in orizzontale (*Schermo principale grande*): lo schermo da toccare sta in alto a destra e non arriva più sopra
  la X.
- README: foto nuove (DS in orizzontale, dati che chiedono, AirPlay) e tolte quelle vecchie o doppie.
- *Copia rapporto* dice anche se lo schermo esterno c'è e se il gioco lo sta usando.

## 0.10.5
- **Cerca TV AirPlay dall'app**: nella scheda Giochi (AirPlay e TV), in Impostazioni › Dispositivi e nel menu del
  gioco (*TV AirPlay…*) si apre l'elenco di sistema dei dispositivi AirPlay vicini; sceglierne uno manda lì il suono.
  Per l'immagine resta Duplica schermo del Centro di Controllo: iOS non lascia avviarla a nessuna app (lo dice anche
  la spiegazione, con il percorso giusto per il desktop Linux: Impostazioni › Dispositivi).
- **Sposta i tasti, più chiaro**: una scheda vera (titolo, spiegazione, *Ripristina* e *Fine* grandi) sopra il gioco
  in pausa invece della striscia che finiva sopra la X; in orizzontale sta al centro. Il tasto che stai spostando si
  illumina e vibra quando lo prendi.

## 0.10.4
- **DS in orizzontale a tutto schermo**: prima gli schermi affiancati dovevano stare in larghezza, quindi restavano
  bassi con tanto nero sopra e sotto. Ora l'app divide da sola l'immagine del DS: lo **schermo principale va a
  tutta altezza** e quello da toccare sta accanto, più piccolo, sotto L/R. Menu del gioco › *Schermi DS in
  orizzontale…* per scegliere *Schermo principale grande* o *Affiancati* (uguali, da bordo a bordo); *Scambia gli
  schermi* mette in grande quello che si tocca (per i giochi tutti a tocco). Girando non si riconfigura più il core.
- I tasti spostati si salvano anche per ognuna delle due disposizioni.

## 0.10.3
- **Tasti personalizzabili per gioco/console**: menu del gioco › *Sposta i tasti…*: il gioco va in pausa, trascini
  croce, tasti, Menu e avanti veloce dove vuoi e li ingrandisci o rimpicciolisci pizzicando. Si salvano per console e
  per verticale/orizzontale (*Ripristina* torna come prima, *Fine* salva).
- **Rinomina i giochi** (tieni premuto o scorri sul gioco › *Rinomina…*): il file non cambia, salvataggi e copertine
  restano collegati; *Nome originale* torna indietro. Di base il nome è ora il **titolo vero del gioco**: sul DS
  quello del banner, in italiano se l'app è in italiano (es. *Pokémon Versione Perla* invece di `[PKWWF]pkdm`);
  GBA e SNES dall'intestazione.
- **Grafica migliorata** (Giochi › Grafica, accesa di base): 3D del DS a risoluzione doppia, PlayStation a 2×,
  Mode 7 dello SNES in HD. Filtri dell'immagine: *Pixel netti*, *Morbido*, *TV (righe)*, *LCD portatile*, allineati
  ai pixel del gioco.
- **DS in verticale**: i comandi non coprono più lo schermo che si tocca (il gioco si ferma al 70% e i comandi
  stanno sotto); in orizzontale restano sempre ai lati.
- **Dati del motore: chiede sempre**, tranne le correzioni gravi: se fmlab-retro segna i dati come `urgente`
  (es. un'opzione che blocca un gioco) si applicano subito e la scheda Giochi lo dice.
- **AirPlay e TV anche nella scheda Giochi**, separato da quello del desktop Linux: si vede lo schermo collegato e
  si può scegliere se usarlo per i giochi.

## 0.10.2
- **Schermo più grande** (Giochi › Comandi e salvataggi, acceso di base): il gioco prende tutto lo spazio che può e
  i comandi gli stanno sopra, trasparenti. Sul DS in verticale gli schermi vanno a tutta larghezza, in orizzontale
  affiancati da bordo a bordo.
- **AirPlay / monitor / TV**: con uno schermo esterno collegato il gioco va lì a tutto schermo e il telefono fa da
  controller, con i comandi grandi. Sul DS il telefono tiene anche gli schermi (quello di sotto si tocca) e la TV li
  mostra in grande. Si collega e scollega anche durante il gioco.

## 0.10.1
- **Dati del motore: prima si chiede**. Nella scheda Giochi FMLAB controlla, scarica e verifica i dati nuovi, ma
  non li usa da solo: compare *Aggiornamento dei dati del motore disponibile* con la versione, le novità e quella in
  uso, e i tasti **Aggiorna ora** / **Più tardi**. Con *Più tardi* resta tutto com'è e lo richiede la volta dopo.
- **Dopo l'aggiornamento si pulisce**: via la copia in attesa, i giochi estratti dagli archivi nella cache e le
  copie di sicurezza temporanee; si vede quanto spazio è stato liberato. Le copertine non trovate si ricercano.
- Tutto questo succede solo nella scheda Giochi.

## 0.10.0
- **Scheda Giochi** nella barra in basso (Home · Distribuzioni · Giochi · Sessioni · Impostazioni): il Game Emulator
  non sta più dentro Distribuzioni. I dati del motore (barra, avviso, controllo) si vedono solo lì dentro; si
  controllano quando apri la scheda o torni nell'app con la scheda aperta (al massimo ogni 2 minuti).
- **Giochi zippati** (.zip, .7z, .rar) direttamente: la console si riconosce dai file dentro, si estrae al momento
  di giocare nella cache dell'app (l'archivio resta com'è; si tiene solo l'ultimo estratto).
- **Motore**: il suono resta in pari col gioco anche quando è indietro (meno scricchiolii); i core sanno quanto suono
  è pronto, così PlayStation e GBA possono saltare un fotogramma da soli se il telefono non ce la fa; **vibrazione**
  nei giochi che la usano (Game Boy con rumble, controller PlayStation).
- Idee prese da Delta, Manic EMU, Provenance e RetroArch:
  - **3 posti per gli stati salvati**, ognuno con data e foto della schermata
  - **Tieni premuto un tasto** (es. correre) finché non lo lasci dal menu
  - **velocità dell'avanti veloce** 2×, 3× o 4×
  - **foto della partita** in Giochi › Foto
  - **copertine automatiche** dalla raccolta pubblica libretro-thumbnails (nomi di file standard), disattivabili
  - **Scambia schermi** sul DS

## 0.9.9
- **Codice FMLAB separato anche nella parte Objective-C**: misura "Telefono", rotazione del desktop, lato della
  fotocamera e margini per RunnerKit in `app/FMLAB/GUIViewController+FMLAB.inc.m`; eliminazione sicura dei file
  condivisi in `app/FMLAB/RuntimeBridge+FMLAB.inc.m`. Nei file di LinuxRunner resta solo una riga che li include.
  Il controllo delle traduzioni guarda anche questi file.
- Game Emulator, **Copia rapporto** quando un gioco non parte (versione, console, core, tipo di file, dati del
  motore, errore; niente percorsi personali) da incollare in un messaggio.
- Game Emulator, **copia di sicurezza**: *Esporta copia…* salva in File/iCloud una cartella con salvataggi, stati,
  BIOS, copertine e impostazioni (i giochi no); *Rimetti una copia…* la ripristina, anche su un altro iPhone.
- Su fmlab-retro: **prove automatiche dei core** (stessi commit, compilati per Linux) con giochi di prova liberi e
  controllo che ogni opzione dei dati esista davvero nel core.

## 0.9.8
- **Nintendo DS più grande**: in verticale gli schermi usano fino al 70% dell'altezza (quasi tutta la larghezza);
  in orizzontale si mettono **affiancati** (circa un quarto più grandi), con lo spazio giusto ai lati per croce e
  tasti, così non coprono gli schermi. Il cambio lo fa l'emulatore mentre giri il telefono e il pennino resta
  giusto. Più in generale l'immagine si risistema da sola quando un gioco cambia misura.
- **Codice FMLAB separato da LinuxRunner**: le funzioni FMLAB (aggiornamenti, informazioni, RunnerKit,
  importazione delle distribuzioni, pulizia) sono uscite da `ManagerView.swift` in `app/FMLAB/FMLABFunzioni.swift`;
  il Game Emulator sta in `app/FMLAB/Emulatore/`. Aggiornare la base LinuxRunner tocca meno codice nostro.

## 0.9.7
- **Dati del motore controllati all'apertura**: ogni volta che apri o riapri FMLAB Linux (e il Game Emulator), al
  massimo ogni 10 minuti, invece che ogni 6 ore. Il file è di pochi KB.
- **Barra di aggiornamento**: in alto nell'app, nella riga Game Emulator e nel Game Emulator si vede cosa sta
  facendo (controllo → scarico, con l'avanzamento vero → verifico → aggiornati / già aggiornati / errore).
- **Avviso dei dati nuovi**: quando arrivano, pallino rosso e "Dati nuovi" sulla riga Game Emulator e un riquadro
  in cima al Game Emulator con la versione e cosa è cambiato (testo "novita" dei dati), finché tocchi OK.

## 0.9.6
- Game Emulator, sezione **Console** rifatta: per ogni console sigla colorata, nome e nota (dai dati del motore,
  quindi cambiano senza nuova app), numero di giochi trovati ed estensioni.
- Nuova sezione **Dati del motore**: versione in uso, ultimo controllo, esito (aggiornati / già aggiornati /
  nessuna connessione / dati scartati) e *Controlla ora*.
- *Solo giochi* in una riga a parte. Schermate nuove dal telefono nel README.

## 0.9.5
- **Dati del motore da fmlab-retro, senza nuova app**: estensioni, opzioni degli emulatori, BIOS controllati e avvisi
  arrivano da `fmlab-retro/dati/emulatore.json`. Il Game Emulator li scarica da solo (al massimo ogni 6 ore, o
  tirando giù la lista), li controlla come le prove di GitHub e li usa dal gioco successivo. Senza rete valgono
  l'ultima copia o quella dentro l'app. Il codice degli emulatori resta nell'app (iOS non esegue codice scaricato).
- **Riprendi da dove eri**: uscendo da un gioco si salva da solo; la volta dopo chiede *Continua* o *Dall'inizio*.
- **Giocati di recente** in cima all'elenco.
- **BIOS**: elenco dei BIOS facoltativi con controllo dell'impronta (sigillo verde = file giusto).
- **Comandi**: dimensione (piccoli, normali, grandi), trasparenza, vibrazione sì/no.

## 0.9.4
- Game Emulator: **icone dei giochi** nell'elenco. I giochi DS mostrano l'icona che hanno dentro (letta dal file);
  per le altre console vale una copertina con lo stesso nome del gioco (.png/.jpg) accanto al file o in
  *Giochi/Copertine*; se no un riquadro col colore e la sigla della console (NES, GB, GBC, GBA, SNES, PS1, DS).

## 0.9.3
- Game Emulator, **cartelle dei giochi**: *Scegli la cartella dei giochi…* collega una tua cartella (Sul mio iPhone,
  iCloud Drive, chiavetta). FMLAB la legge da lì senza copiare nulla, anche nelle sottocartelle, e divide i giochi
  per console (con il numero per console). I giochi in iCloud non ancora scaricati si scaricano con un tocco. Le
  cartelle si tolgono dall'elenco con uno scorrimento, senza toccare i file.
- La cartella **FMLAB Linux › Giochi** (con BIOS, Salvataggi e un LEGGIMI) la crea l'app da sola all'avvio: si vede
  subito nell'app File.
- **Solo giochi**: interruttore nel Game Emulator. FMLAB Linux si apre direttamente sui giochi; il tasto *Linux*
  riporta Home, Distribuzioni, Sessioni e Impostazioni.
- **Ogni dispositivo**: i comandi a schermo sono in proporzione allo schermo (iPhone SE/mini fino a iPad, anche in
  Split View); menu e avanti veloce non coprono più L/R in orizzontale.
- **Tastiera fisica** (iPad, tastiere Bluetooth): frecce, X = A, Z = B, S = X, A = Y, Q/W = L/R, Invio = Start,
  Spazio = Select.

## 0.9.2
- Game Emulator: **Importa giochi** funziona. Prima il file scelto finiva all'importatore dei file di Linux (due
  importatori SwiftUI nella stessa schermata) e non succedeva nulla; ora usa direttamente il selettore di iOS,
  copia anche file grandi (es. DS da 60+ MB) senza bloccare l'app e accetta più file insieme.

## 0.9.1
- Game Emulator: console e giochi in ordine di uscita (NES, Game Boy, SNES, PlayStation, GBA, DS).
- Tolta la vecchia parte Debian di FMLAB Retro (chiave e archivio apt): i giochi si fanno solo col Game Emulator nativo.
  Il progetto fmlab-retro ora compila solo gli emulatori.

## 0.9.0
- **Game Emulator (FMLAB)**: emulatori **nativi dentro l'app**, senza Linux e senza JIT, nella sezione *Game Emulator ·
  FMLAB* sotto le distribuzioni. Console: NES, Game Boy / Color, Game Boy Advance, Super Nintendo, PlayStation,
  Nintendo DS (core libretro FCEUmm, Gambatte, mGBA, bsnes, PCSX ReARMed, DeSmuME, compilati per iPhone dal progetto
  [fmlab-retro](https://github.com/cipherdesk007-max/fmlab-retro) a commit fissi; l'app controlla l'impronta SHA-256).
  - giochi tuoi in File › FMLAB Linux › Giochi o con *Importa* (nessun gioco incluso), elenco per console
  - comandi a schermo multi-tocco: in verticale sotto il gioco, in orizzontale ai lati; si adattano quando giri il
    telefono e lasciano libera la Dynamic Island; croce a 8 direzioni, vibrazione leggera
  - controller MFi/Xbox/PlayStation (i comandi a schermo spariscono da soli), tocco sullo schermo del DS
  - salvataggio automatico della memoria del gioco, salva/carica stato, avanti veloce, pausa e ripresa automatica
  - italiano e inglese
- Tolta *FMLAB Retro* da Configura Linux (era una Debian per i giochi: lenta, perché passava dall'interprete).
- Distribuzioni: mentre rimisura lo spazio si vede l'ultima misura invece di "Calcolo…".

## 0.8.8
- **Nuova distribuzione FMLAB Retro** (console classiche): Distribuzioni → Configura Linux… → *FMLAB Retro*. È
  Debian 13 ufficiale, installato e verificato come Debian; dopo account e desktop c'è *Installa FMLAB Retro*, che
  aggiunge l'archivio apt FMLAB **firmato** (chiave nell'app, stessa impronta del repository fmlab-retro) e installa
  RetroArch con le impostazioni FMLAB, gli emulatori e `rk-giochi`. Da lì si aggiorna con `apt upgrade`, Debian e FMLAB
  insieme. Nessun gioco incluso. In Distribuzioni e nella Home ha l'icona del controller; nella sua pagina c'è il
  pulsante per installarla se hai saltato il passo.

## 0.8.7
- **Cambio distribuzione con un tocco dalla Home**: in *Distribuzioni installate* tocchi quella che vuoi, confermi, e
  l'app ti dice di chiuderla dal multitasking e riaprirla. Accanto a ognuna si vede se è *In funzione*, *Al prossimo
  avvio* o *Tocca per usarla*. Toccando quella in funzione si annulla un cambio già scelto. Prima bisognava andare in
  Distribuzioni → distribuzione → Usa al prossimo avvio.
- Gli avvisi dell'app hanno il titolo FMLAB Linux (prima LinuxRunner).

## 0.8.6
- **Terminale nitido**: a volte (anche in LinuxRunner originale) il terminale si apriva col testo sfocato. Su iOS
  recenti la schermata si apre con un'animazione che la ingrandisce da piccola, e il testo restava disegnato alla
  risoluzione di quel momento. Ora, finita l'apertura, il testo si ridisegna alla risoluzione vera dello schermo
  (senza cambiare righe e colonne della shell).

## 0.8.5
- **Niente desktop sotto la fotocamera**: in orizzontale a schermo intero il lato della Dynamic Island resta una banda
  nera (le icone non finiscono più lì sotto), l'altro lato va fino al bordo. L'app capisce da sola da che parte è la
  fotocamera quando giri il telefono a destra o a sinistra.
- La misura "Telefono" tiene conto della banda: sul 15 Pro Max **1308×644** (sempre 2× esatto), così il desktop
  riempie tutto lo spazio rimasto senza bande sopra e sotto. Vale al prossimo avvio del desktop.

## 0.8.4
- **Anche le finestre si adattano quando giri il telefono**: dopo la rotazione ogni finestra resta dentro lo schermo
  nuovo. Se non ci sta si rimpicciolisce, e si sposta in proporzione. Quelle a tutto schermo (massimizzate) le
  rifà il gestore delle finestre. Provato con openbox vero (workflow `prove-linux`): una finestra larga 1200 diventa
  642 in verticale e resta tutta visibile.

## 0.8.3
- **Schermo intero davvero, senza bande nere ai lati**: la schermata che contiene il desktop (SwiftUI) rimetteva la
  zona sicura dell'iPhone (59 punti a destra e a sinistra), quindi il desktop 1398×644 restava rimpicciolito con
  bande nere ai lati, sopra e sotto. Ora la zona sicura la decide solo il desktop: in orizzontale a schermo intero
  riempie tutto l'iPhone, e TouchPad riceve i margini veri di Dynamic Island e angoli.

## 0.8.2
- **Corretto (grave)**: nella 0.8.0–0.8.1 il desktop non partiva ("Il desktop non è partito",
  `FMLAB_ROTAZIONE: misura non valida`). Lo script della rotazione, caricato all'avvio della sessione, leggeva i
  parametri della sessione come se fossero la misura dello schermo e la chiudeva. Ora sa quando è caricato dalla
  sessione e non fa niente da solo. Nuova prova automatica proprio su questo caso (workflow `prove-linux`).

## 0.8.1
- **File condivisi: elimina da qui**. Tocca un file → menu **sul file** con *Salva in File…* ed *Elimina*; scorri a
  sinistra su un file o una cartella per eliminarlo (le cartelle con quello che contengono). Chiede sempre conferma.
  Eliminazione sicura dentro la cartella condivisa: i collegamenti non vengono mai seguiti.
- Il menu del file si apre sulla riga toccata, non più in cima allo schermo.

## 0.8.0
- **Il desktop si gira col telefono**: con la risoluzione **Telefono** lo schermo di Linux passa da solo da
  orizzontale (1398×644) a verticale (644×1398) quando giri l'iPhone, **senza riavviare il desktop** né chiudere i
  programmi. Lo schermo di Linux parte grande quanto il lato lungo e RandR lo gira (`fmlab-ruota.py`, una sola
  connessione: con `xrandr` Xvfb perdeva la misura nuova); x11vnc avvisa il visore dell'app. Se apri il desktop col
  telefono in verticale parte già in verticale. Serve RunnerKit (Python + Xlib); senza, resta come prima.
  Provato su Linux a ogni modifica (workflow `prove-linux`: orizzontale → verticale → orizzontale, il visore riceve
  ogni volta la misura giusta).
- **File rimasti di LinuxRunner**: in Home → Da LinuxRunner ogni distribuzione rimasta (anche dopo aver tolto
  LinuxRunner) si può **prendere** (Sposta/Copia) o **eliminare** per liberare lo spazio (es. Alpine 730 MB).
- Schermate dell'app vera nel simulatore iPhone, in italiano, a ogni versione (workflow `screenshot`,
  `docs/screenshots/ultima-versione`) e foto dal telefono nel README.

## 0.7.2
- **RunnerKit si adatta a FMLAB Linux**: a schermo intero l'app scrive nella cartella della sessione
  (`fmlab-schermo`) quanta parte del desktop cade sotto Dynamic Island, angoli e indicatore Home, in pixel di
  Linux. TouchPad (RunnerKit 2026.11.04-1) tiene lì fuori la colonna di pallini e le sue finestre.
- Linux sa di girare in FMLAB Linux: `/proc/ish/version` dice anche `FMLAB-Linux/<versione> base=LinuxRunner/<versione>`
  (RunnerKit lo usa per nomi, percorsi e controlli).

## 0.7.1
- **Corretto**: in italiano l'app si chiudeva toccando **Desktop** per vedere i comandi (e con ogni altro avviso).
  Il traduttore dei titoli usava lo stesso nome per le schermate e per gli avvisi, e il titolo richiamava sé stesso
  all'infinito. Ora ogni tipo ha il suo nome e il titolo degli avvisi passa da un solo punto.

## 0.7.0
- **Desktop nitido, scelto da solo**: la risoluzione **Telefono** ora legge lo schermo e sceglie la misura più
  nitida: divide i pixel veri dello schermo per un numero intero, così ogni pixel di Linux diventa un quadrato
  preciso di pixel dell'iPhone. Su **iPhone 15 Pro Max** (2796×1290): **1398×644, esattamente 2×** (prima 1168×540
  ingrandito 2,39 volte, un po' squadrato). Costa circa il 40% di calcolo in più del 540.
- **Non scalda il telefono**: se all'avvio del desktop il telefono è caldo (stato termico Serio/Critico) o in
  Risparmio energetico, usa da solo la misura leggera da 540 righe. La scelta finisce nei registri (`FMLAB_DISPLAY`).
- Vale al prossimo avvio del desktop (Impostazioni del desktop → Riavvia desktop).

## 0.6.0
- **Tutto in italiano, davvero**: prima restavano in inglese lo schermo del desktop (menu "Start / Reconnect Desktop",
  "Use iPhone as Trackpad", stato "Desktop ready · … display updates/s"), le righe di Impostazioni del desktop
  (Sessione, Temperatura del telefono, Utente Linux, Server grafico, Memoria dell'app, Immagine ricevuta, Schermo
  esterno…), gli avvisi di avvio e installazione, gli stati del JIT e della GPU, gli errori di account e file.
  Ora la parte Objective-C (che prima non passava dalla traduzione) viene tradotta nel momento in cui va a schermo
  (`app/FMLAB/FMLABLingua.inc.m`), senza riscrivere i file dell'originale, così gli aggiornamenti di LinuxRunner
  si portano dentro facilmente. **971 testi**, controllati a ogni compilazione anche nei casi che prima sfuggivano
  (scelte "a ? b : c", testi con numeri, righe valore, messaggi messi in variabili, menu e avvisi Objective-C).
- **Schermo intero vero**: a schermo intero il desktop ora va da bordo a bordo (anche sotto la Dynamic Island e
  l'indicatore Home), senza i margini neri della zona sicura e senza i 12 punti di bordo. Il pulsante per far
  tornare i comandi resta nella zona sicura. Con la tastiera iOS aperta il desktop si sposta sopra.
- Foto del prima in [docs/images/0.6.0](docs/images/0.6.0).

## 0.5.0
- **Uguale all'originale anche nella grafica**: GPU Metal (virglrenderer, libepoxy e ANGLE alle stesse versioni di
  LinuxRunner) oltre al JIT. In Impostazioni → Grafica si può scegliere "GPU Metal · Sperimentale" come in LinuxRunner.
- **Desktop a tutto schermo sul telefono**: nuova risoluzione **Telefono · tutto schermo**, alta 540 come 960×540 ma
  larga quanto le proporzioni dello schermo (iPhone 15 Pro Max: 1168×540), quindi niente bande nere ai lati.
  Diventa quella di base; chi aveva 960×540 passa a questa una volta (si può sempre rimettere 960×540).
- **Pulisci file inutili** (Impostazioni → Pulizia): file temporanei di installazione, cartella temporanea e cache
  dell'app, con lo spazio liberato. Con RunnerKit c'è anche **Pulisci anche dentro Linux** (`pulizia --sicura`).
- Tradotte anche le scritte di stato (In funzione, Fermo, Calcolo…, Grafica…).

## 0.4.1
- L'avviso "LinuxRunner originale è passato alla …" compare anche nella **Home**, non solo in Impostazioni.

## 0.4.0
- **Inglese o italiano**: Impostazioni → FMLAB → Lingua. Di base l'app è in inglese; con "Italiano" (e riaprendo
  l'app) tutta l'interfaccia è tradotta: 475 testi, controllati a ogni compilazione (`strumenti/genera_lingue.py`
  ferma la compilazione se un testo nuovo non ha la traduzione). Dove l'app parla di sé dice "FMLAB Linux".
- **Ogni distribuzione si può eliminare, anche Alpine di base**: Distribuzioni → tocca la distribuzione →
  Spazio → Elimina questa distribuzione. Mostra quanto occupa e libera lo spazio subito. Non si elimina quella in
  uso né quella scelta per il prossimo avvio.
- **RunnerKit anche in Gestione app** (Debian): installato o no, con **Aggiorna RunnerKit** e **Togli RunnerKit**
  (`rk disinstalla`, rimette il sistema com'era). Resta l'installazione automatica la prima volta.

## 0.3.1
- **Anche le impostazioni di LinuxRunner**: quando prendi una distribuzione da LinuxRunner, FMLAB Linux copia anche
  le tue impostazioni (tema, terminale e caratteri, mouse e touchpad, grafica, audio, desktop, schermo esterno), così
  non le rifai da capo. C'è anche il pulsante "Prendi le impostazioni di LinuxRunner" da solo. Non vengono copiate
  le impostazioni di sistema né lo stato della procedura guidata.

## 0.3.0
- **Prendi le distribuzioni da LinuxRunner**: se LinuxRunner è installato nello stesso LiveContainer, la Home di
  FMLAB Linux mostra le sue distribuzioni (es. Debian, con il peso). **Sposta** (istantaneo, nessuno spazio in più;
  LinuxRunner non la avrà più) o **Copia** (resta anche in LinuxRunner). Poi si chiude e riapre FMLAB Linux.
- **RunnerKit già installato**: la prima volta che Debian è pronto, FMLAB Linux apre da sola un terminale che installa
  FMlab - RunnerKit (TouchPad, Centro, Pulizia, RunnerBoost, comando `rk`). Nella Home si vede se è installato,
  con il pulsante per installarlo di nuovo.

## 0.2.1
- Link degli aggiornamenti e del codice sul nome nuovo del repository (fmlab-Linux-io).

## 0.2.0
- **Logo FMLAB** come icona dell'app e in cima alla schermata Home, con il titolo "FMLAB Linux".
- **Colori rosso e nero FMLAB**: colore d'accento rosso del logo (#BF6D6F) al posto dell'azzurro, pulsanti principali
  in rosso scuro, tasti modificatori del desktop in rosso; tema scuro come prima.
- **Aggiornamenti come in FMLAB Cleaner**: l'app controlla la versione su GitHub e, se ce n'è una nuova, mostra
  "Copia link di installazione" da incollare in LiveContainer (+ → Installa dall'URL); si installa sopra e i dati restano.
  In Impostazioni → FMLAB: versione, "Controlla aggiornamenti", codice sorgente e segnalazioni.
- **Avviso quando esce un LinuxRunner originale più nuovo**: l'app lo mostra in Impostazioni → FMLAB, e ogni giorno
  il repository controlla da solo e apre una segnalazione su GitHub (arriva per email) per riportare le novità.
- **Come l'originale**: compilata con il JIT (attivabile come in LinuxRunner) e, appena pronte le dipendenze grafiche,
  con la GPU Metal.

## 0.1.0
- Primo passo: LinuxRunner 1.1.0 (build 900) com'è, compilato da GitHub Actions su Mac (variante interprete,
  grafica software), con nome **FMLAB Linux** e identificativo `dev.fmlab.linux`, così si installa accanto a
  LinuxRunner senza toccarne i dati.
- README in italiano, crediti e licenza GPL-3.0.
