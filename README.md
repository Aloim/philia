# collabterm

**Share a Windows terminal over the web for collaborative or remote vibecoding sessions.**

collabterm turns a terminal on your Windows PC into a password-protected web app that
anyone can open in a browser, with nothing to install on their side. It's built for
**collaborative or remote AI-coding ("vibecoding") sessions**: you and a teammate (or just
you, from another machine) drive a coding agent like **Claude Code**, Codex, Aider, or
plain PowerShell together in a shared terminal, with a live chat right next to it.

Under the hood it exposes a local terminal through a temporary [Cloudflare] tunnel, so the
public link works from anywhere while the shell (and your AI agent) keeps running on your
own PC.

## What it's for

- **Pair or mob vibecoding:** several people watch and control the same Claude Code (or
  other agent) terminal at once, talking it through in the side chat.
- **Remote access to your own setup:** hop onto your home PC's terminal and agent from a
  laptop, phone, or another machine, through any browser.
- **Quick demos or handoffs:** send someone a link and a password and let them take the
  wheel for a few minutes, then close the window to cut them off.

It's Windows-first: the terminal it shares is PowerShell by default, so your agent runs in
your real Windows environment with your files and tools.

## Two modes

| Script | What it does |
|--------|--------------|
| **`launch-collabterm.bat`** | **The main launcher.** A multi-user collaborative terminal with tabs and a chat sidebar (small Node server in `collab/`). Everyone sees and controls the same terminals, which is best for group vibecoding. This is the one to run if you're not sure. |
| `launch-simple.bat` | A simpler single web terminal (via [ttyd]) opened in your project folder. Good for a quick 1:1 share. |

## Security: read this first

The link grants **full control of a shell on your PC** to anyone who has it plus the
password. That includes your files and anything your signed-in tools and accounts can
reach. Treat the link and password like a remote-desktop password:

- Only share with people you trust, over a private channel.
- A fresh random password is generated each run and printed in the window.
- A host-only **Stop session** button (and pressing Enter, or closing the window) instantly
  tears down every collabterm process: terminals, the Node server, and the public tunnel.
- All the pieces are linked, so if any one stops the rest stop too - a forgotten or
  force-closed window can't leave a tunnel publicly reachable in the background.
- A topmost "collabterm live" indicator stays on the host's screen for the whole session,
  so an open session is hard to forget about.
- The tunnel URL is public, so the password is the only thing protecting it.

## Requirements

- Windows 10/11 with PowerShell.
- Collaborative mode (`launch-collabterm.bat`) also needs [Node.js] on your `PATH`.
- `ttyd` and `cloudflared` are downloaded automatically on first run into `tools/`.
- Recommended: [Windows Terminal] as your host-side terminal for launching and watching
  sessions.

## Setup and usage

1. Clone or download this repo:
   ```bash
   git clone https://github.com/Aloim/collabterm.git
   ```
2. Drop the scripts into the folder you want to share, or run them in place to share the
   collabterm folder itself.
3. Run a launcher. For the collaborative terminal (the usual choice):

   ```bat
   launch-collabterm.bat
   launch-collabterm.bat -Project "C:\some\path"   :: shares a different folder
   ```

   Or, for the simpler single-user terminal:

   ```bat
   launch-simple.bat                  :: shares this script's folder
   launch-simple.bat "C:\some\path"   :: shares a different folder
   ```

The window prints a `https://<random>.trycloudflare.com` link and a password. Send both to
your collaborators and keep the window open.

The host window also prints a **host-only `http://localhost:...?admin=...` URL**. Open that
on the host PC to join with a red **Stop session** button that kills the whole session
(every shared terminal plus the public link) for everyone. That admin link is shown only in
the host window and must not be shared. Stopping the session any way - the button, pressing
Enter, or just closing the host window - tears down every collabterm process together, so a
forgotten window can't leave a tunnel publicly reachable.

While a session is live, a small always-on-top **red dot labelled "collabterm live"** sits in
the top-right corner of the host's screen. It stays visible even when every window is
minimized, so you can't lose track of an open, accessible session, and it disappears the
moment the session stops.

### Pin a fixed password (optional)

Set `SHARE_PASSWORD` before launching to reuse the same password instead of a random one:

```powershell
$env:SHARE_PASSWORD = 'My-Long-Shared-Secret'; .\launch-collabterm.bat
```

## Tailoring it to your agent

Out of the box collabterm is set up around **Claude Code** as the agent you share, but
nothing is locked to it. Each shared tab is just a shell (PowerShell by default), so you can
run **any** CLI agent or tool in it - Codex, Aider, a REPL, plain PowerShell, whatever - by
typing its command in the tab once you're connected.

To change the default more permanently, edit `collab/server.js`: the `SHELL` / `SHELL_ARGS`
values (driven by the `SHARE_SHELL` env var) decide what each new tab launches. Point that at
a different shell, or have it start your agent directly, and every tab opens straight into
your setup. The collaboration, chat, tabs, auth, and shutdown logic are all agent-agnostic.

## How it works

- `cloudflared tunnel --url` creates a temporary public URL pointing at a local port.
- `ttyd` (single mode) or the Node server in `collab/` (collab mode) serves the terminal
  over that port.
- Authentication is a shared password: `-c user:pass` for ttyd, `?key=` on the WebSocket
  for the collaborative server.

Nothing is hard-coded to a specific machine: the shared folder defaults to wherever the
scripts live, and the password is generated per run.

## License

Licensed under the [PolyForm Noncommercial License 1.0.0](LICENSE.md). You're free to use,
copy, modify, and share it for any **noncommercial** purpose - personal projects, hobby and
amateur use, research, education, and nonprofit or government use. **Commercial use is not
permitted** under this license. If you need a commercial license, open an issue to ask.

[ttyd]: https://github.com/tsl0922/ttyd
[Cloudflare]: https://github.com/cloudflare/cloudflared
[Node.js]: https://nodejs.org
[Windows Terminal]: https://aka.ms/terminal
