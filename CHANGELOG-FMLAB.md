# Changelog — FMLAB Linux

Storico delle versioni FMLAB. Le novità di LinuxRunner originale sono in [CHANGELOG.md](CHANGELOG.md).

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
