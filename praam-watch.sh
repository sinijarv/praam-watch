#!/usr/bin/env bash
#
# praam-watch.sh — jälgib praamid.ee vaba mahutavust ja teatab häälega,
# kui soovitud väljumisele tekib vaba sõidukikoht (keegi tühistas broneeringu).
#
# Töötab Linuxil ja macOS-il. Vajab ainult: bash, curl, awk.
#
# Näide:
#   ./praam-watch.sh --date 14.08 --time 16:00 --direction RH
#
# Vaata kõiki väljumisi:
#   ./praam-watch.sh --date 14.08 --direction RH --list
#
# Kontrolli, kas heli/hääl töötab:
#   ./praam-watch.sh --test-alert
#

set -u

API="https://www.praamid.ee/online/events"
BOOK_URL="https://www.praamid.ee/portal/ticket/departure"
TIME_SHIFT=300

DIRECTION="RH"
DATE_IN=""
TIME_IN=""
WATCH="sv"
MIN=1
INTERVAL=60
REPEATS=6
KEEP_GOING=0
OPEN_BROWSER=0
ONCE=0
LIST=0
DEBUG=0
TEST_ALERT=0
SILENT="${PRAAM_SILENT:-0}"

# ---------------------------------------------------------------- abitekstid

usage() {
  cat <<'EOF'
Kasutamine: praam-watch.sh [valikud]

  -d, --date <kuupäev>     14.08 | 14.08.2026 | 2026-08-14   (kohustuslik)
  -t, --time <kellaaeg>    16:00 | 1600 | 16.00              (kohustuslik, v.a --list)
  -r, --direction <kood>   RH (Rohuküla-Heltermaa, vaikimisi)
                           HR (Heltermaa-Rohuküla)
                           KV (Kuivastu-Virtsu)
                           VK (Virtsu-Kuivastu)
  -w, --watch <koodid>     mida jälgida, komadega eraldatud (vaikimisi: sv)
                             sv  = sõiduautod / väiksed sõidukid
                             bv  = suured sõidukid (veok, buss, haagis)
                             mc  = mootorrattad
                             bc  = jalgrattad
                             pcs = reisijad
  -m, --min <arv>          mitu kohta peab vabanema, et teavitada (vaikimisi 1)
  -i, --interval <sek>     kontrolli sagedus sekundites (vaikimisi 60,
                           lubatud alates 5; nt 30 või 10)
      --repeats <arv>      mitu korda häiret korrata (vaikimisi 6)
      --keep-going         ära lõpeta pärast häiret, jälgi edasi
      --open               ava leiu korral broneerimisleht brauseris
      --once               kontrolli üks kord ja välju
      --list               näita kõiki selle päeva väljumisi ja välju
      --test-alert         mängi häiret (heli + hääl) ja välju
      --debug              näita API toorvastust
  -h, --help               see abi

Väljumine: Ctrl+C
EOF
}

die() { printf 'Viga: %s\n' "$1" >&2; exit 1; }

dir_name() {
  case "$1" in
    RH) echo "Rohuküla - Heltermaa" ;;
    HR) echo "Heltermaa - Rohuküla" ;;
    KV) echo "Kuivastu - Virtsu" ;;
    VK) echo "Virtsu - Kuivastu" ;;
    *)  echo "$1" ;;
  esac
}

cap_name() {
  case "$1" in
    sv)  echo "sõiduauto koht" ;;
    bv)  echo "suure sõiduki koht" ;;
    mc)  echo "mootorratta koht" ;;
    bc)  echo "jalgratta koht" ;;
    pcs) echo "reisijakoht" ;;
    *)   echo "$1" ;;
  esac
}

# ------------------------------------------------------------- argumendid

while [ $# -gt 0 ]; do
  case "$1" in
    -d|--date)      DATE_IN="${2:-}"; shift 2 ;;
    -t|--time)      TIME_IN="${2:-}"; shift 2 ;;
    -r|--direction) DIRECTION="$(printf '%s' "${2:-}" | tr '[:lower:]' '[:upper:]')"; shift 2 ;;
    -w|--watch)     WATCH="${2:-}"; shift 2 ;;
    -m|--min)       MIN="${2:-}"; shift 2 ;;
    -i|--interval)  INTERVAL="${2:-}"; shift 2 ;;
    --repeats)      REPEATS="${2:-}"; shift 2 ;;
    --keep-going)   KEEP_GOING=1; shift ;;
    --open)         OPEN_BROWSER=1; shift ;;
    --once)         ONCE=1; shift ;;
    --list)         LIST=1; shift ;;
    --test-alert)   TEST_ALERT=1; shift ;;
    --debug)        DEBUG=1; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "tundmatu valik: $1 (vaata --help)" ;;
  esac
