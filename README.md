# SambaFix

A patch that lets you play **Samba de Amigo** (the iPhone game removed from the App Store) through **LiveContainer**, without TrollStore or a jailbreak.

> This tweak (`.dylib`) fixes the launch crash and black screen when running Samba de Amigo inside LiveContainer by replacing CloudKit with a fake implementation. You must provide your own IPA.

## What does it fix?

When the game is re-signed for LiveContainer, it loses its iCloud entitlements. The game calls CloudKit during startup, which either causes an immediate crash or leaves it stuck on a black screen waiting for an iCloud response that never arrives.

## How does it work?

`SambaFix.dylib` replaces the CloudKit container with a fake one that:

- Reports that the iCloud account is available.
- Completes cloud operations successfully, returning empty results.

This lets the game continue without errors or warning messages. **Game Center is not modified**: your nickname, achievements, and online leaderboards continue to work normally.

## What it does NOT do

- It does not include the game. You need your own decrypted IPA from a copy you obtained legally.
- iCloud cloud saves are disabled: progress is saved only on your device.

## How to use it

1. Download `SambaFix.dylib` from **Releases** (v3.0.0 Final) or from **Actions** (the `SambaFix` artifact), or build it yourself (see below).
2. Install the game's IPA in **LiveContainer**.
3. In LiveContainer, import `SambaFix.dylib` in the **Tweaks** section and enable it for Samba de Amigo (the exact menu names may vary depending on your LiveContainer version).
4. Launch the game.

## Building

The repository includes a GitHub Actions workflow (`.github/workflows/build.yaml`). Fork the repository, open **Actions → Build SambaFix → Run workflow**, and download the artifact.

Files:

- `SambaFix.m`: the main CloudKit patch.
- `SambaFixNet.m`: optional network request logging for debugging. Its on-screen overlay is disabled (`SF_OVERLAY 0`).

## Tested on

- iOS 27.0 (24A437)
- LiveContainer 3.8.10

If it works (or doesn't work) on another version, open an issue and include your iOS and LiveContainer versions.

## Troubleshooting

- **Crash on launch**: open an issue and attach the crash log (**Settings → Privacy & Security → Analytics & Improvements → Analytics Data**).
- **Unexpected cloud behavior**: in `SambaFix.m`, change `SF_ACCOUNT_STATUS` to `CKAccountStatusNoAccount` and rebuild.
