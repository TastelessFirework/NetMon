# NetMon

[中文](README.md) | **English**

<img src="Resources/AppIcon.png" alt="NetMon icon: a spiderweb and a blue one-eyed creature" width="112">

NetMon is a local macOS menu bar traffic monitor. The menu bar shows live upload and download speeds alongside today's total traffic for the current network. Open the menu to explore usage history by network. Wi-Fi usage is grouped by network name (SSID); Ethernet, PPP/PPPoE, VPN and other primary network interfaces are also supported.

Requires **macOS 14+ on Apple Silicon / arm64**. The interface supports **Chinese and English**. The current public version is **v0.1.1, a pre-release**, distributed with an ad-hoc signature and without Apple notarization.

## Download and install

Download the current version directly:

| File | Purpose |
| --- | --- |
| [NetMon-0.1.1-arm64.dmg](https://github.com/TastelessFirework/NetMon/releases/download/v0.1.1/NetMon-0.1.1-arm64.dmg) | Open the image and drag NetMon into Applications |
| [NetMon-0.1.1-arm64.zip](https://github.com/TastelessFirework/NetMon/releases/download/v0.1.1/NetMon-0.1.1-arm64.zip) | Extract and move the complete app bundle into Applications |
| [SHA256SUMS](https://github.com/TastelessFirework/NetMon/releases/download/v0.1.1/SHA256SUMS) | SHA-256 checksums for the DMG and ZIP |

See the [v0.1.1 release](https://github.com/TastelessFirework/NetMon/releases/tag/v0.1.1) for version details.

The DMG displays NetMon and Applications side by side. Install the app in `/Applications` or `~/Applications`. The license is included inside the app bundle.

If macOS blocks the first launch, try opening the app, then follow the system prompt in **System Settings → Privacy & Security → Open Anyway** and confirm **Open**. Managed Macs may prevent this. See [Apple's instructions for opening an unnotarized app](https://support.apple.com/en-us/102445).

On first launch, NetMon requests location permission to read the Wi-Fi SSID. It does not read or store geographic coordinates. If permission is denied, tracking pauses for Wi-Fi networks whose names cannot be identified. **Launch at Login is off by default** and can be enabled in Settings.

## Interface and features

### Menu bar

![NetMon menu bar showing live upload and download speeds and today's traffic](docs/images/menu-bar.png)

The two lines on the left show upload and download speeds. On the right, the top line shows a custom network name, or `usage` if none is set; the bottom line shows today's total traffic for the current network.

### Usage details

<img src="docs/images/main-menu.png" alt="Example of traffic details in the NetMon main menu" width="360">

The screenshots show speeds and usage at the time they were captured.

- **Current Network**: View the network name, type and interface. Its submenu opens macOS network settings or changes the system network service order. Changing the order requires administrator authorization.
- **Upload / Download Speed**: Speeds update while the menu is open.
- **Today / This Month**: View total, uploaded and downloaded traffic for the current network.
- **All Networks**: Explore usage for each network and the combined total across Today, Last 7 Days, This Month and All Time.
- **Settings**: Choose the interface language and manage tracking, custom names, login startup, SSID permission and history.
- **Debug**: Inspect interface counters and sampling state, with optional file logging.

### Interface language

Choose **中文** or **English** at the top of the **Settings** submenu. Each language occupies its own row, with a checkmark beside the selected language. Chinese is the default, and your choice is saved. Reopen the menu after switching; restarting is unnecessary.

Menus, usage details, app dialogs, app error messages, accessibility text and history dates use the selected language. SSIDs, custom network names and system network service names remain in their original form. macOS permission, authentication and System Settings windows follow the system language.

### Custom network names

Wi-Fi, Ethernet and PPP/PPPoE networks can have custom names of up to six characters. Leave the field blank to restore the default name. Custom names appear in NetMon's menus and menu bar; they do not change the Wi-Fi SSID or the system network service name.

## How traffic is counted and limitations

NetMon reads the primary interface's 64-bit byte counters once per second, tracks upload and download separately, and usually writes accumulated usage to a local SQLite database every ten seconds.

- Only traffic through the primary interface while the app is running is counted. Traffic while the app is closed and simultaneous traffic through every interface are not included.
- Wi-Fi records are grouped by SSID. Identical SSIDs are merged even across different locations or access points; BSSIDs are not used to distinguish them. Ethernet, PPP and similar networks are mainly grouped by type and interface identity.
- A difference is counted only when the network identity and interface match at both ends of the sample interval, counters have not decreased, and the interval is at most 15 seconds. Network changes, disconnections, sleep, tracking setting changes and counter resets rebuild the sampling baseline. Transition intervals may be undercounted; public APIs cannot read the SSID and counters atomically.
- For VPN connections, NetMon prefers the inferred underlying Wi-Fi or Ethernet interface, including tunnel overhead. Multiple interfaces, split tunneling or different IPv4/IPv6 paths may cause the underlying interface to be selected incorrectly.
- Usage is grouped by local date. An interval crossing midnight belongs to its ending date. An unexpected exit may lose about ten seconds of usage that has not yet been saved.
- Interface traffic includes protocol overhead. These figures are neither per-app statistics nor a carrier billing statement.
- Changing network service order affects the entire Mac. If applying or verifying a committed change fails, the configuration may already have changed; an error does not guarantee rollback.
- The app exits if its database cannot be initialized. Recovery from a full disk, database corruption and extreme integer limits still needs improvement.

## Permissions and privacy

All data stays on your Mac. NetMon does not upload data and has no accounts, advertising, telemetry, speed tests or automatic update service.

| Activity | Permissions and data |
| --- | --- |
| Read Wi-Fi SSID | CoreWLAN and Core Location authorization; requests permission only, without starting location updates or reading or storing coordinates |
| Read traffic | Darwin `NET_RT_IFLIST2` 64-bit interface counters; no packet capture |
| Change network service order | Security Authorization and SystemConfiguration; a fresh authorization is created for each actual change and destroyed afterward; administrator passwords are not cached |
| Launch at Login | `SMAppService.mainApp`; off by default and registered only when enabled by the user |
| Debug | Menus display real network information; system log messages are marked private, while optional file logs are plain text |

Local data locations:

```text
~/Library/Application Support/SSIDTrafficMonitor/usage.sqlite3
~/Library/Logs/SSIDTrafficMonitor/debug.log
```

The database contains SSIDs, custom names, interfaces, usage timestamps and byte totals, and is not encrypted. Debug file logging is off by default. When enabled, it records SSIDs, interfaces, timestamps and sample differences, without log rotation. Disabling logging does not delete existing files. Do not commit databases, logs or unredacted Debug screenshots to GitHub.

## Update and uninstall

Quit NetMon from its menu before updating, replace the complete app bundle, and reopen it. Updating preserves local usage history, app preferences and the system login-item choice.

To uninstall, disable Launch at Login, quit the app, and move the app bundle to Trash. To remove history and logs, delete the two directories containing the data files listed above in Finder. **Clear History** in Settings also removes custom network names and cannot be undone.

## Build from source

Requires Apple Command Line Tools or full Xcode, with **Swift 6 or later**. Tests use Swift Testing; the Swift Package manifest declares tools-version 5.10. There are no third-party SwiftPM dependencies.

Run in the project directory:

```bash
make test      # Run automated tests
make app       # Release build with an ad-hoc signed dist/NetMon.app
make package   # Generate DMG, ZIP and SHA256SUMS without installing or publishing
```

Other targets include `make build` (Debug), `make release` (Release executable), `make icon` (regenerate ICNS) and `make install` (build and copy to the current user's Applications directory; override with `INSTALL_DIR`). After installation, launch manually with:

```bash
open ~/Applications/NetMon.app
```

The app must be installed in `/Applications` or `~/Applications` to register a login item. The icon source is `Resources/AppIcon.png`, and app packaging uses `Resources/AppIcon.icns`; run `make icon` after changing the source image.

Scripts use the SDK selected by `xcrun`. If the default is the Command Line Tools macOS 27.0 SDK and a 26.5 SDK is available, the compatible SDK is selected. Override explicitly with:

```bash
SSID_TRAFFIC_SDK=/path/to/MacOSX.sdk make app
```

Builds use module caches inside the project and SwiftPM's `--disable-sandbox` option. The app has no App Sandbox entitlement. Compilation targets the host's native architecture and does not automatically produce a Universal binary. Release packaging requires arm64; Intel installers are not provided.

## Tests and project structure

The 31 automated tests cover attribution boundaries, SQLite persistence and aggregation, custom names, network service order, usage totals, language preferences and formatting, and Darwin counter reads. On-device checks for networks, menu interaction, permissions, login startup and language switching are described in [TESTING.md](TESTING.md), in Chinese. Full on-device acceptance testing and compatibility testing on the minimum supported macOS 14 remain pending; automated tests do not replace them.

| Path | Responsibility |
| --- | --- |
| `Sources/CNetworkStats` | C wrapper for Darwin 64-bit interface counters |
| `Sources/NetMonCore` | Traffic attribution, SQLite, totals, service ordering and language support |
| `Sources/NetMon` | AppKit menus, network resolution, authorization, login items and sampling |
| `Resources` | App icon, version metadata, bilingual permission descriptions and DMG layout |
| `Scripts/build.sh` | Tests, compilation and app packaging |
| `Scripts/package.sh` | arm64 checks, DMG/ZIP packaging and SHA-256 checksum files |

## License

[MIT](LICENSE), with `Copyright (c) 2026 Eric`. A copy of the license is included in the app bundle.