done

# ------------------------------------------------------------- teavitamine

have() { command -v "$1" >/dev/null 2>&1; }

play_sound() {
  [ "$SILENT" = "1" ] && return 0

  # macOS
  if have afplay; then
    for f in /System/Library/Sounds/Sosumi.aiff /System/Library/Sounds/Ping.aiff; do
      [ -f "$f" ] && afplay "$f" >/dev/null 2>&1 && return 0
    done
  fi

  # Linux: kõige töökindlam ogg-failide jaoks
  have canberra-gtk-play && canberra-gtk-play -i complete >/dev/null 2>&1 && return 0

  for f in /usr/share/sounds/freedesktop/stereo/complete.oga \
           /usr/share/sounds/freedesktop/stereo/bell.oga \
           /usr/share/sounds/alsa/Front_Center.wav \
           /usr/share/sounds/sound-icons/prompt.wav; do
    [ -f "$f" ] || continue
    have paplay  && paplay  "$f" >/dev/null 2>&1 && return 0
    have pw-play && pw-play "$f" >/dev/null 2>&1 && return 0
    have ffplay  && ffplay -nodisp -autoexit -loglevel quiet "$f" >/dev/null 2>&1 && return 0
    case "$f" in *.wav) have aplay && aplay -q "$f" >/dev/null 2>&1 && return 0 ;; esac
  done

  # viimane variant: terminali kell
  i=0; while [ "$i" -lt 5 ]; do printf '\a'; i=$((i+1)); sleep 0.2 2>/dev/null || true; done
  return 0
}

speak() {
  [ "$SILENT" = "1" ] && return 0
  msg="$1"
  have say       && { say "$msg" >/dev/null 2>&1 && return 0; }
  have espeak-ng && { espeak-ng -v et "$msg" >/dev/null 2>&1 || espeak-ng "$msg" >/dev/null 2>&1; return 0; }
  have espeak    && { espeak -v et "$msg" >/dev/null 2>&1 || espeak "$msg" >/dev/null 2>&1; return 0; }
  have spd-say   && { spd-say -l et -w "$msg" >/dev/null 2>&1 || spd-say -w "$msg" >/dev/null 2>&1; return 0; }
  have festival  && { printf '%s\n' "$msg" | festival --tts >/dev/null 2>&1; return 0; }
  return 1
}

desktop_notify() {
  title="$1"; body="$2"
  [ "$SILENT" = "1" ] && return 0
  if have osascript; then
    osascript -e "display notification \"$body\" with title \"$title\" sound name \"Sosumi\"" >/dev/null 2>&1
  elif have notify-send; then
    notify-send -u critical "$title" "$body" >/dev/null 2>&1
  fi
}

open_url() {
  have open     && { open "$1"     >/dev/null 2>&1; return 0; }
  have xdg-open && { xdg-open "$1" >/dev/null 2>&1; return 0; }
}

alert() {
  headline="$1"; spoken="$2"
  desktop_notify "Praamid.ee" "$headline"
  [ "$OPEN_BROWSER" = "1" ] && open_url "$BOOK_URL"
  n=0
  while [ "$n" -lt "$REPEATS" ]; do
    play_sound
    speak "$spoken" || true
    n=$((n+1))
    [ "$n" -lt "$REPEATS" ] && sleep 2
  done
}

if [ "$TEST_ALERT" = "1" ]; then
  echo "Testin häiret (heli + hääl). Kui midagi ei kuule, vaata allpool olevat nimekirja."
  REPEATS=2
  alert "Test" "Test. Vaba sõidukikoht praamil."
  echo
  echo "Leitud abivahendid:"
  for c in say espeak-ng espeak spd-say festival afplay paplay pw-play aplay ffplay \
           canberra-gtk-play osascript notify-send; do
    if have "$c"; then printf '  ✓ %s\n' "$c"; else printf '  – %s\n' "$c"; fi
  done
  exit 0
