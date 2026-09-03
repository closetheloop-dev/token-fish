# Security notes

Token Fish is an unsandboxed, non-elevated Omarchy (Quickshell/QML) plugin. This document
summarizes what it runs, reads, and writes, for reviewers and users.

## What it executes

- `omarchy-agent-usage-update` — the built-in Omarchy collector, run on a ~2-minute timer to
  refresh the summarized token-usage records.
- `find` — to list `*.json` records in the usage directory (`-maxdepth 1 -type f`). Its
  output is streamed line by line rather than collected, and the retained filename list is
  capped at 64 entries of at most 128 characters each.
- `mkdir -m 700 -p` — to create the plugin's own state directory owner-only.

No network requests are made. No shell (`sh -c`) is invoked. No elevated privileges are used
or requested.

## What it reads

Only the summarized per-agent JSON that `omarchy-agent-usage-update` produces under
`~/.local/state/omarchy/agents/usage/`. It never reads raw agent session files or
credentials. Numeric fields read from that JSON are accepted only as real numbers or numeric
strings; anything else (booleans, arrays, objects, non-finite values) is rejected. A record
with no valid token field is ignored (the cursor is left unchanged) rather than treated as a
zero, the per-agent total is clamped to a finite range, and the resulting pellet count per
feed is additionally capped.

## What it writes

Token Fish's own code writes only its settings at
`${XDG_STATE_HOME:-$HOME/.local/state}/io.github.closetheloop-dev.token-fish/settings.json`,
and only when you change a control in the panel. It does not modify `~/.config` or any other
application's configuration.

Running the built-in `omarchy-agent-usage-update` on the ~2-minute timer causes that command
to (re)generate the summarized usage records under `~/.local/state/omarchy/agents/usage/` —
the same files Omarchy's built-in Agents module maintains. Token Fish triggers and reads
those records; it does not write them itself.

Settings persistence uses Quickshell's `FileView` with `atomicWrites: true` (temporary file +
rename), the same pattern Omarchy's first-party `clipboard` and `agents` plugins use. The
state directory is created with mode `0700`. A directory created by an earlier version keeps
its prior mode; it is not retroactively `chmod`ed, because a plain chmod would follow a
symlink placed at that path and the stored preferences are non-sensitive.

## Scope and limits

These settings are non-sensitive per-user aquarium preferences. `FileView` does **not**
independently demonstrate `O_NOFOLLOW`, file-ownership, path-component, or explicit
file-mode enforcement, and this plugin does not add a native helper to do so. The atomic
`FileView` approach matches the persistence mechanism used by first-party Omarchy plugins and
is proportionate for user-owned, non-sensitive state in an unelevated plugin.

## Shader artifact

The compiled shader `shaders/wave.frag.qsb` is reproducible from its GLSL source
`shaders/wave.frag` via `shaders/build.sh` (pinned `qsb` command). CI rebuilds it in a
toolchain pinned to a fixed Arch package-archive snapshot (fixing the exact
`qsb`/`qt6-shadertools` version) and fails if the committed binary drifts from a fresh build.
Inspect the shipped binary with `qsb -d shaders/wave.frag.qsb`.
