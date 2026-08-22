# praam-watch

`praam-watch.sh` jälgib [praamid.ee](https://www.praamid.ee) vaba mahutavust ja teatab häälega,
kui soovitud väljumisele tekib vaba sõidukikoht (nt keegi tühistas broneeringu).

Töötab Linuxil ja macOS-il.

## Eeldused

Vajab ainult `bash`, `curl` ja `awk` — kõik on tavaliselt juba olemas.

Heli ja hääle jaoks kasutatakse seda, mis parasjagu süsteemis leidub
(`say`, `espeak-ng`, `spd-say`, `paplay`, `notify-send` jne). Kontrolli oma masinat:

```sh
./praam-watch.sh --test-alert
```

## Kasutamine

```sh
praam-watch.sh [valikud]
```

| Valik | Väärtus | Selgitus |
| --- | --- | --- |
| `-d`, `--date` | `14.08` \| `14.08.2026` \| `2026-08-14` | kuupäev (**kohustuslik**) |
| `-t`, `--time` | `16:00` \| `1600` \| `16.00` | kellaaeg (**kohustuslik**, v.a `--list`) |
| `-r`, `--direction` | `RH` (vaikimisi) | suund, vt tabelit allpool |
| `-w`, `--watch` | `sv` (vaikimisi) | mida jälgida, komadega eraldatud |
| `-m`, `--min` | `1` (vaikimisi) | mitu kohta peab vabanema, et teavitada |
| `-i`, `--interval` | `60` (vaikimisi) | kontrolli sagedus sekundites, lubatud alates `5` |
| `-W`, `--whatsapp` | `+3725xxxxxxx:VÕTI` | saada leiu korral WhatsApp sõnum (CallMeBot); mitu saajat komadega eraldatult või lippu korrates |
| `--repeats` | `6` (vaikimisi) | mitu korda häiret korrata |
| `--keep-going` | | ära lõpeta pärast häiret, jälgi edasi |
| `--open` | | ava leiu korral broneerimisleht brauseris |
| `--once` | | kontrolli üks kord ja välju |
| `--list` | | näita kõiki selle päeva väljumisi ja välju |
| `--test-alert` | | mängi häiret (heli + hääl) ja välju |
| `--debug` | | näita API toorvastust |
| `-h`, `--help` | | see abi |

### Suunad (`--direction`)

| Kood | Suund |
| --- | --- |
| `RH` | Rohuküla–Heltermaa (vaikimisi) |
| `HR` | Heltermaa–Rohuküla |
| `KV` | Kuivastu–Virtsu |
| `VK` | Virtsu–Kuivastu |

### Jälgitavad kategooriad (`--watch`)

| Kood | Tähendus |
| --- | --- |
| `sv` | sõiduautod / väiksed sõidukid |
| `bv` | suured sõidukid (veok, buss, haagis) |
| `mc` | mootorrattad |
| `bc` | jalgrattad |
| `pcs` | reisijad |

## Näited

Jälgi ühte väljumist:

```sh
./praam-watch.sh --date 14.08 --time 16:00 --direction RH
```

Vaata kõiki selle päeva väljumisi:

```sh
./praam-watch.sh --date 14.08 --direction RH --list
```

Kontrolli, kas heli/hääl töötab:

```sh
./praam-watch.sh --test-alert
```

Jälgi tihedamini ja ava leiu korral brauser:

```sh
./praam-watch.sh --date 14.08 --time 16:00 --interval 30 --open
```

Saada leiu korral WhatsApp sõnum kahele saajale:

```sh
./praam-watch.sh --date 14.08 --time 16:00 \
  --whatsapp +3725xxxxxxx:123456,+3725yyyyyyy:654321
```

## WhatsApp teavitused (CallMeBot)

WhatsApp sõnumid saadetakse tasuta [CallMeBot](https://www.callmebot.com/blog/free-api-whatsapp-messages/)
teenuse kaudu. Iga saaja peab end **ühe korra** ise registreerima:

1. Lisa CallMeBoti telefoninumber oma kontaktidesse (kehtiv number on kirjas
   [CallMeBoti juhendis](https://www.callmebot.com/blog/free-api-whatsapp-messages/)).
2. Saada sellele numbrile WhatsApp-is sõnum: `I allow callmebot to send me messages`.
3. Bot vastab isikliku API võtmega (nt `123456`).

Seejärel anna saaja(d) skriptile kujul `number:võti`:

```sh
--whatsapp +3725xxxxxxx:123456              # üks saaja
--whatsapp +3725xxxxxxx:123456,+3725yyyyyyy:654321   # mitu saajat
--whatsapp +3725xxxxxxx:123456 --whatsapp +3725yyyyyyy:654321   # sama, lippu korrates
```

Seadistuse kontrollimiseks saada testsõnum:

```sh
./praam-watch.sh --test-alert --whatsapp +3725xxxxxxx:123456
```

Märkused:

- API võti on saajapõhine — igal numbril on oma võti.
- CallMeBot on kolmanda osapoole tasuta teenus, mis ei garanteeri käideldavust;
  heli/häälteavitus jääb selle kõrval alles.
- `PRAAM_SILENT=1` WhatsApp sõnumeid ei summuta — see mõjutab ainult heli,
  häält ja töölauateavitusi.

## Keskkonnamuutujad

| Muutuja | Selgitus |
| --- | --- |
| `PRAAM_SILENT=1` | ei mängi heli, ei räägi ega saada töölauateavitusi (WhatsApp sõnumid saadetakse siiski) |

## Märkused

- Skript lõpetab pärast esimest leidu; kasuta `--keep-going`, kui tahad edasi jälgida.
- Väljumine: `Ctrl+C`.
- Ära vali liiga lühikest `--interval`'it — alla 5 sekundi ei ole serveri vastu viisakas.

## Litsents

Apache License 2.0 — vt [LICENSE](LICENSE).
