# zsh-to-SRD case study

## Contents

- [Goal and result](#goal-and-result)
- [Source and target](#source-and-target)
- [Cross-configuration](#cross-configuration)
- [Headers and libraries](#headers-and-libraries)
- [Static module strategy](#static-module-strategy)
- [Randomized mount handling](#randomized-mount-handling)
- [Interactive resources](#interactive-resources)
- [Cryptex-wide tool discovery](#cryptex-wide-tool-discovery)
- [Completion ownership mismatch](#completion-ownership-mismatch)
- [Validation](#validation)
- [Transferable conclusions](#transferable-conclusions)

## Goal and result

The `srdzsh` project turned an empty directory into a reproducible Make build
that downloads, patches, cross-compiles, packages, validates, and installs zsh
as an SRD cryptex.

The acceptance criteria included more than launching `zsh`:

- ZLE and key maps;
- persistent history;
- completion;
- terminfo;
- PTYs;
- networking and useful modules;
- randomized cryptex mount support;
- SSH login-shell behavior.

This forced build-time and runtime concerns to be handled together.

## Source and target

The build pinned the then-current official zsh 5.9.2 archive and upstream
SHA-256. It targeted:

- iPhoneOS SDK;
- arm64e;
- iOS deployment minimum 26.0;
- an out-of-tree Autoconf build;
- a single ad-hoc-signed executable plus script/data resources.

Versions and checksums are historical details. The reusable lesson is to
re-discover and pin the current upstream release rather than copying them.

## Cross-configuration

Autoconf correctly detected cross-compilation and therefore could not execute
target probes. Untended probes defaulted to false and would have disabled
working behavior.

The build supplied a documented cache for Darwin/iOS properties such as:

- 64-bit `long`;
- `%lld` support;
- working fixed `mmap`;
- working `strcoll`;
- `realpath(NULL)` behavior;
- termcap probe semantics;
- `rlim_t` size and signedness;
- allocating `getcwd`.

These answers were compared with native Darwin configuration and target
headers. They are not a generic cache for other projects.

Generated signal and errno tables required an explicit target `CPP`. Supplying
only `CPPFLAGS` was insufficient because upstream generated rules called the
preprocessor directly.

## Headers and libraries

The iPhoneOS SDK provided `libncurses` but omitted public curses and term
headers expected by zsh. The build copied the minimal header family from the
active macOS SDK into a private compatibility include directory:

```text
curses.h
ncurses.h
ncurses_dll.h
term.h
unctrl.h
```

The target still linked the iOS system `libncurses`, never a macOS library.
Configure and link checks then verified the expected APIs.

This is a narrowly justified header graft, not a general instruction to expose
all macOS declarations to an iOS build.

## Static module strategy

Upstream zsh normally builds many loadable modules. Dynamic bundles would add
signature, lookup-path, and randomized-mount failure modes. The port disabled
dynamic modules and patched supported modules to link statically.

Important statically available functionality included:

- ZLE, completion, completion lists, and completion utilities;
- termcap, terminfo, and curses;
- regex;
- PTY and selection support;
- system, stat, files, mapfile, math, and private parameters;
- TCP and Unix-domain sockets;
- profiling and other common modules.

The obsolete zftp module was omitted because it required `arpa/telnet.h`,
absent from the iPhoneOS SDK. Modern TCP and socket modules remained.

The transferable rule is to preserve required capabilities while removing
obsolete components with unavailable platform contracts.

## Randomized mount handling

zsh compiled absolute global startup paths such as `/usr/share/zsh/...`.
Custom cryptexes mount below a randomized root, so those paths would miss
packaged files.

A small upstream patch introduced a helper that prefixes compiled global
resource paths with `CRYPTEX_MOUNT_PATH`. Calls that source global zsh startup
files use the helper. User startup paths still resolve through `HOME` or
`ZDOTDIR` and are not redirected into the cryptex.

The packaged `zshenv` uses the mount root to set:

- executable paths;
- `fpath`;
- `TERMINFO`.

This is preferable to replacing every filesystem operation or hardcoding a
mount suffix.

## Interactive resources

The cryptex installed the complete upstream function tree and selected common
compiled terminfo entries. The global interactive configuration enabled:

- a persistent history file in `HOME`;
- minimum history sizes;
- append and duplicate-handling options;
- Emacs key maps;
- arrow, Home, End, Delete, and control-arrow bindings;
- completion initialization.

Host smoke tests verified history writes, key bindings, and completion setup.
The target binary could not execute on macOS, so on-device SSH remained a
separate validation layer.

## Cryptex-wide tool discovery

To find tools from separately installed cryptexes, startup enumerates:

```text
/private/var/run/com.apple.security.cryptexd/mnt/*
```

It adds existing common executable directories. Precedence is:

1. the current cryptex;
2. inherited/system `PATH`;
3. other cryptexes in lexical mount-directory order.

The design deduplicates entries and handles mount names safely. Appending other
cryptexes prevents an unrelated package from silently overriding a system
command.

## Completion ownership mismatch

On-device SSH exposed a subtle packaging issue:

```text
zsh compinit: insecure directories and files
compdump: function definition file not found
```

The packaged functions retained build-host ownership metadata that did not
match the SSH user's UID. `compaudit` treated the signed, read-only cryptex tree
as insecure. After the user accepted the warning, `compinit` removed that
directory from `fpath`; `compdump` lived in the removed directory. A subsequent
standalone `compaudit` reported nothing because it saw the already-filtered
path.

The fix used `compinit -u` only when `CRYPTEX_MOUNT_PATH` proved execution
inside the cryptex. Normal ownership auditing remained outside that context.
A regression test mocked the rejection path and verified prompt-free
completion initialization.

The transferable lesson is to adapt ownership heuristics narrowly when signed,
immutable package metadata crosses machines.

## Validation

The build's `check` target verified:

- Mach-O arm64e;
- `LC_BUILD_VERSION` platform `IOS`;
- deployment minimum and SDK metadata;
- strict code-signature validity;
- linked system dylibs;
- required static modules in generated configuration;
- completion functions, startup files, and terminfo;
- history, key map, completion, and cryptex path smoke tests.

The install recipe was tested with a harmless `srdtool` stand-in to validate
argument construction without mutating a device.

## Transferable conclusions

1. Define runtime feature criteria before declaring a port complete.
2. Cross-configure explicitly; false negatives are common.
3. Treat generated preprocess steps as part of the target toolchain.
4. Graft headers only when the target ABI truly exists.
5. Prefer static modules when randomized mounts and code signing make plugins
   fragile.
6. Patch packaged resource lookup, not user state paths.
7. Include terminal and completion data, not just the executable.
8. Test launcher environments because SSH and launchd can rewrite them.
9. Interpret build-host ownership cautiously inside signed cryptex images.
10. Make install depend on structural and behavioral validation.