fi

# --------------------------------------------------- kuupäeva/kella normaliseerimine

norm_date() {
  d="$1"
  case "$d" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) echo "$d"; return 0 ;;
  esac
  IFS='.' read -r p1 p2 p3 <<EOF
$d
EOF
  [ -n "${p1:-}" ] && [ -n "${p2:-}" ] || return 1
  [ -z "${p3:-}" ] && p3="$(date +%Y)"
  case "$p1$p2$p3" in *[!0-9]*) return 1 ;; esac
  printf '%04d-%02d-%02d\n' "$((10#$p3))" "$((10#$p2))" "$((10#$p1))"
}

norm_time() {
  t="$(printf '%s' "$1" | tr '.' ':')"
  case "$t" in
    *:*) hh="${t%%:*}"; mm="${t##*:}" ;;
    ????) hh="${t%??}"; mm="${t#??}" ;;
    ???)  hh="${t%??}"; mm="${t#?}" ;;
    *)    return 1 ;;
  esac
  case "$hh$mm" in *[!0-9]*) return 1 ;; esac
  printf '%02d:%02d\n' "$((10#$hh))" "$((10#$mm))"
}

case "$DIRECTION" in RH|HR|KV|VK) ;; *) die "suund peab olema RH, HR, KV või VK (sain '$DIRECTION')" ;; esac
[ -n "$DATE_IN" ] || { usage; echo; die "--date on kohustuslik"; }
DATE="$(norm_date "$DATE_IN")" || die "kuupäeva ei õnnestunud lugeda: '$DATE_IN'"

TIME=""
if [ "$LIST" != "1" ]; then
  [ -n "$TIME_IN" ] || die "--time on kohustuslik (või kasuta --list)"
  TIME="$(norm_time "$TIME_IN")" || die "kellaaega ei õnnestunud lugeda: '$TIME_IN'"
fi

case "$MIN$INTERVAL$REPEATS" in *[!0-9]*) die "--min, --interval ja --repeats peavad olema numbrid" ;; esac
[ "$INTERVAL" -ge 5 ] || die "--interval alla 5 sekundi ei ole viisakas serveri vastu"

WATCH_LIST="$(printf '%s' "$WATCH" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"
for w in $WATCH_LIST; do
  case "$w" in sv|bv|mc|bc|pcs) ;; *) die "--watch tundmatu kood '$w' (lubatud: sv, bv, mc, bc, pcs)" ;; esac
done

# ------------------------------------------------------------------ API

AWK_PARSE='
function num(s) { sub(/.*:/, "", s); gsub(/[^0-9-]/, "", s); return s+0 }
/"dtstart":/ {
  split($0, a, "\"")
  dt = a[4]
  tm = substr(dt, 12, 5)
  cur = (substr(dt, 1, length(target)) == target)
  next
}
cur && /"status":/  { s=$0; gsub(/.*:"|"/, "", s); status=s; next }
cur && /"pcs":/     { pcs=num($0); next }
cur && /"bc":/      { bc=num($0);  next }
cur && /"sv":/      { sv=num($0);  next }
cur && /"bv":/      { bv=num($0);  next }
cur && /"mc":/      { mc=num($0);  next }
cur && /"dc":/      { found=1; printf "%s|%s|%d|%d|%d|%d|%d\n", tm, status, sv, bv, mc, bc, pcs; cur=0; next }
END { if (!found) print "NOTFOUND" }
'

fetch() {
  curl -sS --max-time 25 \
       -H 'Accept: application/json' \
       -H 'User-Agent: praam-watch/1.0' \
       "$API?direction=$DIRECTION&departure-date=$DATE&time-shift=$TIME_SHIFT" 2>/dev/null
}

parse() { # $1 = json, $2 = target prefix ("" = kõik)
  printf '%s' "$1" | tr '{},' '\n\n\n' | awk -v target="$2" "$AWK_PARSE"
}

ts() { date '+%H:%M:%S'; }

DIRNAME="$(dir_name "$DIRECTION")"

# ------------------------------------------------------------------ --list

