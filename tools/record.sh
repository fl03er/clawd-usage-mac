#!/bin/zsh
# Makes the README images in docs/ from the app in demo mode (fake data, own settings).
# Needs python3 with Pillow. Run after ./build.sh.
#   tools/record.sh            English images in docs/, Korean ones in docs/ko/
#   tools/record.sh <en|ko> <dir>
set -e
cd "$(dirname "$0")/.."
if [[ -z "$1" ]]; then "$0" en docs && "$0" ko docs/ko; exit; fi
UILANG=$1; OUT=$2
mkdir -p $OUT
BIN=ClawdUsage.app/Contents/MacOS/ClawdUsage
TMP=$(mktemp -d)
USAGE=$PWD/tools/demo-usage.txt
defaults delete local.clawd-usage-mac.demo >/dev/null 2>&1 || true

# demo <name> <seconds> [VAR=value...]: run the app in demo mode until it quits by itself.
demo() {
  local name=$1 secs=$2; shift 2
  env CLAWD_DEMO=1 CLAWD_LANG=$UILANG CLAWD_FAKE_USAGE=$USAGE CLAWD_THEME=classic CLAWD_SKIN=classic CLAWD_DETAILS=0 "$@" $BIN &
  local pid=$!
  ( sleep $(( secs + 10 )); kill $pid 2>/dev/null ) &
  wait $pid 2>/dev/null || true
}
gif() {   # gif <name> <crop height px> <record seconds> [VAR=value...]
  local name=$1 crop=$2 secs=$3; shift 3
  rm -rf $TMP/$name
  demo $name $secs CLAWD_RECORD=$TMP/$name CLAWD_RECORD_AT=1.5 CLAWD_RECORD_SECONDS=$secs "$@"
  python3 tools/make_gif.py gif $TMP/$name $OUT/$name.gif $crop
}
shot() {  # shot <out.png> [VAR=value...]
  local out=$1; shift
  demo shot 3 CLAWD_SNAPSHOT=$out CLAWD_SNAPSHOT_DELAY=3 "$@"
}

# GIFs: header + sky + session bar (300 px = 150 pt at 2x).
gif states 300 11 CLAWD_SKY_MINUTES=1350 CLAWD_MOOD=sleep CLAWD_SCRIPT="3:mood=work;7:mood=idle;9:mood=wait"
gif clicks 300 9 CLAWD_SKY_MINUTES=780 CLAWD_MOOD=idle CLAWD_SCRIPT="2:click=spin;4:click=peekaboo;7:click=coin-hop"
gif soul 300 6.5 CLAWD_SKY_MINUTES=1110 CLAWD_MOOD=idle CLAWD_SCRIPT="0.5:pct=100;2:act=soul"
gif reset 300 5 CLAWD_SKY_MINUTES=780 CLAWD_MOOD=idle CLAWD_SCRIPT="0.5:pct=92;3:reset=3"
gif weather 300 4 CLAWD_SKY_MINUTES=780 CLAWD_MOOD=idle CLAWD_WX=63
# Space theme: header, sky window and the limit rows (the starfield fills the widget).
gif space 470 6 CLAWD_THEME=space CLAWD_MOOD=idle CLAWD_SCRIPT="3:click=wink"
# Launch theme: one whole 30-second cycle on the Moon.
gif launch 300 30 CLAWD_THEME=launch CLAWD_MOOD=idle

# The widget with details.
shot $OUT/details.png CLAWD_SKY_MINUTES=780 CLAWD_DETAILS=1 CLAWD_MOOD=work

# Themes.
args=()
for t in classic midnight mocha oled forest halloween space launch; do
  shot $TMP/theme-$t.png CLAWD_SKY_MINUTES=1350 CLAWD_THEME=$t CLAWD_MOOD=idle CLAWD_SCRIPT="2.2:stop=1"
done
python3 tools/make_gif.py grid $OUT/themes.png 4 Classic=$TMP/theme-classic.png Midnight=$TMP/theme-midnight.png \
  Mocha=$TMP/theme-mocha.png "OLED black=$TMP/theme-oled.png" Forest=$TMP/theme-forest.png Halloween=$TMP/theme-halloween.png Space=$TMP/theme-space.png Launch=$TMP/theme-launch.png

# Skins: Clawd standing still in the sky, cropped to the area he walks in.
for s in classic bow crown ears frost nerd party santa shades tired tophat witch; do
  shot $TMP/skin-$s.png CLAWD_SKY_MINUTES=1350 CLAWD_SKIN=$s CLAWD_MOOD=idle CLAWD_SCRIPT="2.2:stop=1;2.25:x=48"
done
python3 tools/make_gif.py grid $OUT/skins.png 6 Classic=$TMP/skin-classic.png Bow=$TMP/skin-bow.png Crown=$TMP/skin-crown.png \
  "Cat ears=$TMP/skin-ears.png" Frost=$TMP/skin-frost.png Nerd=$TMP/skin-nerd.png Party=$TMP/skin-party.png \
  "Santa hat=$TMP/skin-santa.png" Shades=$TMP/skin-shades.png Tired=$TMP/skin-tired.png "Top hat=$TMP/skin-tophat.png" \
  "Witch hat=$TMP/skin-witch.png" --crop 280,72,250,148

rm -rf $TMP
defaults delete local.clawd-usage-mac.demo >/dev/null 2>&1 || true
ls -la $OUT
