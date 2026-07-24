# iPhone SRD operational reference

## Contents

- [Host and device setup](#host-and-device-setup)
- [srdtool command map](#srdtool-command-map)
- [Cryptex model](#cryptex-model)
- [Cryptex runtime integration](#cryptex-runtime-integration)
- [securityresearchd workflows](#securityresearchd-workflows)
- [Interactive shells and daemons](#interactive-shells-and-daemons)
- [Troubleshooting](#troubleshooting)
- [Durable lessons](#durable-lessons)

## Host and device setup

Verify current requirements in the local Apple repository. At the time this
reference was prepared, the current `srdtool` documentation required macOS
Tahoe 26 or later. Also require Xcode and a selected developer directory:

```sh
xcode-select -p
xcrun --sdk iphoneos --show-sdk-path
command -v srdtool
```

Discover a connected SRD and record its ECID:

```sh
srdtool list
srdtool list --stream
```

Save the Apple Account and ECID when appropriate:

```sh
srdtool config --user researcher@example.com --ecid 0x0123456789abcdef
srdtool config
```

The current configuration is stored below the user's Library directory in
`com.apple.srdtool/config.plist`. Most commands also accept an explicit ECID.

An SRD must be kept checked in according to the program requirements:

```sh
srdtool checkin
```

Host network access is required for check-in and operations that contact
Apple's personalization service.

## srdtool command map

Always inspect the installed version:

```sh
srdtool --help
srdtool <subcommand> --help
```

Important command families:

- `list`: discover connected devices and identifiers.
- `config`: save or display the default user and ECID.
- `checkin`: perform the program check-in.
- `restore`: install a research iOS build; use this instead of OTA updates.
- `image4`: extract, decompress, or package firmware payloads.
- `cryptex`: list, install, and uninstall packaged code.
- `research`: interact with securityresearchd for spawning, file operations,
  firmware loading, dylib management, and launch-service work.

Do not memorize flags across versions. Re-read the local help before restore,
firmware, injection, or uninstall operations.

## Cryptex model

A cryptex distribution root is a directory shaped like a filesystem overlay:

```text
cryptex.root/
├── Library/LaunchDaemons/
├── usr/bin/
├── usr/local/bin/
├── usr/lib/
└── usr/share/
```

Mach-O content must be signed at least ad hoc before packaging. A cryptex
combines a disk image with authorization data for its executable content.

Install a root directory with a stable identifier:

```sh
srdtool cryptex install \
  --persist \
  --identifier com.research.example \
  /absolute/path/to/example-cryptex.root
```

Current `srdtool` behavior removes an existing cryptex with the same identifier
before installing its replacement. Use an explicit `--ecid` when the configured
default is absent or ambiguous.

List or remove installed cryptexes:

```sh
srdtool cryptex list
srdtool cryptex uninstall com.research.example
```

The host needs network access during personalization. The device generally
must be unlocked for cryptex management. On failure, `srdtool` may retain its
temporary staging directory for diagnosis.

A distribution root or pre-personalization disk image can be shared. A
personalized cryptex is tied to the target device and should not be treated as
portable.

## Cryptex runtime integration

Cryptexes mount below:

```text
/private/var/run/com.apple.security.cryptexd/mnt/
```

A mount name combines the identifier and a random suffix:

```text
com.research.example.A1b2C3
```

The suffix and full path can change. Discover it with:

```sh
srdtool cryptex list
```

Launch daemons can receive `CRYPTEX_MOUNT_PATH`, which identifies their own
mount. Build all internal absolute paths from it. Do not hardcode a prior mount
point.

When a launcher replaces the environment, explicitly preserve:

- `CRYPTEX_MOUNT_PATH`
- `PATH`
- `HOME`
- `SHELL`
- `TERM` for terminal sessions

When several cryptexes supply tools, enumerate current mount directories and
add only existing common `bin` and `sbin` directories. Deduplicate the result.
Start a new shell or refresh the environment after installing or removing a
cryptex.

## securityresearchd workflows

Set up the research daemon using the repository path required by the installed
tool:

```sh
srdtool research setup -r /path/to/security-research-device/apple-cryptexes/securityresearchd
srdtool research ping
```

Inspect the exact subcommand help before use:

```sh
srdtool research builtin --help
srdtool research spawn --help
srdtool research dylib --help
srdtool research firmware --help
srdtool research launchctl --help
```

`research spawn` is suitable for one-shot commands. It does not provide an
interactive terminal and does not interpret shell redirection or pipelines.
Pass arguments directly and use supported environment options. Use SSH for
interactive programs and compound shell workflows.

Distinguish:

- Restore-installed firmware: persistent and slower to iterate.
- `research firmware`: ephemeral for the current boot and safer for rapid
  experimentation.
- `research dylib`: installs separately managed libraries for injection.
- `research launchctl`: operates on system, user, or pid launch domains.

## Interactive shells and daemons

An interactive shell port needs more than an executable:

- A PTY-capable SSH or console transport.
- A valid writable `HOME`.
- A useful `TERM` value and matching terminfo entries.
- Correct signal, process-group, and terminal ioctl behavior.
- Runtime access to startup files, completion data, locale data, and history.
- A propagated cryptex mount path when resources live inside the cryptex.

If an SSH server launches a shell stored in its own cryptex, construct the
shell's absolute path from `CRYPTEX_MOUNT_PATH` and propagate the mount variable
to the child session.

Ownership-based safety checks can misinterpret cryptex content. Files may
retain a build-host UID that has no matching identity on the SRD. For a signed,
read-only packaged resource tree, narrowly bypass or adapt the ownership check
instead of disabling unrelated security checks globally.

## Troubleshooting

### Device is not discovered

1. Unlock and connect the SRD.
2. Run `srdtool list --stream`.
3. Verify the selected Xcode and host OS requirements.
4. Check USB connectivity before changing configuration.

### A cryptex operation targets the wrong device

1. Run `srdtool config`.
2. Compare the saved ECID with `srdtool list`.
3. Pass `--ecid` explicitly.

### Installation or personalization fails

1. Confirm host network access.
2. Confirm the device is unlocked.
3. Retry with the command's verbose option.
4. Preserve the retained staging directory and logs.
5. Validate all Mach-O files and signatures before retrying.

### A binary exists but cannot launch

Check:

- arm64e architecture;
- Mach-O build platform is iOS, not macOS or Simulator;
- deployment minimum is supported by the device;
- code signature validity;
- linked dylibs exist on iOS or in the cryptex;
- executable mode bits;
- randomized resource paths;
- required environment and entitlements.

### A command cannot be found over SSH

Print `PATH` and `CRYPTEX_MOUNT_PATH` inside the SSH session. SSH servers often
rebuild their child environment. Add cryptex-relative paths and propagate the
mount variable in the server or wrapper rather than setting a one-off path
manually.

### An interactive program behaves incorrectly

Separate transport issues from program issues. Check PTY allocation, `TERM`,
terminfo, locale, `HOME`, writable state, process groups, and signal handling.
Do not use `research spawn` as an interactive-shell test.

## Durable lessons

- Use the local Apple repository as executable documentation.
- Resolve identifiers before state changes.
- Use stable cryptex identifiers and unstable runtime mount paths.
- Treat distribution roots as shareable and personalized cryptexes as
  device-specific.
- Propagate launch environment deliberately.
- Validate build metadata before debugging runtime behavior.
- Test non-interactive execution and interactive terminal behavior separately.
