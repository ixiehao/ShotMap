# Releasing

This checklist is for maintainers; end users only need the DMG in GitHub
Releases.

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Packaging/Info.plist`, then update `CHANGELOG.md`.
2. Run the same verification gate used by CI before running
   `./scripts/package_dmg.sh`:

   ```sh
   swift test
   python3 scripts/test_native_packaging.py
   swift build -c release --arch arm64 --scratch-path .build/package-arm64 \
     -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
   swift build -c release --arch x86_64 --scratch-path .build/package-x86_64 \
     -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors
   ```

   This catches strict-concurrency regressions before each native DMG is
   assembled. The release build must complete without project warnings; inspect
   any toolchain-level architecture warning rather than suppressing it.
3. The packaging script derives the filename from `Packaging/Info.plist`,
   verifies the signature and DMG, remounts the final compressed artifact,
   checks its Finder metadata and `/Applications` link, confirms each native
   package contains exactly its requested CPU slice with macOS 13.0 minimum,
   and writes a matching `.sha256` file. The default command creates separate
   Apple Silicon (`arm64`) and Intel (`x86_64`) output directories; see
   [INSTALLER-BUILD.md](INSTALLER-BUILD.md) for options and safe rebuilds. Before
   signing, it strips debug and local symbol tables from the binary copied into
   the app. This removes no executable code,
   Swift runtime metadata, fonts, or supported features. Keep the matching
   `dist/ShotMap-<version>-<architecture>/ShotMap.app.dSYM` with the matching source
   commit and release artifacts for crash investigation. It is generated before
   stripping, survives build
   cache cleanup, and is not included in the DMG. The unstripped binary also
   remains in `.build`. Both font and Tabler Icons license texts
   are included in the app's `Contents/Resources/Licenses` directory.
4. Create a release with concise English, 中文, 日本語, and 한국어 notes, in that
   order. Use the same notes in the new changelog entry. Existing three-language
   documentation keeps English first, followed by Chinese and Japanese.
   Attach both native DMGs and both SHA-256 checksums. Label the downloads
   Apple Silicon and Intel clearly. Update the website's download resolution and
   localized READMEs in the same release; do not remove the previous universal
   asset while public links still target it. Do not advertise macOS 28 testing
   until acceptance has actually run on that OS. Packaging locally does not
   authorize uploading or replacing a public release.
5. Keep every stable release available. A rebuild of an existing stable tag is
   only appropriate for a packaging correction, and must retain clear notes.
