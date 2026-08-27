# Controller Manager Creator Themes

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Validate creator themes](https://github.com/Naerian/controller-manager-creator-themes/actions/workflows/validate.yml/badge.svg)](https://github.com/Naerian/controller-manager-creator-themes/actions/workflows/validate.yml)
[![Publish catalog](https://github.com/Naerian/controller-manager-creator-themes/actions/workflows/publish.yml/badge.svg)](https://github.com/Naerian/controller-manager-creator-themes/actions/workflows/publish.yml)

Official community design catalog for [Controller Manager for Playnite](https://github.com/Naerian/playnite-nx-session-controller-manager).

This repository lets Playnite theme authors and visual designers publish complete appearances for Controller Manager notifications and its disconnect overlay. Designs are reviewed, versioned and distributed independently from the plugin, so users can install new or updated designs without waiting for another Controller Manager release.

Creator themes are data-only packages. They can contain appearance definitions, images, fonts and notification sounds, but never executable code.

## Documentation

The complete authoring reference is maintained in this repository's Wiki:

- [English creator guide](https://github.com/Naerian/controller-manager-creator-themes/wiki/Creator-Theme-Authoring)
- [Guía para creadores en español](https://github.com/Naerian/controller-manager-creator-themes/wiki/ES-Disenos-de-Creadores)
- [Wiki home and language selector](https://github.com/Naerian/controller-manager-creator-themes/wiki)
- [Creator design gallery](previews/README.md)

The Wiki documents every notification and overlay property, theme-ID filtering, state colors, gradients and glow, typography, background images, custom sounds, assets, compatibility, testing and troubleshooting.

## What a creator design can control

- Independent Desktop and Fullscreen notification designs.
- Disconnect-overlay composition, scale, placement and alignment.
- Declarative block ordering for overlay content and independent icon, badge and text placement for notifications.
- Full-screen overlay scenes with a base color, linear gradient, optional image, three positioned radial glows and a configurable grid.
- A split alert-card layout with selectable controller side, divider, incident badge and status placement.
- Colors for connected, disconnected, warning and low-battery states.
- Solid or gradient surfaces and borders, including state-specific borders and glow.
- Independent border sides, thickness and corner radius.
- Controller icon placement, size, containers and spacing.
- Connection and battery badges.
- Font family, weight and size for individual content blocks.
- Background images with stretch, focal alignment, opacity and tint.
- Per-event connected, disconnected, warning and low-battery sounds.
- Exact matching against compatible Playnite Desktop and Fullscreen theme IDs.

When a creator design is selected, Controller Manager locks and dims the corresponding appearance and audio controls. This preserves the composition and sound identity authored by the designer.

Creator designs never execute CSS, XAML or scripts. CSS-like compositions must be expressed with the validated JSON scene and layout properties; this keeps downloaded packs data-only while still supporting layered gradients, glows, images and reordered content.

## For Controller Manager users

Creator designs are installed from Controller Manager itself:

1. Open **Settings → Controller Manager → Appearance**.
2. Expand **Design** under notifications or the disconnect overlay.
3. Select **Update designs**.
4. Wait for the cancellable progress window to finish.
5. Select the downloaded design from the **Creator designs** group.

Controller Manager keeps the last installed copy when the computer is offline. It downloads only releases compatible with the installed plugin version and never replaces a compatible release with an incompatible one.

You can also install a downloaded pull-request artifact or another trusted `.csmtheme` directly: use **Install creator design** beside **Import visual profile** in either Appearance toolbar. Controller Manager shows the author and version before installing, rejects incompatible schema/plugin versions, validates the complete data-only package, and atomically replaces an older design with the same ID.

## For creators

Do not fork the Controller Manager plugin repository to submit a design. Fork this repository instead.

1. Copy [`template/creator-theme`](template/creator-theme) to `themes/<your-stable-id>`.
2. Complete `manifest.json` with a unique ID, author, semantic version and plugin compatibility.
3. Add `notification.json`, `overlay.json`, or both.
4. Add optional images, fonts and sounds inside the design folder.
5. Credit and license every redistributed asset.
6. Run `./tools/validate-themes.ps1` and `./tools/test-validator.ps1` from PowerShell.
7. Test every supported surface and state in Playnite Desktop and Fullscreen.
8. Open a pull request with screenshots and the tested Playnite theme IDs.

Read the [complete Wiki](https://github.com/Naerian/controller-manager-creator-themes/wiki) before preparing a contribution. Pull requests that add executable files, unsafe paths, unlicensed assets or duplicate IDs are rejected.

## Testing a pull request in Playnite

Every pull request that changes a design produces a 14-day `creator-themes-pr-<number>` Actions artifact containing one test `.csmtheme` per changed design. Open the PR's **Checks → Validate creator themes → Artifacts** section, download it, and install the contained package from Controller Manager's **Install creator design** button.

Maintainers can also perform a complete temporary installation directly from a trusted clone of `main`:

```powershell
.\tools\test-pr-theme.ps1 -PullRequest 12
```

Close Playnite first. The script downloads the PR into a temporary directory, validates its data using the trusted validator from `main`, detects every changed design, backs up any installed version and installs the candidate without mixing old files. After testing, close Playnite and restore everything with:

```powershell
.\tools\test-pr-theme.ps1 -Restore
```

Use `-DesignId author.design` to test or restore one design and `-PluginDataDirectory <path>` when Playnite's data folder cannot be detected automatically. Never run scripts supplied inside an untrusted contributor branch.

## Minimal design structure

```text
themes/
└── author.design-name/
    ├── manifest.json
    ├── notification.json       optional
    ├── overlay.json            optional
    ├── Images/                 optional
    ├── Fonts/                  optional
    ├── Audio/                  optional
    ├── LICENSE.txt             recommended
    └── CREDITS.md              recommended
```

At least one appearance file is required. All assets must remain inside the design folder.

## Versioning and compatibility

Each design release declares:

- `SchemaVersion`: creator-package format understood by Controller Manager.
- `Version`: semantic version of the design itself.
- `MinimumPluginVersion`: oldest tested Controller Manager release.
- `MaximumPluginVersion`: optional ceiling for a known incompatibility.

The catalog retains previous releases. This allows an older plugin to receive the newest design version it can safely understand while newer users receive the latest release.

Stable design IDs must never change after publication. Increment the design version whenever appearance files or packaged assets change.

## Security and integrity

Every merged design is packaged as `.csmtheme` and published with its exact size and SHA-256 checksum. Before installation, Controller Manager verifies:

- catalog and design schema versions;
- plugin compatibility range;
- HTTPS transport and TLS 1.2;
- package size and SHA-256;
- archive entry count and decompressed size limits;
- allowed data-file extensions;
- absence of symbolic links and directory traversal;
- agreement between the catalog and root `manifest.json`.

Installation uses a staging directory and atomic replacement. A failed or cancelled update leaves the previously installed design intact.

## Repository structure

- [`themes/`](themes): reviewed design sources.
- [`previews/`](previews): reviewed Desktop, Fullscreen and overlay screenshots for each design.
- [`template/creator-theme/`](template/creator-theme): starter pack.
- [`schemas/`](schemas): JSON schemas for manifests and the remote catalog.
- [`tools/`](tools): validation and catalog-building scripts.
- [`catalog` branch](https://github.com/Naerian/controller-manager-creator-themes/tree/catalog/dist): generated machine-readable catalog and downloadable packages.
- `dist/packages/`: generated downloadable `.csmtheme` releases.
- [Wiki](https://github.com/Naerian/controller-manager-creator-themes/wiki): complete English and Spanish authoring documentation.

Files under `dist/` are generated in the dedicated `catalog` branch and must not be edited manually. Keeping generated artifacts outside `main` allows the source branch to remain protected without granting the publication workflow permission to bypass reviews.

## Publication workflow

Every pull request runs the required `validate` check. It rejects unknown manifest or appearance properties, wrong JSON types, values outside documented ranges, invalid colors and enumerations, unsafe or missing assets, invalid font/sound declarations, missing previews, duplicate IDs and missing license/credit evidence for binary assets. Its own negative regression fixtures also run in CI so a broken validator cannot silently accept common invalid cases.

The protected `main` branch only accepts pull requests whose validation is green. After an approved design is merged, the publication workflow validates the source again, creates the `.csmtheme`, calculates its size and SHA-256, preserves compatible historical releases, and publishes only the generated `dist/` tree to the separate `catalog` branch.

Automation cannot decide whether a design is attractive, readable in every real theme, genuinely original, or whether a submitted license claim is truthful. Maintainers must still review screenshots, attribution, provenance and visual quality before merging.

Controller Manager reads that catalog when a user chooses **Update designs**.

## Relationship with Controller Manager

This repository contains only community appearance data and its publishing tools. Plugin code, releases, issues concerning rendering or settings, and user support remain in [playnite-nx-session-controller-manager](https://github.com/Naerian/playnite-nx-session-controller-manager).

- Report a malformed or incorrectly credited design here.
- Report a Controller Manager rendering or update bug in the plugin repository.
- Imported `.pcvisual` profiles are personal user snapshots and should not be submitted as creator themes.

## License and asset rights

Repository tooling and documentation are available under the [MIT License](LICENSE).

That license does not automatically grant rights over assets contributed inside individual designs. Every design must document the license and attribution for its artwork, fonts and audio. Theme adaptations must credit the original Playnite theme author and must not imply endorsement without permission.

## Author

Created and maintained by [Naerian](https://github.com/Naerian).
