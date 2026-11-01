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
node() { # print center "x y" of a node: $1 text, $2 mode first|last|prefix
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml ui.xml >/dev/null 2>&1
  python3 - "$1" "${2:-first}" <<'PY'
import re,sys,html
s=open("ui.xml",encoding="utf-8").read(); want,mode=sys.argv[1],sys.argv[2]; hits=[]
for m in re.finditer(r'<node [^>]*>',s):
    t=re.search(r' text="([^"]*)"',m.group(0)); b=re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"',m.group(0))
    if not (t and b): continue
    tx=html.unescape(t.group(1))
    if tx==want or (mode=="prefix" and re.match(want,tx)):
        x1,y1,x2,y2=map(int,b.groups()); hits.append(((x1+x2)//2,(y1+y2)//2))
if hits:
    x,y=hits[-1] if mode=="last" else hits[0]; print(x,y)
PY
}
tap_text() { p=$(node "$1" "$2"); if [ -n "$p" ]; then adb shell input tap $p; sleep 2; else echo "not found: $1"; fi; }
SZ=$(adb shell wm size | grep -o '[0-9]*x[0-9]*' | tail -1); W=${SZ%x*}; H=${SZ#*x}
D=$(adb shell wm density | grep -o '[0-9]*' | tail -1)
up()   { adb shell input swipe $((W/2)) $((H*7/10)) $((W/2)) $((H*3/10)) 250; sleep 1.2; }
down() { adb shell input swipe $((W/2)) $((H*3/10)) $((W/2)) $((H*7/10)) 250; sleep 1.2; }
CRASHES=0
front() { # make sure the app is in the foreground
  adb shell dumpsys activity activities | grep -q "mResumedActivity.*$PKG" || { echo "app not in front, reopening"; adb shell am start -n $PKG/.MainActivity >/dev/null; sleep 4; }
}

adb install -r app.apk || exit 1
adb emu geo fix 19.9373 50.0617   # Main Square, Kraków (lng lat)
adb logcat -c
adb shell am start -n $PKG/.MainActivity; sleep 10
# --- first run: welcome screens, as a brand-new user would see them
shot welcome-1; crash_check "launch"
tap_text "Get started"; shot welcome-2-dates; crash_check "welcome dates"
tap_text "Next"; shot welcome-3-location; crash_check "welcome location"
tap_text "Allow location"; sleep 2; shot permission-prompt
tap_text "While using the app"; sleep 3; shot welcome-3-location-on; crash_check "after permission"
tap_text "Next"; shot welcome-4-offline
tap_text "Skip, load photos as I go"; sleep 6; shot nearby-first; crash_check "finish welcome"
# undo a mis-tap on Visited
tap_text "Visited" first; shot toast; crash_check "tick visited"
tap_text "UNDO"; sleep 1; shot after-undo; crash_check "undo"
if [ -n "$(node "Main Square (Rynek Główny)")" ]; then echo "UNDO_OK"; else echo "::error::UNDO_FAILED"; CRASHES=$((CRASHES+1)); fi
# open a place panel, close it with Back
tap_text "Main Square (Rynek Główny)"; sleep 4; shot place-panel; crash_check "open place"
if [ -n "$(node "Your notes")" ]; then echo "PANEL_OK"; adb shell input keyevent 4; sleep 2; else echo "::error::PANEL_NOT_OPEN"; fi
front

for i in 1 2 3 4 5; do up; done; shot nearby-scrolled; crash_check "Nearby scroll"
for i in 1 2 3 4 5 6; do down; done

front; tap_text "Day plans" last; shot plans; crash_check "open Day plans"
tap_text "[0-9]+ tips for this day" prefix; shot plans-tips-open; crash_check "open tips"
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

tap_text "Done" first; sleep 1; shot done-ticked; crash_check "Done button"
tap_text "Visited" last; shot visited; crash_check "Visited tab"
tap_text "Nearby" last; sleep 2
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do up; done; shot nearby-bottom; crash_check "Nearby bottom"
echo "TOTAL_CRASHES=$CRASHES"
adb logcat -d | grep -E "FATAL|AndroidRuntime" | head -40
[ "$CRASHES" = "0" ]
