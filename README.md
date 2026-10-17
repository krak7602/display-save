# Display Save

Native macOS display layout presets. Save and restore named layouts from the menu bar. Requires macOS 14 or later; no accounts, telemetry, network access, or Accessibility permission.

## Install

Download the DMG from [GitHub Releases](https://github.com/krak7602/display-save/releases/latest), open it, and drag **Display Save** into **Applications**. Launch it from Applications; its icon appears in the menu bar, not the Dock. Releases support Apple Silicon and Intel Macs.

**Signing:** releases are ad-hoc signed, not Developer ID signed or notarized. macOS may block a downloaded build. If you trust this source, use **System Settings → Privacy & Security → Open Anyway** after attempting to open it. Do not disable Gatekeeper globally. The DMG does not run a privileged installer.

## Use

1. Arrange your displays in **System Settings → Displays**, including the main display, orientation, resolution/scaling, refresh rate, and mirroring.
2. Click the menu-bar icon, choose **Save…** in the preview’s bottom-right corner, enter a name, and save. The naming row disappears after Save or Cancel.
3. Choose **Switch** beside a saved layout. Click **Keep** within 20 seconds, or **Revert** to restore the previous arrangement. Closing the popover does not stop the countdown; quitting normally also reverts unconfirmed changes.
4. Click a layout’s trash button, or use its context menu, then confirm **Delete** inside that row. **Cancel** or Escape keeps it. No floating dialog opens.

The display count and Save share the preview’s bottom edge. Display names are available on hover. A checkmark means a layout matches the live configuration, not just that it was selected last. Names are unique, ignoring case. Restore warnings expand under **Adjustments**.

## Missing and changed displays

- Disconnected displays are skipped; connected matches are still restored, with warnings.
- If the saved main display is missing, a matched display becomes primary and the saved positions are translated together.
- If a mirror source is missing, a connected follower becomes independent; remaining members can mirror it.
- Extra connected displays stay enabled. Independent extras are placed to the right of the saved arrangement.
- Matching uses persistent macOS UUIDs with compatible hardware checks, then an unambiguous hardware fallback. The app does not guess between indistinguishable monitors with missing or duplicate serial numbers. No matches means no attempted layout change.
- An unavailable resolution/scaling/refresh combination retains the current mode and reports a warning. There is no arbitrary nearest-resolution fallback. macOS can adjust positions to prevent gaps or overlaps.

Reconnect a display and select the layout again to restore it. Switching is manual, not automatic on reconnect.

## Data and privacy

Presets are stored only on your Mac:

```text
~/Library/Application Support/Display Save/presets.json
```

The versioned JSON file is written atomically. Corrupt or newer-format data is not overwritten; recover the file and reopen the app before editing layouts. Presets include display names and hardware identifiers: treat backups as personal data. Preset files, credentials, build caches, and local development files are not included in this repository or release images.

## Native implementation and limitations

- SwiftUI popover and AppKit status item, public CoreGraphics display configuration APIs, and public ColorSync UUIDs.
- Captures origin, primary display, rotation, logical/backing pixel dimensions, reported refresh rate, and mirror relationships. It does not manage app-window positions, brightness, HDR, color profiles, True Tone, Night Shift, display power, or disabling displays.
- Apple exposes no public rotation setter. A small Objective-C bridge dynamically loads the private **MonitorPanel** framework, validates its runtime interfaces, and verifies the resulting orientation. It can fail on unsupported hardware or future macOS releases. This private API is not suitable for Mac App Store distribution.
- CoreGraphics changes are session-only until Keep. MonitorPanel’s rotation setter has no session-only option; macOS controls its persistence. Normal failures, timeout, and quit paths attempt explicit rollback. A force-kill, crash, or power loss cannot run rollback.
- Keep submits the current configuration with CoreGraphics’ permanent option. Apple documents that unsupported permanent configurations can nevertheless last only for the session.
- AirPlay, Sidecar, DisplayLink, docks, and identical-monitor port changes need hardware-specific validation. The automated suite deliberately does not modify real displays.

## Build and test

Requires macOS and Xcode 15.3 or later (Swift 5.10+).

```sh
make test
make run
```

`make build` produces an ad-hoc signed `dist/Display Save.app` for the current architecture. `VERSION` supplies both app version fields. The `DisplayCore` Swift package product exposes snapshots, restore planning, persistence, and native display operations; the app has no third-party Swift package dependencies.

Original app/menu artwork and the DMG background are committed. Regenerate them with `make assets`; this uses AppKit and `iconutil`, not exported SF Symbols or external art.

## Build a release

```sh
make release
```

This builds a universal Apple Silicon/Intel app, creates the custom drag-to-Applications `dist/Display-Save-<version>-universal.dmg`, and writes `dist/SHA256SUMS.txt`. Verify a download with `shasum -a 256 -c SHA256SUMS.txt` from the folder containing both files.

DMG packaging additionally requires Python 3.9+ with `venv`/`pip` and Xcode’s command-line utilities. Hash-pinned [dmgbuild](https://github.com/dmgbuild/dmgbuild), `ds_store`, and `mac_alias` are installed only into `.build/dmg-tools`; they are build tools, not bundled app dependencies. The first packaging run needs network access. Set `PYTHON=/path/to/python3` to choose the bootstrap interpreter. Existing versioned DMGs are not overwritten.

### Versioning and publishing

Stable releases use [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`. Update **VERSION** and **CHANGELOG.md**, commit, then create and push the matching annotated `vX.Y.Z` tag. Do not move an existing release tag.

```sh
version="$(cat VERSION)"
git add VERSION CHANGELOG.md
git commit -m "Release $version"
git tag -a "v$version" -m "Display Save $version"
git push origin main "v$version"
```

CI tests and builds pull requests and `main`. The release workflow checks that the tag matches VERSION, tests, builds the universal DMG, verifies its checksum, and publishes it to GitHub Releases. The generated app embeds the project license and upstream notice. Do not commit signing keys, local preset backups, `.env` files, or build output.

## License and acknowledgements

Display Save is licensed under the [MIT License](LICENSE), copyright © 2026 Display Save contributors.

Some of Display Save’s display-management approach was inspired by [**displayplacer**](https://github.com/jakehilborn/displayplacer). Thanks to Jake Hilborn and all the contributors for sharing their work! The upstream MIT notice is included in [NOTICE](NOTICE).

The app and menu bar share original overlapping-monitor artwork. The app icon uses a matte-black background and muted silver, without gradients or gloss. `scripts/generate-assets.swift` is their source.
