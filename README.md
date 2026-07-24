# Agent Skills for Apple Security Research Device

This repository contains skills that allow coding agents to work
more effectively with security research devices.

## Requirements

- Access to the Apple Security Research Device program
- A local copy of Apple's `security-research-device` repository (export `SRD_REPO_PATH` so that agents can easily find it)
- Xcode and command-line development tools
- Optional, but highly recommended: `srdtool` exported in `PATH`

> TIP: There are other handy environment variables you can set to help agents work with your SRD. Read the `Useful Environment Variables and SSH Access` section in `skills/use-iphone-srd/SKILL.md` for more details.
## Install/Update

Run the `./install` script. It will ask you if you’d like to install the skills for Codex and/or Claude, and whether to install locally within the current project or globally.