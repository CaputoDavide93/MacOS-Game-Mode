# FAQ

## What is Game Ready?

Game Ready is a free, open-source (MIT) Mac app that checks your Mac, Wi-Fi and internet before cloud gaming, switches the Mac into Game Mode, and tells you whether the Mac's Wi-Fi, the internet or the Mac caused each hiccup while you play.

## Is Game Ready free?

Yes. It is MIT licensed, has no purchases, no ads and no account.

## Which Macs and macOS versions does it run on?

Apple silicon Macs on macOS 15 or later. Intel Macs are not supported: the build targets arm64 only.

## Which cloud gaming services does it support?

Xbox Cloud Gaming, GeForce NOW and Amazon Luna can be opened with the Play button. Better xCloud tuning applies to Xbox Cloud Gaming only. Game Ready does not stream games itself.

## Does it work with Wi-Fi and Ethernet?

Yes. On Wi-Fi it grades signal and link rate; on a cable it grades the port's negotiated speed and duplex. A cable is steadier than Wi-Fi, and the app says so.

## What does Game Mode change?

It turns off the AirDrop/Handoff radio, Handoff, Universal Control, the AirPlay Receiver and Low Power Mode, pauses Time Machine, stops new automatic macOS and App Store update downloads from starting, keeps the Mac awake and quits the apps you chose. Every setting goes back when Game Mode ends. See [how it works](how-it-works.md#game-mode).

## Why does it ask for my administrator password?

Some of those settings need root. One password prompt covers them. The script is compiled into the app and accepts only fixed arguments. The details are in [SECURITY.md](../SECURITY.md).

## What happens if the app crashes during Game Mode?

The saved originals stay on disk. Reopening the app offers **Turn off**, which restores them. See [troubleshooting](troubleshooting.md#game-mode-is-on-after-the-app-crashed-or-the-mac-restarted).

## What does Game Ready send over the internet?

Test traffic only: pings to 1.1.1.1 and the game server, DNS queries, and speed-test downloads and uploads of random bytes. There are no accounts, analytics, crash reports or update checks. Every host is listed in `Endpoints.swift`, and a test fails on any other. See [privacy.md](privacy.md).

## Where is my data stored?

On your Mac, in `~/Library/Application Support/Game Ready/history.jsonl`, for 90 days. **Delete All Data** in History removes it. The Wi-Fi network name is never read.

## Can it fix the lag by itself?

It fixes what is on the Mac: Game Mode and, if allowed, Better xCloud settings. It cannot fix your router, your line or the game's servers, but it tells you which of them is at fault.

## Why does the first launch say the app is blocked?

The release is not notarised yet. Choose **Open Anyway** in System Settings → Privacy & Security.

## Which languages are available?

English, Italian, Spanish, French, German, Portuguese (Brazil), Japanese, Chinese (Simplified), Korean and Hindi. Translations are machine-assisted and have not been reviewed by native speakers.

## How do I report a problem or test on other hardware?

See [Contributing](../README.md#-contributing).
