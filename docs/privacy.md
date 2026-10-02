# Privacy

Each promise, how the code keeps it, and its limits.

| Promise | How it's enforced | Limit |
|---|---|---|
| Only test traffic leaves the Mac | Every host is in `Endpoints.allHosts`; `EndpointGuardTests` fails on any other host, URL or IPv4 literal in the sources | The test reads string literals; a host built at run time from pieces would slip past it, so don't do that |
| No accounts, analytics, crash reports or update checks | No such code or dependency; the only package is `GameReadyCore`, which has no dependencies | — |
| History holds no personal data | `CheckRecord` stores grades, finding codes and formatted numbers. The Wi-Fi network name is never read: CoreWLAN only returns it with Location access, which the app never asks for | Results include link facts such as the Wi-Fi channel and signal |
| History stays on the Mac and is deletable | `~/Library/Application Support/Game Ready/history.jsonl`, pruned after 90 days; **Delete All Data** removes the file | Time Machine backs up Application Support like any other folder |
| Speed tests reveal nothing about you | Plain HTTPS downloads/uploads of random bytes; no cookies (`URLSessionConfiguration.ephemeral`, no cookie storage) | The servers see your public IP address, as any website does |
| Root access only with consent, only for three settings | See [SECURITY.md](../SECURITY.md) | The password prompt is macOS's own and can't show the script's text |
