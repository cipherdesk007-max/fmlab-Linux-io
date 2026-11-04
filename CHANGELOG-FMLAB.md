# Changelog — FMLAB Linux

Storico delle versioni FMLAB. Le novità di LinuxRunner originale sono in [CHANGELOG.md](CHANGELOG.md).

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
