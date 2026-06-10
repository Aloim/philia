# collabterm

**Share a Windows terminal over the web for collaborative or remote vibecoding sessions.**

collabterm turns a terminal on your Windows PC into a password-protected web app that
anyone can open in a browser — they install nothing. It's built for **collaborative or
remote AI-coding ("vibecoding") sessions**: you and a teammate (or just you, from another
machine) drive a coding agent like **Claude Code**, Codex, Aider — or plain PowerShell —
together in a shared terminal, with a live chat right next to it.

Under the hood it exposes a local terminal through a temporary [Cloudflare] tunnel, so the
public link works from anywhere while the shell — and your AI agent — keeps running on
your own PC.

## What it's for

- **Pair / mob vibecoding** — several people watch and control the same Claude Code (or
  other agent) terminal at once, talking it through in the side chat.
- **Remote access to your own setup** — hop onto your home PC's terminal and agent from a
  laptop, phone, or another machine, through any browser.
- **Quick demos / handoffs** — send someone a link and a password and let them take the
  wheel for a few minutes, then close the window to cut them off.

It's Windows-first: the terminal it shares is PowerShell by default, so your agent runs in
your real Windows environment with your files and tools.

## Two modes

| Script | What it does |
|--------|--------------|
| `share-claude.bat` | A single web terminal (via [ttyd]) opened in your project folder. Good for a quick 1:1 share. |
| `share-collab.bat` | A multi-user collaborative terminal **with tabs and a chat sidebar** (small Node server in `collab/`). Everyone sees and controls the same terminals — best for group vibecoding. |

## ⚠️ Security — read this first

The link grants **full control of a shell on your PC** to anyone who has it plus the
password — including everything that shell can reach (your files, and any tool you're
logged into: Claude Code, Gmail, Drive, Stripe, etc.). Treat the link + password like a
remote-desktop password:

- Only share with people you trust, over a private channel.
- A fresh random password is generated each run and printed in the window.
- Closing the window immediately tears down the tunnel and terminals.
- The tunnel URL is public; the password is the only thing protecting it.

## Requirements

- Windows 10/11 with PowerShell.
- Collaborative mode (`share-collab.bat`) also needs [Node.js] on your `PATH`.
- `ttyd` and `cloudflared` are downloaded automatically on first run into `tools/`.

## Setup & usage

1. Clone or download this repo:
   ```bash
   git clone https://github.com/Aloim/collabterm.git
   ```
2. Drop the scripts into the folder you want to share (or run them in place to share the
   collabterm folder itself).
3. Run one of the launchers:

   ```bat
   share-claude.bat                  :: shares this script's folder
   share-claude.bat "C:\some\path"   :: shares a different folder
   ```

   ```bat
   share-collab.bat
   share-collab.bat -Project "C:\some\path"
   ```

The window prints a `https://<random>.trycloudflare.com` link and a password. Send both to
your collaborators and keep the window open — closing it stops the session.

### Pin a fixed password (optional)

Set `SHARE_PASSWORD` before launching to reuse the same password instead of a random one:

```powershell
$env:SHARE_PASSWORD = 'My-Long-Shared-Secret'; .\share-collab.bat
```

## How it works

- `cloudflared tunnel --url` creates a temporary public URL pointing at a local port.
- `ttyd` (single mode) or the Node server in `collab/` (collab mode) serves the terminal
  over that port.
- Authentication is a shared password — `-c user:pass` for ttyd, `?key=` on the WebSocket
  for the collaborative server.

Nothing is hard-coded to a specific machine: the shared folder defaults to wherever the
scripts live, and the password is generated per run.

[ttyd]: https://github.com/tsl0922/ttyd
[Cloudflare]: https://github.com/cloudflare/cloudflared
[Node.js]: https://nodejs.org
