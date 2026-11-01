#!/bin/bash
# Drives Waypoint on an emulator like a brand-new user: welcome, location, then every city end to end.
PKG=com.laur.waypoint
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
tap_below() { # tap the middle of the screen, $2 dp below the text $1
  p=$(node "$1"); [ -z "$p" ] && { echo "not found: $1"; return; }
  y=$(( $(echo $p | awk '{print $2}') + $2 * D / 160 )); adb shell input tap $((W/2)) $y; sleep 1
}
front() { # make sure the app is in the foreground
  adb shell dumpsys activity activities | grep -q "mResumedActivity.*$PKG" || { echo "app not in front, reopening"; adb shell am start -n $PKG/.MainActivity >/dev/null; sleep 4; }
}

adb install -r app.apk || exit 1
adb emu geo fix 19.9373 50.0617   # Main Square, Kraków (lng lat)
adb logcat -c
adb shell am start -n $PKG/.MainActivity; sleep 10
shot hub-welcome-1; crash_check "launch"
tap_text "Get started"; shot hub-welcome-2; crash_check "welcome page 2"
tap_text "Allow location"; sleep 2
tap_text "While using the app"; sleep 3; shot hub-welcome-location-on; crash_check "after permission"
tap_text "Show my trips"; sleep 2; shot hub; crash_check "hub"

dl_test() { # Download all from the bottom of Nearby, wait for it, check the result, then look at a few place photos
  name="$1"; front
  for i in $(seq 1 14); do up; done
  tap_text "Download all"; tap_text "Download the remaining [0-9]+" prefix; sleep 3; shot "$name-dl-running"
  r=""; for i in $(seq 1 100); do sleep 5
    if [ -n "$(node "All done.*" prefix)" ]; then r=done; break; fi
    if [ -n "$(node "Download the remaining [0-9]+" prefix)" ]; then r=partial; break; fi
    alive || break
  done
  shot "$name-dl-finished"; crash_check "$name download"
  adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1; adb pull /sdcard/ui.xml ui.xml >/dev/null 2>&1
  grep -o 'text="[^"]*places[^"]*"' ui.xml | head -3
  if [ "$r" = done ]; then echo "DOWNLOAD_OK $name"; elif [ "$r" = partial ]; then echo "::warning::DOWNLOAD_PARTIAL $name"; else echo "::error::DOWNLOAD_TIMEOUT $name"; fi
  for i in $(seq 1 16); do down; done
  tap_text "Sights"; sleep 1
  for k in 1 2 3; do
    tap_text "SIGHT" first; sleep 3; shot "$name-photo-$k"
    adb shell input swipe $((W*8/10)) $((H*25/100)) $((W*2/10)) $((H*25/100)) 200; sleep 1; shot "$name-photo-$k-b"
    adb shell input keyevent 4; sleep 2; up
  done
  for i in $(seq 1 6); do down; done
}
test_city() { # $1 city name, $2 lng, $3 lat  (opens it from My trips)
  name="$1"; adb emu geo fix $2 $3; sleep 1
  front; tap_text "$name"; sleep 2
  city_body "$name"
}
city_body() {
  name="$1"; shot "$name-welcome-dates"; crash_check "$name open"
  tap_text "Next"; shot "$name-welcome-offline"
  tap_text "Skip, load photos as I go"; sleep 6; shot "$name-nearby"; crash_check "$name nearby"
  tap_text "Visited" first; tap_text "UNDO"; sleep 1; crash_check "$name undo"
  tap_text "SIGHT" first; sleep 4; shot "$name-place-panel"; crash_check "$name place"
  if [ -n "$(node "×")" ]; then echo "PANEL_OK $name"; else echo "::error::PANEL_NOT_OPEN $name"; fi
  if [ -n "$(node "×")" ]; then adb shell input keyevent 4; sleep 2; fi
  tap_text "Eat"; sleep 1
  tap_text "RESTAURANT" first; sleep 4; tap_text "Menu"; sleep 1; shot "$name-restaurant"; crash_check "$name restaurant"
  if [ -n "$(node "×")" ]; then echo "RESTAURANT_OK $name"; adb shell input keyevent 4; sleep 2; fi
  if [ -n "$(node "×")" ]; then adb shell input keyevent 4; sleep 2; fi
  if [ -z "$(node "Around you")" ]; then echo "::error::NOT_ON_NEARBY $name"; fi
  tap_text "All"
  for i in 1 2 3 4 5 6; do up; done; crash_check "$name nearby scroll"; shot "$name-nearby-scrolled"
  for i in 1 2 3 4 5 6 7; do down; done
  tap_text "Day plans" last; shot "$name-plans"; crash_check "$name plans"
  tap_text "[0-9]+ tips for this day" prefix
  tap_text "4  ▾"; tap_text "7"; sleep 1; crash_check "$name 7 days"
  TOP=$(node "TODAY" | awk '{print $2}')
  for d in 0 1 2 3 4 5 6; do
    px=$((D*16/160)); gap=$((D*6/160)); cw=$(((W-2*px-6*gap)/7))
    x=$((px + d*(cw+gap) + cw/2))
    [ -n "$TOP" ] && adb shell input tap $x $TOP; sleep 2
    for i in 1 2 3 4 5 6 7; do up; done; crash_check "$name day $d"
    [ $d = 0 ] && shot "$name-day0-bottom"
    for i in 1 2 3 4 5 6 7 8; do down; done
  done
  tap_text "Done" first; sleep 1; crash_check "$name done"
  tap_text "Visited" last; shot "$name-visited"; crash_check "$name visited tab"
  tap_text "Nearby" last; sleep 1
  adb shell input keyevent 4; sleep 2   # Back goes to the city list
  if [ -n "$(node "Your trips")" ]; then echo "BACK_TO_HUB_OK $name"; else echo "::error::BACK_TO_HUB_FAILED $name"; front; fi
}
if [ "$QUICK" != "1" ]; then
test_city "Kraków" 19.9373 50.0617
front; tap_text "Kraków"; sleep 2; dl_test "Kraków"; adb shell input keyevent 4; sleep 2
test_city "Vienna" 16.3731 48.2085
test_city "Milan" 9.1919 45.4641
fi