if [ "$LIST" = "1" ]; then
  json="$(fetch)"
  [ -n "$json" ] || die "API ei vastanud"
  [ "$DEBUG" = "1" ] && printf '%s\n\n' "$json"
  printf '%s, %s\n\n' "$DIRNAME" "$DATE"
  printf '%-6s %-11s %6s %6s %6s %6s %6s\n' "aeg" "staatus" "autod" "suured" "mootor" "rattad" "reisij"
  parse "$json" "$DATE" | while IFS='|' read -r tm st sv bv mc bc pcs; do
    [ "$tm" = "NOTFOUND" ] && { echo "  (selle kuupäeva kohta väljumisi ei leitud)"; continue; }
    printf '%-6s %-11s %6s %6s %6s %6s %6s\n' "$tm" "$st" "$sv" "$bv" "$mc" "$bc" "$pcs"
  done
  exit 0
fi

# ------------------------------------------------------------------ jälgimine

TARGET="${DATE}T${TIME}"
WATCH_HUMAN=""
for w in $WATCH_LIST; do WATCH_HUMAN="$WATCH_HUMAN$(cap_name "$w"), "; done
WATCH_HUMAN="${WATCH_HUMAN%, }"

SPOKEN="Tähelepanu. Praamil $DIRNAME kell $TIME on vaba koht."

trap 'printf "\nLõpetan. Head reisi!\n"; exit 0' INT TERM

printf 'Jälgin: %s, %s kell %s\n' "$DIRNAME" "$DATE" "$TIME"
printf 'Ootan:  %s (vähemalt %s)\n' "$WATCH_HUMAN" "$MIN"
printf 'Sagedus: iga %s sekundi järel. Katkesta Ctrl+C-ga.\n\n' "$INTERVAL"

prev=""
fails=0

while :; do
  json="$(fetch)"

  if [ -z "$json" ] || [ "${json#*\"items\"}" = "$json" ]; then
    fails=$((fails+1))
    printf '\r[%s] API ei vastanud (%s. korda) — proovin edasi%s' "$(ts)" "$fails" '   '
    [ "$ONCE" = "1" ] && { echo; die "API ei vastanud"; }
    sleep "$INTERVAL"
    continue
  fi
  fails=0
  [ "$DEBUG" = "1" ] && printf '\n%s\n' "$json"

  line="$(parse "$json" "$TARGET" | head -n 1)"

  if [ -z "$line" ] || [ "$line" = "NOTFOUND" ]; then
    printf '\n[%s] Väljumist %s kell %s ei leitud. Selle päeva väljumised:\n' "$(ts)" "$DATE" "$TIME"
    parse "$json" "$DATE" | while IFS='|' read -r tm st sv bv mc bc pcs; do
      [ "$tm" = "NOTFOUND" ] || printf '   %s (autod: %s)\n' "$tm" "$sv"
    done
    exit 1
  fi

  IFS='|' read -r tm st sv bv mc bc pcs <<EOF
$line
EOF

  # kas mõni jälgitav kategooria on vaba?
  hit=""
  for w in $WATCH_LIST; do
    case "$w" in
      sv)  v="$sv" ;;  bv) v="$bv" ;;  mc) v="$mc" ;;
      bc)  v="$bc" ;;  pcs) v="$pcs" ;;  *) v=0 ;;
    esac
    if [ "$v" -ge "$MIN" ]; then hit="$hit$(cap_name "$w"): $v, "; fi
  done

  cur="autod=$sv suured=$bv mootor=$mc rattad=$bc reisijad=$pcs staatus=$st"

  if [ -n "$hit" ]; then
    hit="${hit%, }"
    printf '\n[%s] *** VABA KOHT! %s ***  (%s)\n' "$(ts)" "$hit" "$cur"
    printf '    Broneeri kohe: %s\n' "$BOOK_URL"
    alert "Vaba koht! $DIRNAME $TIME — $hit" "$SPOKEN"
    if [ "$KEEP_GOING" != "1" ]; then
      printf '\nLõpetan. (Kasuta --keep-going, kui tahad edasi jälgida.)\n'
      exit 0
    fi
  elif [ "$cur" != "$prev" ]; then
    printf '\n[%s] %s\n' "$(ts)" "$cur"
  else
    printf '\r[%s] %s%s' "$(ts)" "$cur" '   '
  fi

  prev="$cur"
  [ "$ONCE" = "1" ] && { echo; exit 0; }
  sleep "$INTERVAL"
done
