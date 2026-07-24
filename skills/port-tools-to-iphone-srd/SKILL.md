---
name: port-tools-to-iphone-srd
description: Port an existing command-line tool, daemon, shell, library-backed utility, or Unix software project to an Apple iPhone Security Research Device (SRD). Use when Codex needs to cross-compile for arm64e iOS with Xcode, adapt Autoconf or Make builds, answer cross-compile runtime probes, graft selectively available headers, remove unsupported APIs or modules, choose static versus dynamic linkage, patch randomized cryptex resource paths, assemble and sign a cryptex root, add srdtool installation targets, or validate the finished Mach-O and runtime resources.
---

# Port tools to an iPhone SRD

## Define the port

Write acceptance criteria before editing:

- Target architecture and minimum iOS version (target iOS 26 and higher by default).
- Required commands, libraries, modules, plugins, and data files.
- Interactive behavior such as PTYs, key maps, terminal capabilities, history,
  and signals.
- Runtime entry point: `srdtool research spawn`, launch daemon, SSH, or wrapper.
- Persistent and writable state locations.
- Install identifier and replacement behavior.

Inspect the upstream source, build system, license, current release, and
checksum source. Pin an immutable source archive and verify it before extracting.

Read [references/porting-playbook.md](references/porting-playbook.md) for
build patterns and failure diagnosis. Read
[references/zsh-case-study.md](references/zsh-case-study.md) when the target
uses Autoconf, modules, terminal UI, completion data, or compiled resource
paths.

## Inspect the SRD reference implementation

Locate Apple's `security-research-device` repository (path to it should be available in `SRD_REPO_PATH`).
Read, in order:

1. `example-cryptex/README.md`
2. `example-cryptex/build_env.mk`
3. `example-cryptex/Makefile`
4. The closest example under `example-cryptex/src/`
5. Current `srdtool ... --help`

Reuse current patterns, but do not copy obsolete SDK names, deployment targets,
or command flags blindly.

## Characterize incompatibilities

Inventory:

- Build-time tools that must run on the Mac versus target binaries.
- Configure tests that execute target programs.
- Headers present only in macOS, XNU sources, or private SDKs.
- APIs unavailable on iOS.
- Dynamic modules, plugins, `dlopen`, and fixed module directories.
- Subprocess, PTY, networking, locale, terminfo, user database, and filesystem
  assumptions.
- Embedded paths such as `/usr/share`, `/etc`, `/usr/lib`, and `/var`.
- Files generated during the build and whether they use the target preprocessor.

Prefer feature reduction over fake detection. Disable obsolete or unsupported
components explicitly and document the loss.

Remember that on iPhone Security Research Device normal iOS restrictions
do not apply: you can sign binaries with arbitrary entitlements and
use any private API as long as the private API exists in the iOS runtime.

## Build for the actual target

Resolve tools and SDKs through `xcrun`. Apply the same target flags to compile,
preprocess, and link steps:

```text
-isysroot <iphoneos-sdk>
-arch arm64e
-miphoneos-version-min=<version>
```

For Autoconf:

1. Build out of tree.
2. Set `CC`, `CPP`, `CFLAGS`, `CPPFLAGS`, and `LDFLAGS` explicitly.
3. Pass a native Mac build tuple and an arm64e Darwin host tuple.
4. Cache only runtime checks that cannot execute while cross-compiling.
5. Derive cached answers from SDK headers, source inspection, platform ABI, or
   a justified native-Darwin comparison. Never guess.

Graft a missing header only after verifying the corresponding ABI or system
library exists on iOS. Copy the smallest required header set into a private
compatibility include directory. Do not link macOS libraries into the target.

## Design for cryptex runtime constraints

Prefer one signed executable with required modules linked statically when
upstream dynamic loading depends on fixed paths or unsigned bundles.

Install into a distribution root such as:

```text
<name>-cryptex.root/
├── Library/LaunchDaemons/
├── usr/bin/
├── usr/libexec/
├── usr/lib/
└── usr/share/
```

Ad hoc sign every Mach-O after its final modification, including entitlements as needed.
Include all required functions, terminfo, locale, configuration, schemas, 
certificates, or helper data.

Never compile a randomized cryptex mount point. Use `CRYPTEX_MOUNT_PATH` in
launchers and patch resource lookup when upstream insists on absolute paths.
Preserve normal user paths such as `HOME`, history, and user startup files.

## Make the workflow reproducible

Provide separate targets for:

```text
download -> source/patch -> configure -> build -> cryptex -> check -> install
```

Also provide `clean`, `distclean`, and useful overrides. Make downloads
atomic, validate checksums, apply patches deterministically, and rebuild a
cryptex root from scratch.

Resolve `srdtool` from `PATH` first and allow an explicit override. An install
target should validate the cryptex before invoking:

```sh
srdtool cryptex install \
  --persist \
  --identifier <stable.identifier> \
  <absolute-cryptex-root>
```

Inspect local help before fixing option order or names.

## Validate proportionately

Run `scripts/validate-srd-binary.sh` on every primary executable:

```sh
skills/port-tools-to-iphone-srd/scripts/validate-srd-binary.sh \
  path/to/cryptex.root/usr/bin/tool arm64e 26.0
```

Also verify:

- required modules were linked or packaged;
- expected resources and launch plists exist;
- no target step silently used host headers or libraries;
- startup files work from a randomized mount;
- non-interactive features pass deterministic smoke tests;
- interactive tools work on an actual PTY over SSH;
- the same-identifier reinstall path behaves correctly.

Do not claim full success from host-side inspection alone. State clearly when
device validation remains.

Explicitly ask the user for permission to install the built cryptex and access 
the device over SSH to test it. Only perform those actions if allowed.

## Preserve maintainability

- Keep upstream changes in numbered patch files.
- Explain every configure-cache answer.
- Keep version, URL, checksum, architecture, deployment target, identifier,
  and tool paths visible near the top of the build.
- Avoid copying generated build products into source control.
- Document intentionally omitted functionality.
- Re-run a clean build after editing patches or compatibility headers.
