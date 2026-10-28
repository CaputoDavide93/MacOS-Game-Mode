# Uninstall

Game Ready has no installer and no background service. Removing it is deleting the app and,
if you want, the few files it keeps. Do these in order. None of the commands below has been
run on a real Mac by the author yet; each is the inverse of something in the code, so check
before you paste.

## 1. Turn Game Mode off first

Open Game Ready and turn Game Mode off. This puts back the AirDrop radio, Low Power Mode,
Time Machine, update downloads, Handoff, Universal Control and the AirPlay Receiver. If the
app offers **Turn off** after a crash or restart, accept it.

If you have already removed the app, see "If something is left changed" at the end.

## 2. Remove the AirDrop-off profile, if you used it

Settings → AirDrop off → **Remove** (asks for your password), or System Settings → General →
Device Management → "Game Ready: AirDrop off" → remove. Or in Terminal:

```bash
sudo profiles remove -identifier io.github.caputodavide93.gameready.airdrop
```

## 3. Quit and delete the app

Quit Game Ready (⌘Q) and move **Game Ready** from Applications to the Bin. With Homebrew, once
a cask exists (see [packaging](../packaging/homebrew/game-ready.rb)): `brew uninstall --cask game-ready`.

## 4. Remove what it kept (optional)

| What | Where | Remove |
|---|---|---|
| History, the flag file and undo plan | `~/Library/Application Support/Game Ready/` | Delete the folder. **Delete All Data** in History removes only the history |
| Settings | `~/Library/Preferences/io.github.caputodavide93.gameready.plist` | Delete the file (log out and in, or `killall cfprefsd`, if it reappears) |
| Saved undo values | `/var/db/game-ready/` (root-owned) | `sudo rm -r /var/db/game-ready` **only after** step 1, since it holds the originals |
| Automation permission | System Settings → Privacy & Security → Automation | `tccutil reset AppleEvents io.github.caputodavide93.gameready` |
| Browser option for Better xCloud | Your browser's "Allow JavaScript from Apple Events" | Game Ready never changes this switch; turn it off yourself if you enabled it only for this app |

## If something is left changed

Only needed if the app was removed or broken while Game Mode was on. Check each, then fix only
what differs from what you want:

```bash
ifconfig awdl0 | head -1                         # <UP,...> means the AirDrop radio is up
pmset -g custom | grep lowpowermode              # 1 means Low Power Mode is on
defaults read /Library/Preferences/com.apple.TimeMachine AutoBackup
defaults read /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload
defaults read /Library/Preferences/com.apple.commerce AutoUpdate
```

To put them back (root ones need `sudo`; the values you had before are in
`/var/db/game-ready/originals` if it still exists):

```bash
sudo ifconfig awdl0 up
sudo pmset -b lowpowermode 1; sudo pmset -c lowpowermode 1     # only if you used it
sudo tmutil enable                                             # only if you used it
sudo defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool true
sudo defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool true
```

Handoff, Universal Control and the AirPlay Receiver are switches in System Settings (General →
AirDrop & Handoff, Displays → Advanced, General → AirDrop & Handoff). Open System Settings and
set them as you like.

To report a leftover, open an issue with the output of the check commands above.
