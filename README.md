# FMLAB Linux 🐧📱

Linux vero sull'iPhone (Debian GNU/Linux, Arch Linux ARM, Alpine), versione FMLAB di
**[LinuxRunner](https://github.com/mxhm11cr/LinuxRunner)**. Niente jailbreak, niente macchina virtuale:
i programmi Linux ARM64 girano dentro l'app grazie a un interprete e a uno strato che traduce le chiamate di sistema.

> **Stato: 0.1.0 — primo passo.** È LinuxRunner 1.1.0 (build 900) com'è, con nome e identificativo propri
> (`dev.fmlab.linux`): si installa **accanto** a LinuxRunner senza toccarne i dati. Le migliorie arrivano dopo,
> una alla volta, ognuna misurata contro l'originale.

## Installazione

LiveContainer → **+** → **Installa dall'URL** e incolla:
`https://github.com/cipherdesk007-max/new-app/releases/download/ultima/FMLAB-Linux.ipa`

## Cosa cambierà rispetto a LinuxRunner

| Miglioria | Perché |
|---|---|
| **Distribuzioni a scelta e cancellabili** | In LinuxRunner Alpine è dentro l'app e non si può togliere. Qui ogni distribuzione (Debian, Arch, Alpine) si scarica solo se la vuoi, mostra quanto pesa e si elimina con un tocco, anche quella di base |
| **RunnerKit già dentro** | TouchPad, pannello Sistema e consigli di prestazioni di [FMlab - RunnerKit](https://github.com/cipherdesk007-max/FMlab---RunnerKit) senza installare niente a parte |
| **Italiano e grafica FMLAB** | Stessi colori e stile di [FMLAB Cleaner](https://github.com/cipherdesk007-max/FMLAB-cleaner) |
| **Aggiornamenti dall'app** | Come FMLAB Cleaner: l'app avvisa e si reinstalla sopra senza perdere i dati |
| **Backup e trasferimento del Debian** | Esporta/importa l'ambiente, anche per portarci quello che hai già in LinuxRunner |

**Come si verifica che è davvero meglio**: gli stessi comandi cronometrati sulle due app, sullo stesso telefono
(avvio, `apt install`, uno script Python, apertura del desktop, RAM usata), più lo spazio occupato visto dalla
scheda App di FMLAB Cleaner. I numeri finiscono in questo README.

## Come è fatta

- Sorgente di partenza: LinuxRunner al commit
  [`d141978`](https://github.com/mxhm11cr/LinuxRunner/commit/d141978) ("Release LinuxRunner 1.1.0 (900)").
  Il README originale è in [README.LinuxRunner.md](README.LinuxRunner.md), le istruzioni di compilazione in
  [docs/BUILDING.md](docs/BUILDING.md).
- Compilata **gratis da GitHub Actions su Mac** ([.github/workflows/build.yml](.github/workflows/build.yml)) con
  `scripts/build-ipa.sh --unsigned`: variante interprete + grafica software (senza JIT e senza GPU Metal, che
  richiedono dipendenze grafiche molto pesanti e arriveranno dopo).
- Le correzioni di LinuxRunner originale si riportano qui a ogni loro versione.
- Storico delle versioni FMLAB: [CHANGELOG-FMLAB.md](CHANGELOG-FMLAB.md).

## Licenza e riconoscimenti

**GPL-3.0**, come l'originale: il codice resta aperto e ogni modifica è pubblica. Vedi [LICENSE.md](LICENSE.md),
[LICENSE.IOS](LICENSE.IOS) e [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

- **LinuxRunner** — Leminos ([mxhm11cr](https://github.com/mxhm11cr)): il lavoro vero è il loro.
- **iSH** — Theodore Dubois e collaboratori ([ish-app/ish](https://github.com/ish-app/ish)).
- **ios-linuxkit** — Rui Carmo e collaboratori ([rcarmo/ios-linuxkit](https://github.com/rcarmo/ios-linuxkit)).

Problemi e idee per FMLAB Linux: [segnalazioni](https://github.com/cipherdesk007-max/new-app/issues/new).
Un problema che c'è anche in LinuxRunner originale va segnalato anche [a loro](https://github.com/mxhm11cr/LinuxRunner/issues).