# --- a brand-new city: Portugal -> Lisbon, built on the phone from the internet
adb emu geo fix -9.1393 38.7223; sleep 1
front; tap_text "+  Plan a new trip"; sleep 2; shot add-countries; crash_check "countries"
tap_below "Which country?" 52; adb shell input text "Portu"; sleep 2; shot add-countries-search
tap_text "Portugal"; sleep 2; shot add-cities; crash_check "cities"
tap_below "Which city?" 52; adb shell input text "Obidos"; adb shell input keyevent 66; sleep 8
shot add-search-results; crash_check "city search"
if [ -n "$(node "Óbidos")" ]; then echo "SEARCH_OK"; else echo "::error::SEARCH_FAILED"; fi
adb shell input keyevent 4; sleep 1   # close keyboard
tap_text "Lisbon"; sleep 3; shot build-progress; crash_check "build start"
ok=""; for i in $(seq 1 40); do sleep 3; if [ -n "$(node "When is your trip?")" ]; then ok=1; break; fi; alive || break; done
shot build-done; crash_check "build"
if [ -n "$ok" ]; then echo "BUILD_GUIDE_OK"; city_body "Lisbon"; dl_test "Lisbon"; else echo "::error::BUILD_GUIDE_FAILED"; adb shell uiautomator dump /sdcard/ui.xml >/dev/null; adb shell cat /sdcard/ui.xml | grep -o 'text="[^"]*"' | head -30; fi
shot hub-diary; crash_check "hub diary"
for i in 1 2 3; do up; done; shot hub-diary-scrolled
echo "TOTAL_CRASHES=$CRASHES"
adb logcat -d | grep -E "FATAL|AndroidRuntime" | head -40
[ "$CRASHES" = "0" ]
