# Idea 2 — Retire `dot`; manage all of `~/.bashrc.d/` via the bare-repo dotfile manager

Date: 2026-06-16
Status: design (pending user review)

Supersedes idea-1: if we fully retire `dot`, fixing `dot`'s path assumptions
(idea-1) becomes moot.

## Goal

Collapse the bashrc-snippet ecosystem from "many git repos + a `dot`
package-manager" down to **one bare git repo** (the existing
`homedirdotfiles`, driven by the `config` alias from `dot-home/config`) that
tracks all of `~/.bashrc.d/*` as flat, plain files. The distro's native
`.bashrc.d` loop does the sourcing. The single repo is intended to be
**public/shareable**, so secrets are extracted into an untracked store.

## Decisions

- **Direction:** fully retire `dot`. (chosen)
- **Sharing:** share almost everything via the one public repo; keep secrets
  out via untracked files referenced with the `$(cat ~/.secret)` trick. (chosen)
- **Secret store:** read secrets from **KeePassXC** through a backend-agnostic
  `secret()` wrapper — layered `keepassxc-proxy` → `keepassxc-cli` →
  `~/.secrets/` plaintext fallback. (chosen)
- **History:** audit existing git history for committed secrets before
  publishing; scrub or restart history if any are found. (chosen)
- **jumpmarks:** replace `dot-jumpmarks` with `zoxide`. (chosen)

## End-state architecture

- `~/.bashrc.d/` is a **flat directory of plain snippet files** — no subdirs,
  no per-snippet `.git`. The distro `.bashrc.d` loop sources them all.
- **One bare repo** at `$HOME/.homedirgit` (`homedirdotfiles`) tracks
  `~/.bashrc.d/*` and other `$HOME` dotfiles via the `config` alias. Public.
- **Secrets live outside the repo**, untracked, referenced indirectly, so the
  repo is safe to publish.

## Secret handling — KeePassXC-backed `secret()` wrapper

Secrets are stored as entries in the user's existing **KeePassXC** database
(encrypted at rest). Snippets never hold secret values; they call a single
backend-agnostic shell function:

```bash
export OPENAI_API_KEY=$(secret openai)
```

`secret <name> [attr]` retrieves a value, trying backends in order and
**memoizing per session** (cache the retrieved value in an in-memory
associative array — never the master password) so KeePassXC prompts/confirms at
most once per shell:

1. **keepassxc-proxy** — talk to the already-unlocked running KeePassXC GUI over
   its encrypted browser socket (present on this machine) via a proxy helper
   (candidate: `git-credential-keepassxc`). No DB password in the shell;
   KeePassXC shows a per-access confirmation. Used when a desktop session and
   the socket are present.
2. **keepassxc-cli** — `keepassxc-cli show -s -a Password $KPXC_DB <entry>`
   against the `.kdbx`. Works headless/over SSH. Unlock once per session
   (prompt, keyfile, or quick-unlock).
3. **`~/.secrets/<name>`** — plaintext fallback only when KeePassXC is
   unavailable. `chmod 700` dir / `chmod 600` files, gitignored, with a
   perms-guard that refuses to load if group/world-accessible.

### Why this layering (security rationale)

- A bare `$(cat ~/.secrets/x)` exported into a variable is inherited by every
  child process, readable via `/proc/<pid>/environ` by the same user, and can
  leak into crash dumps. KeePassXC keeps secrets encrypted at rest and (proxy
  path) gates each access behind the unlocked GUI with confirmation.
- The clean `secret-tool` (Secret Service) route is **blocked on this box**:
  it's GNOME and `gnome-keyring` already owns `org.freedesktop.secrets`, so
  KeePassXC cannot cleanly provide the Secret Service. Hence proxy + cli.
- **Principles:** never commit secrets; never pass them as CLI args; export only
  what a tool genuinely needs; prefer just-in-time retrieval; cache the value,
  not the master password; keep history clean (audit before publish).

### Optional: per-command injection

For tools that only need a secret for one invocation, a wrapper scopes it to a
single process instead of the shell environment:

```bash
withsecret OPENAI_API_KEY=openai -- somecmd   # exports only for `somecmd`
```

This is tighter than a global `export` and complements the memoized `secret()`.

