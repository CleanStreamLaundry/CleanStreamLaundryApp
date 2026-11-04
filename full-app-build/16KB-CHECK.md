# Accepted Debug APK: 16 KB Inspection

Source-prepared only; QA owns the single execution. No build/install/launch or
dependency change. Existing tools were located, not executed by the author.

QA's first authorized run exited 2 before ZIP/ELF checks: the SHA-pinned APK
contains 7 arm64-v8a, 5 x86_64 and 5 armeabi-v7a libraries. The Flutter arm64
target did not remove other ABIs supplied by plugins. No alignment verdict was
produced. Revised runner accepts those three known ABIs, verifies ELF identity for
each, and applies 16 KB segment criteria to the 12 packaged 64-bit libraries only.
The five ARM32 entries are explicitly `evaluated16kb: false`, not 16 KB passes.

Official [Android guidance](https://developer.android.com/guide/practices/page-sizes)
checked 2026-09-30 requires LOAD alignment of at least 2**14 and APK ZIP checking
with `zipalign -c -P 16 -v 4`. Its RELRO section additionally checks
`(VirtAddr + MemSiz) % 0x4000 == 0`; no RELRO segment is not an alignment failure.
Use existing Build-Tools 36.0.0 zipalign and NDK 28.2.13676358 llvm-readelf.

## QA Command

```sh
/Users/jamaki604/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node --max-old-space-size=128 /Users/jamaki604/CleanStreamProjects/.campaign-work/firebase/full-app-build/inspect-16kb.mjs
```

Fixed input:
`/Users/jamaki604/CleanStreamProjects/CleanStreamLaundryApp/build/app/outputs/apk/debug/app-debug.apk`

Required SHA256:
`ffaf0c1ba176c8b1ae82c70698430008c289bf0f13ec7d761e2c29abafbe756b`

Runner streams hashes, serializes subprocesses (60-second timeout each), and extracts
one packaged library at a time. Only native entries are extracted; .env/assets,
DerivedData and dependency caches are not searched or copied. Node heap is capped
at 128 MiB; this is not a total RSS cap for the native tools. No ZIP mutation,
alignment repair, APK replacement or network request is performed.

Outputs: this directory's `16kb-results/inspection-*/report.json`, native inventory,
zipalign stdout/stderr, numbered readelf logs. Temporary ELF is deleted after each
inspection. Empty/duplicate/unexpected ABI inventories or unparsed ELF are errors,
not passes. Input SHA must match before and after. Evaluated 64-bit LOAD segments
must meet the alignment rule and have congruent offset/address modulo 16 KB; every present RELRO
end in evaluated 64-bit libraries must meet the documented rule. ARM32 LOAD/RELRO
counts are inventory only. ZIP check must exit zero. Compressed libraries
are not expected to have direct-map ZIP offsets; zipalign applies that distinction.

Exit 0 = this APK's static checks pass; 1 = alignment finding; 2 = inspection/input
error. Report actual library/LOAD/RELRO counts and exact failing library/segment,
not a unit-test count. Retain raw evidence; request owner review before any fix.

## Remaining Gate

This debug APK uses debug Flutter/kernel artifacts; it does not establish release
AOT libapp.so, release engine or AAB-generated split APK compatibility. Packaged
x86_64 plugin inspection is not acceptance of a complete x86_64 Flutter application.
The eventual release bundle still needs its PAGE_ALIGNMENT_16K packaging setting
and generated APKs checked. Static alignment also cannot prove absence of runtime
4 KB assumptions; actual 16 KB device testing remains separate and unauthorized
here. No dependency upgrade is proposed without a concrete finding.
