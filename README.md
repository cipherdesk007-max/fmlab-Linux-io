# FMLAB Linux 🐧📱

Linux vero sull'iPhone (Debian GNU/Linux, Arch Linux ARM, Alpine), versione FMLAB di
**[LinuxRunner](https://github.com/mxhm11cr/LinuxRunner)**. Niente jailbreak, niente macchina virtuale:
i programmi Linux ARM64 girano dentro l'app grazie a un interprete e a uno strato che traduce le chiamate di sistema.

> **Stato: 0.6.0.** È LinuxRunner 1.1.0 (build 900) con nome, logo e colori FMLAB (rosso e nero), identificativo
> proprio (`dev.fmlab.linux`, si installa **accanto** a LinuxRunner senza toccarne i dati), aggiornamenti dall'app
> come FMLAB Cleaner e avviso quando esce un LinuxRunner originale più nuovo. Le altre migliorie arrivano una alla
> volta, ognuna misurata contro l'originale.

## Installazione

LiveContainer → **+** → **Installa dall'URL** e incolla:
`https://github.com/cipherdesk007-max/fmlab-Linux-io/releases/download/ultima/FMLAB-Linux.ipa`

## Cosa cambierà rispetto a LinuxRunner

| Miglioria | Perché |
|---|---|
| **Distribuzioni cancellabili** ✅ | In LinuxRunner Alpine è dentro l'app e non si può togliere. Qui ogni distribuzione (Debian, Arch, Alpine) si scarica solo se la vuoi, mostra quanto pesa e si elimina con un tocco, anche quella di base |
| **RunnerKit già dentro** ✅ | Si installa da solo la prima volta che Debian è pronto, e da Gestione app si aggiorna o si toglie: TouchPad, pannello Sistema e consigli di prestazioni di [FMlab - RunnerKit](https://github.com/cipherdesk007-max/FMlab---RunnerKit) senza installare niente a parte |
| **Italiano e grafica FMLAB** ✅ (inglese di base, italiano da Impostazioni; dalla 0.6.0 anche desktop, menu e avvisi) | Stessi colori e stile di [FMLAB Cleaner](https://github.com/cipherdesk007-max/FMLAB-cleaner) |
| **Aggiornamenti dall'app** ✅ | Come FMLAB Cleaner: l'app avvisa e si reinstalla sopra senza perdere i dati |
| **Al passo con l'originale** ✅ | Quando esce un LinuxRunner più nuovo, l'app lo dice e il repository apre da solo una segnalazione ([workflow "originale"](.github/workflows/originale.yml)) |
| **Prendi il Debian da LinuxRunner** ✅ | Se LinuxRunner è nello stesso LiveContainer, la Home mostra le sue distribuzioni: **Sposta** (istantaneo) o **Copia**, insieme alle tue impostazioni |
| **Desktop a tutto schermo** ✅ | Risoluzione "Telefono": 540 di altezza con le proporzioni dell'iPhone; a schermo intero va da bordo a bordo, senza bande nere |
| **Pulizia** ✅ | File temporanei e cache dell'app, e con RunnerKit anche dentro Linux |
| **Backup del Debian** | Esporta/importa l'ambiente con un tocco |

**Come si verifica che è davvero meglio**: gli stessi comandi cronometrati sulle due app, sullo stesso telefono
(avvio, `apt install`, uno script Python, apertura del desktop, RAM usata), più lo spazio occupato visto dalla
scheda App di FMLAB Cleaner. I numeri finiscono in questo README.

## Come è fatta

- Sorgente di partenza: LinuxRunner al commit
  [`d141978`](https://github.com/mxhm11cr/LinuxRunner/commit/d141978) ("Release LinuxRunner 1.1.0 (900)").
  Il README originale è in [README.LinuxRunner.md](README.LinuxRunner.md), le istruzioni di compilazione in
  [docs/BUILDING.md](docs/BUILDING.md).
- Compilata **gratis da GitHub Actions su Mac** ([.github/workflows/build.yml](.github/workflows/build.yml)) con
  `scripts/build-ipa.sh --unsigned`, con il JIT e la GPU Metal come l'originale. La GPU Metal richiede dipendenze grafiche pesanti
  (virglrenderer, libepoxy, ANGLE): le compila una volta il [workflow "gpu"](.github/workflows/gpu.yml), restano in
  cache e da lì entrano in ogni versione.
- Le correzioni di LinuxRunner originale si riportano qui a ogni loro versione.
- Storico delle versioni FMLAB: [CHANGELOG-FMLAB.md](CHANGELOG-FMLAB.md).

## Licenza e riconoscimenti

**GPL-3.0**, come l'originale: il codice resta aperto e ogni modifica è pubblica. Vedi [LICENSE.md](LICENSE.md),
[LICENSE.IOS](LICENSE.IOS) e [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

- **LinuxRunner** — Leminos ([mxhm11cr](https://github.com/mxhm11cr)): il lavoro vero è il loro.
- **iSH** — Theodore Dubois e collaboratori ([ish-app/ish](https://github.com/ish-app/ish)).
- **ios-linuxkit** — Rui Carmo e collaboratori ([rcarmo/ios-linuxkit](https://github.com/rcarmo/ios-linuxkit)).

Problemi e idee per FMLAB Linux: [segnalazioni](https://github.com/cipherdesk007-max/fmlab-Linux-io/issues/new).
Un problema che c'è anche in LinuxRunner originale va segnalato anche [a loro](https://github.com/mxhm11cr/LinuxRunner/issues).
