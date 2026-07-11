# Changelog

All notable changes to **Philia** (published as **collabterm** before v1.1).

---

## v1.2 (2026-07-11)

Hardening release: brute-force protection with a visible cooldown, loopback-only
listeners, and the same kill-on-close safety net for both modes.

### Added
- Brute-force protection on the collaborative server. All state is global, so guessing
  from many IPs at once does not help:
  - Every wrong password blocks the next attempt for 5 seconds; the login card shows the
    wait as a live countdown with a draining bar, and retries automatically when the
    attempt was blocked without being evaluated.
  - 5 wrong attempts lock new attempts out for 5 minutes, then 3 attempts / 10 minutes,
    then 2 attempts / 30 minutes (three rounds), then 1 attempt per hour for as long as
    the guessing continues. A warning appears when 2 or fewer attempts remain, and a
    correct login resets the ladder.
  - While a lockout or the 5 second gap is active, attempts are rejected without being
    checked, so a correct guess in that window buys nothing.
- Simple mode now has the same safety net as collaborative mode: the kill-on-close job
  object (a force-closed window takes the tunnel down with it), the "philia live"
  indicator, the startup loading screen, and Enter-to-stop. Its logic moved from
  `launch-simple.bat` into the new `_simple.ps1`.
- The web terminal scales its font down on narrow windows so all 120 columns stay
  visible, and stacks the chat below the terminal on phone-sized screens.
- The collaborative launcher checks for Node.js up front and explains what to install,
  instead of printing a public link that can never answer.

### Changed
- Both servers now listen on 127.0.0.1 only, so sessions are reachable only through the
  tunnel link or on the host PC itself, not from the local network.
- `server.js` generates a random password instead of falling back to "changeme" when
  started without `SHARE_PASSWORD`.
- Startup cleanup now only kills ttyd and cloudflared processes started from this
  install's `tools\` folder, not every such process on the machine.

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
