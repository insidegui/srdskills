# SRD porting playbook

## Contents

- [Repository shape](#repository-shape)
- [Source acquisition](#source-acquisition)
- [Toolchain setup](#toolchain-setup)
- [Autoconf cross-compilation](#autoconf-cross-compilation)
- [SDK header grafting](#sdk-header-grafting)
- [Linkage and modules](#linkage-and-modules)
- [Cryptex layout and signing](#cryptex-layout-and-signing)
- [Runtime paths and writable state](#runtime-paths-and-writable-state)
- [Build target design](#build-target-design)
- [Validation matrix](#validation-matrix)
- [Failure diagnosis](#failure-diagnosis)

## Repository shape

Keep inputs, outputs, patches, runtime configuration, and tests separate:

```text
project/
├── Makefile
├── config/
├── patches/
├── tests/
├── downloads/             # ignored
├── build/                 # ignored
└── tool-cryptex.root/     # ignored
```

Use stamp files for expensive stages, but make each stamp depend on every input
that materially changes the stage. A configuration or packaging change must
invalidate the correct output.

## Source acquisition

Prefer the upstream release archive over a moving branch. Pin:

- version;
- canonical HTTPS URL;
- cryptographic checksum from an upstream source.

Download to a temporary filename, verify it, then rename atomically. Extract to
a build-owned source directory and apply ordered patch files with batch mode.
Fail if any hunk does not apply.

Do not silently reuse a corrupt pre-existing archive. Either verify every time
or make the verified archive the only way the final name is created.

## Toolchain setup

Resolve the active SDK and Clang:

```make
SDK ?= iphoneos
ARCH ?= arm64e
IOS_MIN_VERSION ?= 15.0

SDK_PATH = $(shell xcrun --sdk "$(SDK)" --show-sdk-path)
IOS_CC = $(shell xcrun --sdk "$(SDK)" --find clang)

TARGET_FLAGS = -isysroot $(SDK_PATH) -arch $(ARCH) \
	-miphoneos-version-min=$(IOS_MIN_VERSION)
CFLAGS = -O2 $(TARGET_FLAGS)
CPPFLAGS = -isysroot $(SDK_PATH) -I$(COMPAT_INCLUDE_DIR)
LDFLAGS = $(TARGET_FLAGS)
```

Use the iPhoneOS SDK, not an iOS Simulator SDK. Keep host tools on the native
Mac toolchain. Do not run an arm64e iOS generator binary on the Mac.

Apply target identity at every stage. Generated sources often invoke `CPP`
directly and ignore `CPPFLAGS`; set both:

```sh
CPP="$IOS_CC -E -isysroot $SDK_PATH -I$COMPAT_INCLUDE_DIR"
```

## Autoconf cross-compilation

A typical configure invocation is:

```sh
env \
  CC="$IOS_CC" \
  CPP="$IOS_CC -E -isysroot $SDK_PATH -I$COMPAT_INCLUDE_DIR" \
  CFLAGS="$TARGET_CFLAGS" \
  CPPFLAGS="$TARGET_CPPFLAGS" \
  LDFLAGS="$TARGET_LDFLAGS" \
  /path/to/configure \
    --build="$(/path/to/config.guess)" \
    --host=arm64e-apple-darwin \
    --prefix=/usr \
    --cache-file=/absolute/path/to/config.cache
```

Cross-compiling prevents configure from running target executables. For each
cached answer:

1. Find the exact configure test.
2. Decide whether it is compile-time, ABI-defined, kernel behavior, or library
   runtime behavior.
3. Prove the answer from target headers, platform documentation, source, or a
   defensible Darwin comparison.
4. Record why the answer is safe.
5. Compare generated configuration with a native Darwin build where useful.

Never copy a cache wholesale between unrelated projects or platforms.

Common hidden cross-build problems:

- a generated signal or errno table preprocesses host headers;
- `config.guess` and build generators need host execution;
- configure reports a feature absent only because its runtime probe could not
  run;
- an upstream Makefile drops `-isysroot` in subdirectories;
- link checks succeed against the wrong SDK.

Inspect the full configure log and final link command.

## SDK header grafting

Apple's public iPhoneOS SDK can expose a system dylib while omitting a public
header required by older Unix software. Apple's SRD examples use a private
compatibility include directory populated from the macOS SDK or XNU sources.

Use this only when all conditions hold:

1. The target library or ABI is present on iOS.
2. The declarations match the target ABI.
3. The software does not begin using a macOS-only symbol merely because the
   declaration became visible.
4. Link and runtime validation cover the feature.

Copy only required headers:

```make
$(COMPAT_INCLUDE_DIR)/%.h: $(MACOS_SDK_PATH)/usr/include/%.h
	mkdir -p "$(dir $@)"
	cp "$<" "$@"
```

Never add the macOS SDK library path to target linkage. A header graft is a
compile-time compatibility technique, not permission to mix platforms.

Prefer patching or disabling a feature when the target ABI is absent.

## Linkage and modules

Dynamic plugins create several SRD problems:

- randomized mount paths;
- compiled module directories under `/usr/lib`;
- unsigned or separately signed Mach-O bundles;
- runtime `dlopen` behavior and missing dependencies.

When practical, link essential modules statically into the main executable.
Preserve optional features only if the result remains testable and maintainable.

Do not confuse "static modules" with a fully static executable. iOS binaries
normally link system dylibs from `/usr/lib` and `/System/Library`.

Audit every dependency with `otool -L`. Package non-system dylibs inside the
cryptex, sign them, and use a valid runtime lookup design. Avoid unreviewed
host library paths.

## Cryptex layout and signing

Install with `DESTDIR` into a root that uses final device paths:

```text
tool-cryptex.root/usr/bin/tool
tool-cryptex.root/usr/share/tool/...
tool-cryptex.root/Library/LaunchDaemons/com.example.tool.plist
```

Sign after stripping, rewriting load commands, or making any final binary
change:

```sh
codesign --force --sign - tool-cryptex.root/usr/bin/tool
```

Sign all Mach-O executables, dylibs, and bundles. Preserve executable modes.
Validate launch plists and use stable reverse-DNS identifiers.

Install with current `srdtool` syntax discovered from local help. Allow:

- `SRDTOOL` override;
- ECID override;
- identifier override;
- persistence/verbose flags;
- an install target that depends on validation.

## Runtime paths and writable state

Cryptexes mount at randomized directories below:

```text
/private/var/run/com.apple.security.cryptexd/mnt
```

Do not substitute a mount path at build time. Use `CRYPTEX_MOUNT_PATH` in:

- launch wrappers;
- configuration lookup;
- plugin or module lookup;
- `PATH`, `FPATH`, `TERMINFO`, and data roots;
- daemon child environments.

Patch compiled absolute resource paths narrowly. Prefix global packaged
resources with the current mount, but leave user-controlled paths such as
`HOME`, `ZDOTDIR`, history, caches, and temporary files writable and normal.

For tools spread across cryptexes, enumerate mounted roots at process startup
and add existing standard executable directories. Use a stable precedence
policy and deduplicate.

Avoid writing caches into the cryptex. Choose a writable home, `/tmp`, or an
application-specific writable location.

## Build target design

A useful Make graph is:

```text
all -> cryptex
download
source
configure
build
cryptex (or dstroot)
check
install
clean
distclean
```

`check` should verify:

- architecture;
- iOS build platform and minimum OS;
- code signature;
- linked dylibs;
- required modules;
- resource files;
- launch plists;
- deterministic host-side feature tests.

`install` should depend on `check`. Resolve `srdtool` from `PATH` before using a
repository fallback:

```make
PATH_SRDTOOL := $(shell command -v srdtool 2>/dev/null)
SRDTOOL ?= $(if $(PATH_SRDTOOL),$(PATH_SRDTOOL),$(SRD_REPOSITORY)/bin/srdtool)
```

Use `command -v "$(SRDTOOL)"` for validation because `test -x srdtool` does not
search `PATH`.

## Validation matrix

### Host-side binary checks

- `file`: Mach-O and expected architecture.
- `lipo -archs`: arm64e slice.
- `xcrun vtool -show-build`: platform `IOS`, supported minimum OS.
- `codesign --verify --strict`: valid final signature.
- `otool -L`: only expected target dependencies.

### Package checks

- Correct `/usr/bin` or `/usr/local/bin` placement.
- Every Mach-O signed.
- All data/functions/terminfo/locales included.
- Startup files use runtime mount paths.
- No build-host absolute paths.
- No unneeded source, object, or temporary files.

### Feature checks

Create smoke tests for the acceptance criteria. For a shell, test history
write/read, key map setup, completion initialization, terminal parameters,
PTY creation, networking modules, and resource lookup independently.

Host tests cannot execute an iOS binary directly. Test scripts and package
structure on the host, then run the executable on the SRD through the intended
launcher.

## Failure diagnosis

| Symptom | Likely cause | Check |
|---|---|---|
| Configure marks working APIs absent | Runtime probe could not execute | `config.log`, cache variable |
| Generated constants match macOS | Generator used host preprocessor | Explicit `CPP`, build log |
| Header not found but dylib exists | iPhoneOS SDK omits public header | Target ABI, minimal graft |
| Link succeeds but launch fails | Wrong platform, missing dylib, bad signature | `vtool`, `otool`, `codesign` |
| Plugin/module not found | Fixed path or unsigned bundle | Static linkage, mount-relative path |
| Resource file not found | Compiled absolute path ignores mount | `CRYPTEX_MOUNT_PATH` propagation |
| Works via one launcher only | Environment rebuilt differently | Compare `env`, PATH, HOME, TERM |
| Completion security warning | Build UID differs on device | Narrow trust for signed read-only tree |
| Interactive keys/history fail | Missing terminfo, HOME, PTY, startup file | Test each layer separately |
| `srdtool` "not executable" despite PATH | Used `test -x` on a bare command | Use `command -v` |
