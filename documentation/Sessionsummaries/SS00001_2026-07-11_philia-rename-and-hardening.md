# Session Summary 00001: Philia rename (v1.1) and hardening release (v1.2)

**Date:** 2026-07-11
**Continuing from:** none (first session summary in this repository)
**Releases shipped:** v1.1 (rename), v1.2 (hardening)

> Two releases in one session. First the project was renamed from
> **collabterm** to **Philia** (after the Greek goddess of friendship) with a
> Phanes-style README, changelog, and repo description. Then a full checkup
> was run and every finding was fixed, headlined by layered brute-force
> protection designed in-session with the operator.

---

## 1. Goal of session

1. Rename the entire project from collabterm to Philia (scripts, UI, package
   metadata, license notice, git remote, GitHub description and topics).
2. Restructure the README to match the Phanes repository (contents table,
   install/use split, version section, `Changelog.md`), with no em dashes
   anywhere in published text.
3. Run a checkup for improvement opportunities, then (after operator review)
   fix all of them, replacing the "longer password" recommendation with an
   operator-designed lockout ladder plus a 5 second attempt gap with a
   visible countdown.

---

## 2. What was done

### 2.1 v1.1: rename and docs

- `launch-collabterm.bat` renamed `launch-philia.bat`, `_collabterm.ps1`
  renamed `_philia.ps1`, `collab-overlay.ps1` renamed `philia-overlay.ps1`
  (all via `git mv`); indicator label now "philia live".
- All UI text, `package.json` and lockfile names, and the PolyForm license
  notice updated; git remote and clone URL now point at the philia repo.
- README rebuilt in the Phanes structure; `Changelog.md` created; GitHub
  description rewritten and topics added. Em dashes removed everywhere,
  including terminal system messages.
- The `collab/` server folder kept its name (it means collaborative mode,
  not collabterm).

### 2.2 v1.2: brute-force protection (server + login UI)

- `collab/server.js` gained a global auth gate in front of the WebSocket
  upgrade:
  - 5 second gap after every wrong attempt; at most one password evaluation
    per 5 seconds server-wide.
  - Lockout ladder: 5 attempts then 5 minutes, 3 attempts then 10 minutes,
    2 attempts then 30 minutes (three rounds), then 1 attempt per hour
    indefinitely. A correct login resets the ladder.
  - During a gap or lockout, attempts are rejected without evaluation, so a
    correct guess in that window buys nothing.
- Rejections are delivered as a `denied` WebSocket message (a bare 401 is
  invisible to browser JS) carrying reason, retry time, attempts left, and
  the pending lockout length.
- The login card renders it: live countdown text, a thin draining cooldown
  bar (amber for waits and warnings, red for lockouts), disabled Join button,
  a warning when 2 or fewer attempts remain, and automatic retry when the
  attempt was throttled without being evaluated.

### 2.3 v1.2: remaining checkup fixes

- Simple mode rewritten as `_simple.ps1` (launch-simple.bat is now a thin
  wrapper): kill-on-close job object, "philia live" indicator, loading
  screen, Enter-to-stop, and ttyd bound to 127.0.0.1 via `-i`.
- Node server binds 127.0.0.1 only; nothing is reachable from the LAN.
- `server.js` generates a random password when `SHARE_PASSWORD` is unset
  instead of falling back to "changeme".
- `_philia.ps1` checks for Node.js up front with a clear install message.
- Startup cleanup only kills ttyd/cloudflared started from this install's
  `tools\` folder.
- Web terminal scales its font down on narrow windows (all 120 columns stay
  visible) and stacks the chat below the terminal under 700 px.

---

## 3. Decisions taken

| Theme | Decision | Rationale |
|---|---|---|
| Lockout scope | Global state, not per IP | One shared password; per-IP limits are trivially dodged from a botnet, and cloudflared hides origin IPs anyway |
| Lockout semantics | Reject without evaluating during gap/lockout | If correct guesses were still evaluated, the limiter would not actually cap the guess rate |
| 5 second gap arming | Armed by failed attempts only | Same throttle for attackers, but two friends joining in quick succession with the right password are not delayed |
| Throttled attempts | Client auto-retries them | The attempt was never evaluated, so retrying the same credentials is safe and makes the gap nearly invisible to legitimate users |
| Password format | Kept `Word-Word-1234` | Operator decision: with the ladder in place (roughly 1 guess per hour at steady state against 900k combinations), longer passwords buy nothing but typing pain |
| Simple mode | Full `_simple.ps1` port of the collab supervisor | Closes the biggest gap from the checkup: a force-closed window can no longer leave a public tunnel running |

---

## 4. Verification

- `node --check` on `server.js`; PowerShell parser clean on all four scripts.
- Live end-to-end WS harness against a test server: warning countdown 4, 3,
  2, 1 attempts left; 5th wrong attempt returns a 300 s lockout; immediate
  retries and correct-password attempts inside the gap return `throttle`;
  correct password after the gap logs in and resets the ladder; correct
  password during lockout is rejected.
- Verified the server listens on 127.0.0.1 only, and that ttyd accepts
  `-i 127.0.0.1` (checked with a live bind).
- Browser pass on the real login card: red "Wrong password. Next attempt in
  5s." with draining bar and disabled button, amber "2 attempts left before
  a 5 minute lockout" warning tier, settled post-cooldown text, then a
  successful join into the shared terminal with the font auto-fit active.

## 5. Code surface

| File | Change |
|---|---|
| `collab/server.js` | Auth gate (ladder + gap), `denied` messages, random fallback password, loopback bind |
| `collab/public/index.html` | Countdown UI + cooldown bar, denied handling, auto-retry, font auto-fit, narrow-screen layout |
| `_philia.ps1` | Node.js pre-check, scoped cloudflared cleanup |
| `_simple.ps1` | New full launcher (job object, indicator, loading screen, loopback ttyd) |
| `launch-simple.bat` | Reduced to a thin wrapper |
| `README.md`, `Changelog.md`, `collab/package.json` | v1.2 docs and version |

---

## 6. Open carryovers

- Simple mode's ttyd basic auth still has no brute-force limiter (documented
  honestly in the README). Fixing it would mean proxying ttyd or dropping
  ttyd for the Node server; only worth it if simple mode sees real use.
- The lockout state lives in server memory, so restarting the session resets
  the ladder. Acceptable for session-length tunnels; persisting it to disk
  would survive restarts if that ever matters.
- Possible future polish: a host-visible counter of failed attempts in the
  chat sidebar, so the host notices someone probing the link.

## 7. Next session pickup

Nothing blocked. The repository is pushed, v1.2 is live on the main branch,
and both launch paths were exercised this session. If a next step is wanted,
the highest-value one is a real two-machine session over the tunnel to
confirm the reconnect and lockout interplay end to end.
