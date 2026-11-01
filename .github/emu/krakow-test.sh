#!/bin/bash
# Drives the Kraków app on an emulator: Nearby, Day plans (every day/theme, scrolled to the bottom), Visited.
PKG=com.laur.krakowtrip
mkdir -p shots; n=0
shot() { n=$((n+1)); adb exec-out screencap -p > "shots/$(printf %02d $n)-$1.png"; }
alive() { [ -n "$(adb shell pidof $PKG | tr -d '\r')" ]; }
crash_check() {
  if ! alive; then
    echo "::error::APP CRASHED during: $1"
    adb logcat -d | grep -A40 "FATAL EXCEPTION" | head -80
    CRASHES=$((CRASHES+1))
    adb logcat -c
    adb shell am start -n $PKG/.MainActivity >/dev/null; sleep 6
  fi
}
node() { # print center "x y" of the first node whose text matches $1 exactly
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml ui.xml >/dev/null 2>&1
  python3 - "$1" <<'PY'
import re,sys,html
s=open("ui.xml",encoding="utf-8").read()
for m in re.finditer(r'<node [^>]*>',s):
    t=re.search(r' text="([^"]*)"',m.group(0)); b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',m.group(0))
    if t and b and html.unescape(t.group(1))==sys.argv[1]:
        x1,y1,x2,y2=map(int,b.groups()); print((x1+x2)//2,(y1+y2)//2); break
PY
}
tap_text() { p=$(node "$1"); if [ -n "$p" ]; then adb shell input tap $p; sleep 2; else echo "not found: $1"; fi; }
SZ=$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1); W=${SZ%x*}; H=${SZ#*x}
D=$(adb shell wm density | grep -o '[0-9]*' | tail -1)
up()   { adb shell input swipe $((W/2)) $((H*7/10)) $((W/2)) $((H*3/10)) 250; sleep 1.2; }
down() { adb shell input swipe $((W/2)) $((H*3/10)) $((W/2)) $((H*7/10)) 250; sleep 1.2; }
CRASHES=0

adb install -r app.apk || exit 1
adb shell pm grant $PKG android.permission.ACCESS_FINE_LOCATION
adb shell pm grant $PKG android.permission.ACCESS_COARSE_LOCATION
adb emu geo fix 19.9373 50.0617   # Main Square, Kraków (lng lat)
adb logcat -c
adb shell am start -n $PKG/.MainActivity; sleep 10
shot start; crash_check "launch"

for i in 1 2 3 4 5; do up; done; shot nearby-scrolled; crash_check "Nearby scroll"
for i in 1 2 3 4 5 6; do down; done

tap_text "Day plans"; shot plans; crash_check "open Day plans"
for i in 1 2 3 4 5 6 7; do up; crash_check "Day plans scroll $i"; done; shot plans-bottom
for i in 1 2 3 4 5 6 7 8; do down; done

# 7 days -> every theme gets a day
tap_text "4  ▾"; tap_text "7"; sleep 1; shot plans-7days; crash_check "set 7 days"
TOP=$(node "TODAY" | awk '{print $2}')
for d in 0 1 2 3 4 5 6; do
  px=$((D*16/160)); gap=$((D*6/160)); cw=$(((W-2*px-6*gap)/7))
  x=$((px + d*(cw+gap) + cw/2))
  [ -n "$TOP" ] && adb shell input tap $x $TOP; sleep 2
  crash_check "tap day $d"
  for i in 1 2 3 4 5 6 7; do up; crash_check "day $d scroll $i"; done
  shot "day$d-bottom"
  for i in 1 2 3 4 5 6 7 8; do down; done
done

tap_text "Visited"; shot visited; crash_check "Visited tab"
tap_text "Nearby"; sleep 2
echo "TOTAL_CRASHES=$CRASHES"
adb logcat -d | grep -E "FATAL|AndroidRuntime" | head -40
[ "$CRASHES" = "0" ]
