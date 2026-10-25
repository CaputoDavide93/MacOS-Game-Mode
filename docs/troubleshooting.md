# Troubleshooting

Find your symptom. If it is not here, open an issue with the details listed in [Contributing](../README.md#-contributing).

## macOS says the app can't be opened

The release build is ad-hoc signed and not notarised. Open **System Settings → Privacy & Security**, scroll to the message about Game Ready, and choose **Open Anyway**.

## The verdict says "Couldn't finish"

At least one check could not measure. Game Ready never turns a missing measurement into a pass. Open **Advanced → Overview** and read the result that says it could not measure. Likely causes are no internet during the check, a blocked ping or UDP port on the network, or a speed test that got no valid data. Run **Check now** again; the speed test runs at most once every 2 minutes.

## The speed test shows nothing, or "couldn't measure"

Speed servers that rate-limit answer with a tiny reply that would read as an instant perfect test. Game Ready discards it and tries the next provider. If every provider fails, the speed row says it could not measure. Try again after a few minutes.

## "Line free" says there is nothing to compare with

The first check has no history to compare against. It compares idle latency with the best of the last 14 days, so it can answer from the second check on.

## Game Mode asks for my password

It is meant to, once, when you turn it on. macOS draws that prompt, so it cannot show the script. See [SECURITY.md](../SECURITY.md) for exactly what the script may do.

## Game Mode is on after the app crashed or the Mac restarted

Reopen Game Ready. It offers **Turn off**, which restores the saved settings. After a restart mid-session it asks for the password once more, to put back the settings that needed it.

## Better xCloud shows as not detected

Check, in order: Better xCloud is installed and you have opened xbox.com once in that browser; the browser allows scripts from Apple Events (Chrome and Edge: View → Developer → Allow JavaScript from Apple Events; Safari: Settings → Developer → Allow JavaScript from Apple Events); you approved the macOS prompt that lets Game Ready control the browser; the browser you play in is the one chosen in Settings. Then press **Refresh** on the Better xCloud card in Checklist.

## AirDrop is still on after I chose "off"

macOS only switches AirDrop off through a configuration profile that you approve. Open **System Settings → General → Device Management** and approve **Game Ready: AirDrop off**. If Game Ready cannot open the profile, it is in `Application Support/Game Ready`: double-click it there.

## The menu bar dot never changes

The live watch runs only while Game Mode is on. Turn Game Mode on (⌘G).

## Text is clipped in my language

Please report it with the language and a screenshot. Layout in every language has not been verified: see [testing.md](testing.md).
