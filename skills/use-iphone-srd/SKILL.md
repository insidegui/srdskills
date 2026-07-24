---
name: use-iphone-srd
description: Operate, inspect, and troubleshoot an Apple iPhone Security Research Device (SRD) and its host tooling. Use when Codex needs to work with srdtool device discovery or configuration, check-in or restore workflows, cryptex installation and lifecycle, securityresearchd commands, randomized cryptex mounts, CRYPTEX_MOUNT_PATH, launch daemons, SSH integration, or SRD runtime diagnostics. Use the separate port-tools-to-iphone-srd skill when the primary task is adapting and cross-compiling an existing software project.
---

# Use an iPhone Security Research Device

## Establish local truth

Treat the checked-out Apple `security-research-device` repository and the
installed `srdtool --help` output as authoritative. SRD tooling evolves.

If the `SRD_REPO_PATH` environment variable is set, use that as the source
of truth for a local checkout of Apple's `security-research-device` repository.
If you can't find the `security-research-device` repository nearby, ask the
user to provide the full path to it and instruct them to set the `SRD_REPO_PATH`
environment variable so that you don't need to ask again in the future.

1. Locate `srdtool` with `command -v srdtool`. Also check a nearby
   `security-research-device/bin/srdtool` when working beside Apple's repo.
2. Run the narrowest relevant `--help` command before constructing a mutating
   command.
3. Locate Apple's example cryptex and current `bin/README.md`.
4. Inspect device state with read-only commands before installing,
   uninstalling, restoring, rebooting, or changing configuration.

Read [references/srd-reference.md](references/srd-reference.md) for command
patterns, cryptex runtime behavior, process-launch integration, and diagnostics.

## Route the task

- For device identity or selection, start with `srdtool list` and
  `srdtool config`.
- For packaged tools and daemons, use the `srdtool cryptex` lifecycle.
- For one-shot execution, file inspection, dylib injection, or launch-service
  work, inspect the relevant `srdtool research` subcommand and its limitations.
- For firmware research, distinguish persistent restore-time firmware from
  ephemeral `research firmware` loading.
- For interactive programs, use SSH or another PTY-capable transport rather
  than `research spawn`.
- For source ports, switch to `$port-tools-to-iphone-srd`.

## Handle cryptex paths correctly

Never persist or compile a randomized mount suffix. Installed cryptexes appear
below:

```text
/private/var/run/com.apple.security.cryptexd/mnt/<identifier>.<random>
```

Use `srdtool cryptex list` to inspect current mount points. For processes
launched from a cryptex launch daemon, consume `CRYPTEX_MOUNT_PATH`. Propagate
it through SSH servers, wrappers, or child-process launchers that rebuild the
environment.

Construct paths from the mount root at runtime:

```text
$CRYPTEX_MOUNT_PATH/usr/local/bin
$CRYPTEX_MOUNT_PATH/usr/bin
$CRYPTEX_MOUNT_PATH/bin
$CRYPTEX_MOUNT_PATH/usr/local/sbin
$CRYPTEX_MOUNT_PATH/usr/sbin
$CRYPTEX_MOUNT_PATH/sbin
```

Prefer the current cryptex, then the inherited system path, then tools from
other cryptexes. This avoids unexpected command shadowing.

## Verify outcomes

After a state change:

1. Re-list the device or cryptex state.
2. Confirm the actual mount point and identifier.
3. Test the smallest non-interactive command first.
4. Confirm required environment variables in the launched process.
5. Test PTY, terminal, history, and signal behavior separately for interactive
   tools.
6. Preserve verbose output and host/device logs on failure.

## Apply safety boundaries

- Do not restore, reboot, uninstall, replace firmware, inject a dylib, or alter
  a live service unless the user requested that state change.
- Resolve the ECID and cryptex identifier before destructive operations.
- Assume personalization may require an unlocked SRD and host network access.
- Treat a same-identifier cryptex install as a replacement operation.
- Do not confuse a shareable distribution root or disk image with a
  device-personalized cryptex.
- Do not infer success from a build alone; verify the installed runtime.
