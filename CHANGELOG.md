# Changelog

Versions follow [Semantic Versioning](https://semver.org/).

## 1.0.1 — 2026-10-18

- Clarify the project description.
- Make the displayplacer acknowledgements in the README and bundled notice friendlier.
- Update GitHub Actions to maintained Node.js 24-based actions.

## 1.0.0 — 2026-10-18

- Native menu-bar app for saving, switching, and deleting named display layouts.
- Capture display arrangement, primary display, rotation, resolution/scaling, refresh rate, and mirroring.
- Conservative display matching, partial restoration when displays are missing, and warnings for unavailable modes.
- Keep/Revert confirmation with automatic rollback after 20 seconds.
- Local, versioned preset storage; no accounts, telemetry, or network access in the app.
- Original matching overlapping-monitor icons, with a matte-black app background and muted-silver artwork.
- Universal macOS app and custom drag-to-Applications DMG.

Rotation uses Apple's private MonitorPanel framework. Release builds are ad-hoc signed, not Developer ID signed or notarized.