### Considered and rejected: gnome-keyring seeding

gnome-keyring is the live Secret Service provider on this box, so "unlock
KeePassXC once, seed gnome-keyring for the session" was evaluated. Rejected
because the secrets' only consumers are **shell/CLI**, for which the in-shell
memo already provides the "unlock once per session" benefit with zero extra
dependencies and no second on-disk store. Notes for the record:

- `secret-tool store` cannot target the memory-only **session** keyring (no
  `--collection` flag); it only writes the persistent **login** keyring, which
  would leave decrypted copies on disk outside KeePassXC.
- Ephemeral session-keyring seeding would need the Secret Service D-Bus API
  (`python3-secretstorage`, not installed) — extra dependency and code for a
  benefit only non-shell, Secret-Service-aware consumers would see.

Revisit only if a GUI/Secret-Service app later needs these values.

## Repo collapse — keep / drop / replace

Delete outright (functionality gone or replaced by a tool):

- `dot` — the package-manager tooling; replaced by `git` + the distro loop.
- `dot-powerline` — replaced by `starship` (already a loose file).
- `dot-jumpmarks` — replaced by `zoxide`.

Flatten to plain top-level files (keep functionality, drop the repo wrapper):

- `dot-home/config`   → `~/.bashrc.d/homedir-git` (defines the `config` alias;
  self-bootstraps because the loop sources it).
- `dot-ssh/agentinit` → de-duped with the existing loose `ssh-agent` file
  (likely overlapping ssh-agent startup; keep one).

Add:

- `~/.bashrc.d/zoxide` → `eval "$(zoxide init bash)"`; optionally
  `alias jj=z` / `alias jump=z` for muscle memory. New dependency: `zoxide`.

Keep as-is (loose files already in the modern layout):

- atuin, starship, nvm, cargo-bin, kbs, marktext, nerdfonts, plus the
  remaining personal snippets — after secret extraction.

## Migration outline

1. **Inventory & audit** every file (especially the `0600`-mode ones:
   `openai`, `pypirc`, `mvd`, `one-liners`, `arduino`, `defaulteditor`,
   `nerdfonts`, `pretty-csv`) → classify keep / drop / contains-secret.
   (Do not print secret values into logs/transcripts.)
2. **Extract secrets** → store each as a **KeePassXC** entry; rewrite the owning
   snippets to `$(secret <name>)`. Add the `secret()` wrapper snippet (proxy →
   cli → `~/.secrets/` fallback) and install/configure the proxy helper.
3. **Flatten** the dot-* subdirs into top-level files; delete `dot`,
   `dot-powerline`, `dot-jumpmarks`; add the `zoxide` snippet.
4. **Remove** the per-repo `.git` directories.
5. **History audit:** scan `homedirdotfiles` (and any folded-in histories) for
   previously committed secrets; scrub (`git filter-repo`/BFG) or start a
   fresh single-commit history before publishing.
6. `config add` the snippets, commit, push.
7. Add `~/.secrets/` and `$HOME/.homedirgit` to `.gitignore`.
8. **Verify** a fresh shell sources everything via the distro loop — no `dot`
   references, no errors, prompt/tools intact.

## Risks

- **History contamination:** extracting a secret now does not remove it from
  past commits; publishing would expose it. Step 5 is mandatory before going
  public.
- **Env-var exposure:** eagerly exported secrets are visible to all child
  processes; prefer just-in-time retrieval and memoize the value, not the
  master password.
- **Proxy-helper capability:** confirm during planning that the chosen proxy
  helper (`git-credential-keepassxc`) can fetch **arbitrary named entries**, not
  just URL-keyed git credentials; if not, demote proxy and make `keepassxc-cli`
  the primary backend. The helper isn't in Fedora repos (cargo/release install).
- **Headless sessions:** with no GUI, `secret()` falls through to
  `keepassxc-cli`, which needs an unlock per session (keyfile/quick-unlock to
  smooth this).
- **New dependency:** `zoxide` must be installed on every machine; document it.
- **`config status.showUntrackedFiles no`** means new snippets must be added
  explicitly with `config add`.
- **Loss of per-snippet repos:** sharing now happens at the whole-repo level
  rather than per snippet. Accepted.
