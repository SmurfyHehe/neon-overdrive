# discord_rich_presence (vendored, unmodified)

- Source: https://github.com/SlayHorizon/discord-rich-presence-godot
- Commit: c69c6f9e00b006ca3ae912e2c1f4fc0bbf9cb850 (v1.2, 2026-10-10)
- Licence: MIT (LICENSE, next to this file)
- What it is: one pure-GDScript file, no DLLs. On Windows it opens Discord's
  local named pipe with FileAccess. It does nothing under --headless, and
  retries every 20 s while Discord is closed.
- Used by scripts/core/discord_presence.gd. Do not edit; update by re-vendoring.
