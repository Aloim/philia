# Changelog

All notable changes to **Philia** (published as **collabterm** before v1.1).

---

## v1.1 (2026-07-11)

The rename release: **collabterm** is now **Philia**, named after the Greek goddess of
friendship. No functional changes.

### Changed
- Project, scripts, and UI renamed: `launch-collabterm.bat` is now `launch-philia.bat`,
  `_collabterm.ps1` is now `_philia.ps1`, `collab-overlay.ps1` is now `philia-overlay.ps1`,
  and the on-screen indicator now reads "philia live".
- README restructured: table of contents, separate install and usage sections, and
  per-mode security notes that state exactly which guarantees apply to collaborative mode
  and which to simple mode.

### Added
- This changelog.

---

## v1.0 (2026-06-10, as collabterm)

Initial public release, including the follow-up hardening shipped shortly after:

- Collaborative mode: a multi-user web terminal with shared tabs and a chat sidebar,
  served by a small Node server and exposed through a temporary Cloudflare tunnel.
- Simple mode: a single web terminal via ttyd for quick 1:1 shares.
- Password auth with a fresh random password per run, plus `SHARE_PASSWORD` to pin one.
- Host-only kill switch: an admin URL printed only in the host window adds a
  "Stop session" button that tears down the whole session for everyone.
- Kill-on-close job object in collaborative mode, so a force-closed host window still
  takes down the server, the shells, and the public tunnel.
- Always-on-top "live" indicator on the host's screen for the whole session.
- WebSocket heartbeat so idle sessions survive Cloudflare's idle timeout, and client
  auto-reconnect for dropped connections.
- Startup loading screen, tab bar scrollbar fix, and the PolyForm Noncommercial 1.0.0
  license.
