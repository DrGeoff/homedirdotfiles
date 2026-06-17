# Retire `dot` & Consolidate `~/.bashrc.d/` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `dot` snippet package-manager with a single publishable bare-repo dotfile setup: all of `~/.bashrc.d/` becomes flat plain files sourced by the distro loop, secrets are read from KeePassXC via a `secret()` wrapper, and `dot`/`dot-powerline`/`dot-jumpmarks` are removed.

**Architecture:** Each snippet is a flat file in `~/.bashrc.d/` sourced by the distro's native `~/.bashrc.d/*` loop. The existing `homedirdotfiles` bare repo (driven by the `config` git alias) tracks them. Secrets live in KeePassXC, fetched lazily and memoized per shell by a backend-agnostic `secret()` function (`keepassxc-cli` + `~/.secrets/` plaintext fallback first; `keepassxc-proxy` added later as a gated enhancement). `zoxide` replaces jumpmarks; `starship` already replaces powerline.

**Tech Stack:** bash, git (bare-repo dotfile technique), KeePassXC (`keepassxc-cli`, optionally `keepassxc-proxy` + `git-credential-keepassxc`), zoxide, gitleaks (audit).

**Spec:** `docs/idea-2.md`

**Safety rules for the executor:**
- NEVER `cat`/`echo` a secret value into the terminal or a commit. Inventory greps use `-l` (filenames only).
- NEVER `config add` a snippet until it is confirmed secret-free.
- Keep the Task 1 backup until the final verification passes.
- This is not run in a worktree; changes touch `$HOME` directly.

---

### Task 1: Safety backup and preserve planning docs

**Files:**
- Create: `~/dot-migration-backup-2026-06-17.tar.gz`
- Create: `~/dotfiles-docs/` (relocated planning docs)
- Read: `~/.bashrc.d/` (entire tree)

- [ ] **Step 1: Back up the whole `~/.bashrc.d/` tree**

```bash
tar czf ~/dot-migration-backup-2026-06-17.tar.gz -C "$HOME" .bashrc.d
ls -lh ~/dot-migration-backup-2026-06-17.tar.gz
```
Expected: a non-empty `.tar.gz` is listed.

- [ ] **Step 2: Verify the backup is readable and complete**

```bash
tar tzf ~/dot-migration-backup-2026-06-17.tar.gz | grep -c . 
tar tzf ~/dot-migration-backup-2026-06-17.tar.gz | grep -E 'bashrc.d/(dot|atuin|starship)' 
```
Expected: a file count > 0, and the grep shows `dot`, `atuin`, `starship` entries.

- [ ] **Step 3: Record the current homedirdotfiles repo state**

```bash
source ~/.bashrc.d/dot-home/config    # defines the `config` alias
config log --oneline -5 2>/dev/null || echo "homedirdotfiles repo not yet initialised"
config status 2>/dev/null | head
```
Expected: either recent commits, or the "not yet initialised" message. Note which it is — Task 15 branches on it.

- [ ] **Step 4: Preserve the planning docs outside the `dot` repo (it gets deleted in Task 12)**

```bash
mkdir -p ~/dotfiles-docs
cp -a ~/.bashrc.d/dot/docs/. ~/dotfiles-docs/
ls ~/dotfiles-docs
```
Expected: `idea-2.md` and `superpowers/plans/2026-06-17-retire-dot-consolidate-bashrc-d.md` are present under `~/dotfiles-docs/`.

- [ ] **Step 5: Commit the relocated docs into the homedir repo**

```bash
config add ~/dotfiles-docs
config commit -m "docs: preserve dot-retirement spec and plan before migration"
```
Expected: a commit is created. (If the repo is not yet initialised, skip — Task 15 will init and add it.)

---

### Task 2: Create the `secret()` snippet (cli + plaintext tiers)

**Files:**
- Create: `~/.bashrc.d/secret`
- Test: ad-hoc subshell sourcing + a throwaway `~/.secrets/_dottest`

- [ ] **Step 1: Write the `secret` snippet**

Create `~/.bashrc.d/secret` with exactly:

```bash
# secret — backend-agnostic secret retrieval for shell/CLI use.
#
#   secret <name> [attribute]   # print a secret value (memoised per shell)
#   withsecret VAR=name [..] -- cmd args    # (defined in ~/.bashrc.d/withsecret)
#
# Backends tried in order: keepassxc-cli -> ~/.secrets/<name> plaintext.
# (A keepassxc-proxy tier is added in Task 4.)
#
# Values are cached per shell in __SECRET_CACHE. The KeePassXC master password
# is never cached; with the cli backend you are prompted once per distinct
# secret per shell.

: "${KPXC_DB:=$HOME/.bashrc.d/.keepass-db-path-not-set}"
: "${SECRETS_DIR:=$HOME/.secrets}"

declare -A __SECRET_CACHE 2>/dev/null

_secret_check_perms() {
    # Refuse to read ~/.secrets unless it is 700 (owner-only).
    local mode
    mode="$(stat -c '%a' "$SECRETS_DIR" 2>/dev/null)" || return 0
    if [[ "$mode" == "700" ]]; then
        return 0
    fi
    echo "secret: $SECRETS_DIR has unsafe perms ($mode); want 700" >&2
    return 1
}

_secret_cli() {
    # $1=entry name, $2=attribute. Prompts for the DB password on the tty.
    keepassxc-cli show -q -s -a "$2" "$KPXC_DB" "$1"
}

secret() {
    local name="$1" attr="${2:-Password}"
    if [[ -z "$name" ]]; then
        echo "usage: secret <name> [attribute]" >&2
        return 2
    fi

    local key="${name}/${attr}"
    if [[ -n "${__SECRET_CACHE[$key]+set}" ]]; then
        printf '%s' "${__SECRET_CACHE[$key]}"
        return 0
    fi

    local value=""

    # 1) keepassxc-cli against the .kdbx
    if [[ -z "$value" ]] && command -v keepassxc-cli >/dev/null 2>&1 && [[ -r "$KPXC_DB" ]]; then
        value="$(_secret_cli "$name" "$attr")"
    fi

    # 2) plaintext fallback
    if [[ -z "$value" ]] && [[ -r "$SECRETS_DIR/$name" ]]; then
        _secret_check_perms || return 1
        value="$(<"$SECRETS_DIR/$name")"
    fi

    if [[ -z "$value" ]]; then
        echo "secret: could not retrieve '$name'" >&2
        return 1
    fi

    __SECRET_CACHE[$key]="$value"
    printf '%s' "$value"
}
```

- [ ] **Step 2: Syntax-check and verify the function loads**

```bash
bash -n ~/.bashrc.d/secret && echo "SYNTAX OK"
bash -c 'source ~/.bashrc.d/secret; declare -F secret >/dev/null && echo "FUNC OK"'
```
Expected: `SYNTAX OK` then `FUNC OK`.

- [ ] **Step 3: Functional test against the plaintext fallback**

```bash
mkdir -p ~/.secrets && chmod 700 ~/.secrets
printf 'hunter2' > ~/.secrets/_dottest && chmod 600 ~/.secrets/_dottest
bash -c 'source ~/.bashrc.d/secret; [[ "$(secret _dottest)" == "hunter2" ]] && echo "PLAINTEXT OK"'
```
Expected: `PLAINTEXT OK`.

- [ ] **Step 4: Verify the perms-guard refuses an unsafe directory**

```bash
chmod 755 ~/.secrets
bash -c 'source ~/.bashrc.d/secret; secret _dottest >/dev/null 2>&1 || echo "GUARD OK"'
chmod 700 ~/.secrets
```
Expected: `GUARD OK`.

- [ ] **Step 5: Clean up the test secret and commit the snippet**

```bash
rm -f ~/.secrets/_dottest
config add ~/.bashrc.d/secret
config commit -m "feat: add secret() retrieval wrapper (keepassxc-cli + plaintext)"
```
Expected: a commit is created. (If repo not yet initialised, defer the add to Task 15 and just `git diff`-review the file now.)

---

### Task 3: Point `secret()` at the real KeePassXC database and test end-to-end

**Files:**
- Create: `~/.bashrc.d/keepass-env` (sets `KPXC_DB`)

- [ ] **Step 1: Find the user's KeePassXC database path**

```bash
find "$HOME" -maxdepth 4 -iname '*.kdbx' 2>/dev/null
```
Expected: one or more `.kdbx` paths. Pick the canonical one (ask the user if ambiguous). Call it `<KDBX_PATH>` below.

- [ ] **Step 2: Write the `keepass-env` snippet**

Create `~/.bashrc.d/keepass-env` with (substituting the real path):

```bash
# Location of the canonical KeePassXC database used by secret().
export KPXC_DB="<KDBX_PATH>"
```

- [ ] **Step 3: Create a throwaway entry to test cli retrieval**

Tell the user to add, in the KeePassXC GUI, an entry titled `_dottest` with Password `hunter2`, then save the database. (Or, if they prefer CLI, they run it themselves — it prompts for the DB password:)

```bash
keepassxc-cli add -p "$KPXC_DB" _dottest    # interactive; sets the password
```

- [ ] **Step 4: Verify cli retrieval works end-to-end**

```bash
bash -c 'source ~/.bashrc.d/keepass-env; source ~/.bashrc.d/secret; secret _dottest' 
echo    # newline
```
Expected: prints `hunter2` (after one interactive DB-password prompt). If it errors, confirm the entry title and `KPXC_DB`.

- [ ] **Step 5: Remove the throwaway entry and commit**

```bash
keepassxc-cli rm "$KPXC_DB" _dottest    # interactive
config add ~/.bashrc.d/keepass-env
config commit -m "feat: configure KPXC_DB for secret() cli backend"
```
Expected: entry removed; commit created. Note: `keepass-env` contains only a path, not a secret — safe to commit.

---

### Task 4: Add the keepassxc-proxy tier (gated on capability test)

**Files:**
- Modify: `~/.bashrc.d/secret`

- [ ] **Step 1: Install the proxy helper**

```bash
cargo install git-credential-keepassxc 2>&1 | tail -5 || \
  echo "cargo unavailable — download a release binary into ~/.local/bin instead"
command -v git-credential-keepassxc && echo "HELPER OK"
```
Expected: `HELPER OK` with a path. If it cannot be installed, SKIP this entire task — `secret()` keeps working on cli; record "proxy tier skipped" and move on.

- [ ] **Step 2: Associate the helper with the running KeePassXC and capability-test it**

```bash
git-credential-keepassxc configure 2>&1 | tail -20    # KeePassXC will prompt to allow access
# Capability test: can it return a value for a named entry? Create a temp entry
# `_dottest`/`hunter2` in the GUI first, then:
git-credential-keepassxc --unlock 3 get <<<'url=kpxc://_dottest' 2>&1 | sed -n '1,10p'
```
Expected: the helper returns a `password=...` line for the entry. **If it cannot fetch arbitrary named entries** (only URL-keyed git creds), STOP this task — proxy stays disabled, cli remains primary. Record the outcome in `~/dotfiles-docs/idea-2.md` risks section.

- [ ] **Step 3: Add the proxy tier to `secret()`**

In `~/.bashrc.d/secret`, add this helper above `_secret_cli`:

```bash
_secret_proxy() {
    # $1=entry name, $2=attribute (Password only, via proxy).
    [[ "$2" != "Password" ]] && return 1
    git-credential-keepassxc get <<<"url=kpxc://$1" 2>/dev/null \
        | sed -n 's/^password=//p'
}
```

And insert this block in `secret()` immediately before the `# 1) keepassxc-cli` block:

```bash
    # 0) keepassxc-proxy (running, unlocked GUI)
    local _sock="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/org.keepassxc.KeePassXC.BrowserServer"
    if [[ -z "$value" ]] && command -v git-credential-keepassxc >/dev/null 2>&1 \
        && { [[ -S "$_sock" ]] || [[ -L "$_sock" ]]; }; then
        value="$(_secret_proxy "$name" "$attr")"
    fi
```

- [ ] **Step 4: Syntax-check and verify proxy retrieval is preferred**

```bash
bash -n ~/.bashrc.d/secret && echo "SYNTAX OK"
bash -c 'source ~/.bashrc.d/keepass-env; source ~/.bashrc.d/secret; secret _dottest'
```
Expected: `SYNTAX OK`, then `hunter2` printed **without** a DB-password prompt (proxy used). Remove the `_dottest` entry afterwards.

- [ ] **Step 5: Commit**

```bash
config add ~/.bashrc.d/secret
config commit -m "feat: add keepassxc-proxy tier to secret()"
```
Expected: commit created.

---

### Task 5: Add the `withsecret` per-command wrapper

**Files:**
- Create: `~/.bashrc.d/withsecret`

- [ ] **Step 1: Write the wrapper**

Create `~/.bashrc.d/withsecret`:

```bash
# withsecret VAR=name [VAR2=name2 ...] -- cmd args...
# Run `cmd` with the named secrets exported only into that one process.
withsecret() {
    local -a assigns=() envv=()
    while [[ $# -gt 0 && "$1" != "--" ]]; do assigns+=("$1"); shift; done
    [[ "$1" == "--" ]] && shift
    if [[ $# -eq 0 ]]; then
        echo "usage: withsecret VAR=name [...] -- cmd args" >&2
        return 2
    fi
    local a var name val
    for a in "${assigns[@]}"; do
        var="${a%%=*}"; name="${a#*=}"
        val="$(secret "$name")" || return 1
        envv+=("$var=$val")
    done
    env "${envv[@]}" "$@"
}
```

- [ ] **Step 2: Syntax-check and functional test**

```bash
bash -n ~/.bashrc.d/withsecret && echo "SYNTAX OK"
mkdir -p ~/.secrets && chmod 700 ~/.secrets
printf 'zzz' > ~/.secrets/_dottest && chmod 600 ~/.secrets/_dottest
bash -c 'source ~/.bashrc.d/secret; source ~/.bashrc.d/withsecret;
         withsecret FOO=_dottest -- bash -c "[[ \$FOO == zzz ]] && echo WITHSECRET OK"'
rm -f ~/.secrets/_dottest
```
Expected: `SYNTAX OK` then `WITHSECRET OK`.

- [ ] **Step 3: Commit**

```bash
config add ~/.bashrc.d/withsecret
config commit -m "feat: add withsecret per-command injection wrapper"
```
Expected: commit created.

---

### Task 6: Inventory and classify every snippet (no value leakage)

**Files:**
- Create: `~/dotfiles-docs/inventory.md` (worksheet)

- [ ] **Step 1: List every snippet file (top-level + inside dot-* subdirs)**

```bash
find ~/.bashrc.d -type f -not -path '*/.git/*' | sort
```
Expected: the full file list. Record each in the worksheet.

- [ ] **Step 2: Flag files that likely contain secrets (filenames only — no values printed)**

```bash
grep -rIlE 'API|TOKEN|SECRET|PASSWORD|PASSWD|KEY|Bearer|[A-Za-z0-9_-]{32,}' \
    ~/.bashrc.d --exclude-dir=.git
```
Expected: a list of filenames. `-l` prints filenames only, never the matching line. Pay special attention to the `0600`-mode files: `openai`, `pypirc`, `mvd`, `one-liners`, `arduino`, `defaulteditor`, `nerdfonts`, `pretty-csv`.

- [ ] **Step 3: Write the classification worksheet**

Create `~/dotfiles-docs/inventory.md` with a table: one row per file, columns `file | action (keep/drop/secret) | notes`. Pre-fill the known decisions:
- `dot/*`, `dot-powerline/*` → drop; `dot-jumpmarks/*` → drop (zoxide).
- `dot-home/config` → flatten to `homedir-git`; `dot-ssh/agentinit` → de-dupe with `ssh-agent`.
- each file flagged in Step 2 → `secret` (extract in Task 7).

- [ ] **Step 4: Commit the worksheet**

```bash
config add ~/dotfiles-docs/inventory.md
config commit -m "docs: bashrc.d migration inventory"
```
Expected: commit created.

---

### Task 7: Extract secrets into KeePassXC and rewrite snippets

**Files:**
- Modify: each `secret`-classified file from Task 6
- Create: KeePassXC entries (one per secret)

Repeat Steps 1–4 for EACH file classified `secret`. Example uses `openai`.

- [ ] **Step 1: Inspect the file in an editor (do not cat to the terminal)**

```bash
${EDITOR:-vi} ~/.bashrc.d/openai
```
Identify each hardcoded secret and the env var it feeds (e.g. `export OPENAI_API_KEY=sk-...`).

- [ ] **Step 2: Create a KeePassXC entry for the secret**

In the KeePassXC GUI, create an entry (e.g. title `openai`) with the secret as its Password, and save. (Keeps the value out of shell history.)

- [ ] **Step 3: Rewrite the snippet to use `secret()`**

Replace the hardcoded line, e.g.:

```bash
# before:  export OPENAI_API_KEY=sk-REDACTED
export OPENAI_API_KEY=$(secret openai)
```

- [ ] **Step 4: Verify no literal secret remains and the var still resolves**

```bash
grep -nE 'sk-|[A-Za-z0-9_-]{32,}' ~/.bashrc.d/openai || echo "NO LITERAL SECRET"
bash -c 'source ~/.bashrc.d/keepass-env; source ~/.bashrc.d/secret; source ~/.bashrc.d/openai;
         [[ -n "$OPENAI_API_KEY" ]] && echo "VAR RESOLVES"'
```
Expected: `NO LITERAL SECRET` and `VAR RESOLVES`.

- [ ] **Step 5: After ALL secret files are done, commit them together**

```bash
config add ~/.bashrc.d/openai ~/.bashrc.d/pypirc <...each rewritten file...>
config commit -m "refactor: read secrets from KeePassXC via secret()"
```
Expected: commit created. Do NOT add any file still containing a literal secret.

---

### Task 8: Replace jumpmarks with zoxide

**Files:**
- Create: `~/.bashrc.d/zoxide`
- Delete: `~/.bashrc.d/dot-jumpmarks/`

- [ ] **Step 1: Install zoxide**

```bash
command -v zoxide || sudo dnf install -y zoxide || cargo install zoxide
command -v zoxide && echo "ZOXIDE OK"
```
Expected: `ZOXIDE OK`.

- [ ] **Step 2: Write the zoxide snippet**

Create `~/.bashrc.d/zoxide`:

```bash
# zoxide — smarter cd; replaces the old jumpmarks jump/mark functions.
eval "$(zoxide init bash)"
# Muscle-memory aliases for the retired jumpmarks commands.
alias jj='z'
alias jump='z'
```

- [ ] **Step 3: Verify it loads and `z` is defined**

```bash
bash -n ~/.bashrc.d/zoxide && echo "SYNTAX OK"
bash -ic 'source ~/.bashrc.d/zoxide; declare -F __zoxide_z >/dev/null && echo "ZOXIDE FUNC OK"'
```
Expected: `SYNTAX OK` then `ZOXIDE FUNC OK`.

- [ ] **Step 4: Remove the jumpmarks repo**

```bash
rm -rf ~/.bashrc.d/dot-jumpmarks
ls ~/.bashrc.d/dot-jumpmarks 2>&1 || echo "JUMPMARKS GONE"
```
Expected: `JUMPMARKS GONE`.

- [ ] **Step 5: Commit**

```bash
config add ~/.bashrc.d/zoxide
config commit -m "feat: replace jumpmarks with zoxide"
```
Expected: commit created.

---

### Task 9: Flatten `dot-home/config` to a plain `homedir-git` snippet

**Files:**
- Create: `~/.bashrc.d/homedir-git`
- Delete: `~/.bashrc.d/dot-home/`

- [ ] **Step 1: Copy the config snippet to a flat top-level file**

```bash
cp ~/.bashrc.d/dot-home/config ~/.bashrc.d/homedir-git
```

- [ ] **Step 2: Verify the `config` alias is still defined when sourced flat**

```bash
bash -n ~/.bashrc.d/homedir-git && echo "SYNTAX OK"
bash -c 'source ~/.bashrc.d/homedir-git; alias config >/dev/null 2>&1 && echo "CONFIG ALIAS OK"'
```
Expected: `SYNTAX OK` then `CONFIG ALIAS OK`.

- [ ] **Step 3: Remove the dot-home repo (its `.git` is the bare-repo wrapper, NOT the homedirdotfiles bare repo at `~/.homedirgit`)**

```bash
# Sanity: confirm we are deleting the snippet repo, not the live bare repo.
test "$(readlink -f ~/.bashrc.d/dot-home)" != "$(readlink -f ~/.homedirgit)" && \
  rm -rf ~/.bashrc.d/dot-home && echo "DOT-HOME REPO REMOVED"
```
Expected: `DOT-HOME REPO REMOVED`.

- [ ] **Step 4: Commit**

```bash
config add ~/.bashrc.d/homedir-git
config commit -m "refactor: flatten dot-home/config to ~/.bashrc.d/homedir-git"
```
Expected: commit created.

---

### Task 10: De-duplicate ssh-agent startup, remove `dot-ssh`

**Files:**
- Modify/keep: `~/.bashrc.d/ssh-agent`
- Delete: `~/.bashrc.d/dot-ssh/`

- [ ] **Step 1: Diff the two ssh-agent sources**

```bash
diff <(cat ~/.bashrc.d/ssh-agent) <(cat ~/.bashrc.d/dot-ssh/agentinit) || true
```
Review the difference. Decide on ONE canonical agent-startup snippet (prefer the loose `~/.bashrc.d/ssh-agent`; fold in anything unique from `agentinit`).

- [ ] **Step 2: Ensure the canonical `~/.bashrc.d/ssh-agent` is complete, then syntax-check**

Edit `~/.bashrc.d/ssh-agent` so it is the single source of truth, then:

```bash
bash -n ~/.bashrc.d/ssh-agent && echo "SYNTAX OK"
```
Expected: `SYNTAX OK`.

- [ ] **Step 3: Remove the dot-ssh repo**

```bash
rm -rf ~/.bashrc.d/dot-ssh && echo "DOT-SSH REMOVED"
```
Expected: `DOT-SSH REMOVED`.

- [ ] **Step 4: Verify exactly one agent starts in a fresh login shell**

```bash
bash -lic 'pgrep -u "$USER" ssh-agent | wc -l'
```
Expected: `1` (not 2+). If higher, another snippet also starts an agent — reconcile before continuing.

- [ ] **Step 5: Commit**

```bash
config add ~/.bashrc.d/ssh-agent
config commit -m "refactor: single canonical ssh-agent snippet; drop dot-ssh"
```
Expected: commit created.

---

### Task 11: Remove `dot-powerline` (superseded by starship)

**Files:**
- Delete: `~/.bashrc.d/dot-powerline/`

- [ ] **Step 1: Confirm starship is active**

```bash
command -v starship && grep -q starship ~/.bashrc.d/starship && echo "STARSHIP ACTIVE"
```
Expected: `STARSHIP ACTIVE`.

- [ ] **Step 2: Remove the powerline repo**

```bash
rm -rf ~/.bashrc.d/dot-powerline && echo "POWERLINE REMOVED"
```
Expected: `POWERLINE REMOVED`.

- [ ] **Step 3: Verify the prompt still renders in a fresh shell**

```bash
bash -lic 'echo "prompt test: $?"' 2>&1 | tail -1
```
Expected: no powerline errors; a clean prompt line.

- [ ] **Step 4: Commit**

```bash
config commit -am "chore: remove dot-powerline (replaced by starship)" || \
  config commit -m "chore: remove dot-powerline (replaced by starship)"
```
Expected: commit created (deletion recorded).

---

### Task 12: Retire the `dot` tooling and clean bootstrap

**Files:**
- Delete: `~/.bashrc.d/dot/`
- Modify: `~/.bashrc` and/or any `~/.bashrc.d/*` loader symlink referencing dot (user-applied)

- [ ] **Step 1: Find anything that still references dot**

```bash
grep -RIn -e 'dot\.sh' -e 'dot-foreach' -e 'dot-update' -e 'dot-install' \
    ~/.bashrc ~/.bash_profile ~/.profile ~/.bashrc.d 2>/dev/null || echo "NO DOT REFERENCES"
```
Expected: ideally `NO DOT REFERENCES`. List every hit.

- [ ] **Step 2: Confirm the distro loop sources `~/.bashrc.d/*`**

```bash
grep -RIn 'bashrc.d' ~/.bashrc /etc/bashrc /etc/profile.d/*.sh 2>/dev/null
```
Expected: a loop like `for rc in ~/.bashrc.d/*; do ... . "$rc"; done`. If absent, have the user add this to `~/.bashrc`:

```bash
if [ -d ~/.bashrc.d ]; then
  for rc in ~/.bashrc.d/*; do
    [ -f "$rc" ] && . "$rc"
  done
  unset rc
fi
```

- [ ] **Step 3: Remove the dot bootstrap lines (user-applied edit)**

Have the user delete any `source .../dot/dot.sh`, `dot-foreach-config source`, or dot loader symlink found in Step 1 from `~/.bashrc`. (Skipped automatically — `.bashrc` edits are the user's call.)

- [ ] **Step 4: Remove the dot repo**

```bash
rm -rf ~/.bashrc.d/dot && echo "DOT REMOVED"
```
Expected: `DOT REMOVED`. (Planning docs were copied to `~/dotfiles-docs` in Task 1.)

- [ ] **Step 5: Verify a fresh login shell has no dot errors**

```bash
bash -lic 'type dot-foreach-config 2>/dev/null; echo "shell loaded rc=$?"' 2>&1 | tail -5
```
Expected: `dot-foreach-config` is NOT found, and the shell loads with no "command not found"/source errors.

- [ ] **Step 6: Commit**

```bash
config commit -am "chore: retire dot tooling; rely on distro loop" || \
  config commit -m "chore: retire dot tooling; rely on distro loop"
```
Expected: commit created.

---

### Task 13: Confirm flat layout — no stray per-snippet `.git` dirs

**Files:**
- Inspect: `~/.bashrc.d/`

- [ ] **Step 1: Ensure no nested git repos remain under `~/.bashrc.d/`**

```bash
find ~/.bashrc.d -name .git -maxdepth 3 2>/dev/null || echo "NO NESTED GIT"
find ~/.bashrc.d -mindepth 1 -maxdepth 1 -type d
```
Expected: `NO NESTED GIT` (no output from the first find), and the second lists only intentional dirs (ideally none). Any leftover dot-* dir is a miss — remove it.

- [ ] **Step 2: Verify the directory is now flat files only**

```bash
find ~/.bashrc.d -mindepth 1 -maxdepth 1 -type f | sort
```
Expected: the snippet files (atuin, secret, withsecret, zoxide, homedir-git, ssh-agent, starship, keepass-env, …) and no surviving dot-* repos.

---

### Task 14: Audit git history for previously-committed secrets

**Files:**
- Inspect: the `homedirdotfiles` history (`~/.homedirgit`)

- [ ] **Step 1: Install gitleaks (redacts values in output)**

```bash
command -v gitleaks || sudo dnf install -y gitleaks || \
  echo "install gitleaks from https://github.com/gitleaks/gitleaks/releases"
command -v gitleaks && echo "GITLEAKS OK"
```
Expected: `GITLEAKS OK`.

- [ ] **Step 2: Scan the full homedirdotfiles history**

```bash
gitleaks detect --source "$HOME" --git-dir "$HOME/.homedirgit" --redact -v 2>&1 | tail -30
```
Expected: `no leaks found`. If leaks ARE found, they are redacted in the report — do NOT publish yet; proceed to Step 3.

- [ ] **Step 3: If leaks found — scrub or restart history (decision point)**

Option A (scrub specific blobs), requires `git-filter-repo`:

```bash
# Replace each leaked file's history; back up first.
cp -a ~/.homedirgit ~/.homedirgit.bak-2026-06-17
git --git-dir="$HOME/.homedirgit" filter-repo --path <leaked-file> --invert-paths --force
```

Option B (fresh single-commit history — simplest, loses old history):

```bash
cp -a ~/.homedirgit ~/.homedirgit.bak-2026-06-17
git --git-dir="$HOME/.homedirgit" checkout --orphan clean-master
config add -A
config commit -m "chore: fresh history after secret extraction"
git --git-dir="$HOME/.homedirgit" branch -D master
git --git-dir="$HOME/.homedirgit" branch -m clean-master master
```

Re-run Step 2 after scrubbing; expected: `no leaks found`.

- [ ] **Step 4: Record the audit outcome**

Append the result (clean / scrubbed-Option-A / fresh-Option-B) to `~/dotfiles-docs/idea-2.md` history section, then `config commit`.

---

### Task 15: Adopt everything into the bare repo and publish

**Files:**
- Modify: `~/.gitignore`
- Repo: `~/.homedirgit` (via `config`)

- [ ] **Step 1: If the bare repo does not exist yet, initialise it**

```bash
config status >/dev/null 2>&1 || { source ~/.bashrc.d/homedir-git; config-onetime-init; }
```
Expected: `config status` works (repo present).

- [ ] **Step 2: Gitignore the secret store and the bare repo path**

```bash
grep -qxF "$HOME/.secrets/" ~/.gitignore 2>/dev/null || echo "$HOME/.secrets/" >> ~/.gitignore
grep -qxF "$HOME/.homedirgit" ~/.gitignore 2>/dev/null || echo "$HOME/.homedirgit" >> ~/.gitignore
cat ~/.gitignore
```
Expected: both paths present.

- [ ] **Step 3: Verify `~/.secrets` is NOT tracked**

```bash
config status --porcelain | grep -E '\.secrets' && echo "DANGER: secrets tracked" || echo "SECRETS UNTRACKED OK"
```
Expected: `SECRETS UNTRACKED OK`.

- [ ] **Step 4: Stage and commit the full bashrc.d set**

```bash
config add ~/.bashrc.d ~/.gitignore ~/dotfiles-docs
config status
config commit -m "feat: consolidate ~/.bashrc.d under homedirdotfiles; retire dot"
```
Expected: a commit with the snippet files. Re-confirm via `config show --stat HEAD` that no `~/.secrets` file or literal secret is included.

- [ ] **Step 5: Push only after the Task 14 audit is clean**

```bash
config push    # or `config push -u origin master` on first push
```
Expected: push succeeds. (Do NOT push if Task 14 found unscrubbed leaks.)

---

### Task 16: Final fresh-shell verification and cleanup

- [ ] **Step 1: Open a brand-new login shell and confirm clean load**

```bash
bash -lic 'echo OK' 2>&1 | tail -20
```
Expected: ends in `OK` with no `command not found`, no source errors, no dot references.

- [ ] **Step 2: Confirm the key tools and functions are present**

```bash
bash -lic 'declare -F secret withsecret >/dev/null && command -v zoxide starship >/dev/null && echo "TOOLS OK"'
```
Expected: `TOOLS OK`.

- [ ] **Step 3: Confirm a real secret resolves via secret()**

```bash
bash -lic 'v=$(secret openai); [[ -n "$v" ]] && echo "SECRET OK"'
```
Expected: `SECRET OK` (one prompt/confirmation at most).

- [ ] **Step 4: Confirm no nested repos and no tracked secrets remain**

```bash
find ~/.bashrc.d -name .git -maxdepth 3 2>/dev/null | grep . && echo "STRAY GIT" || echo "FLAT OK"
config ls-files | grep -E '\.secrets' && echo "DANGER" || echo "NO TRACKED SECRETS"
```
Expected: `FLAT OK` and `NO TRACKED SECRETS`.

- [ ] **Step 5: Remove the migration backup once satisfied**

```bash
# Only after everything above passes and you are confident.
rm -f ~/dot-migration-backup-2026-06-17.tar.gz
rm -rf ~/.homedirgit.bak-2026-06-17   # if a scrub backup was made in Task 14
echo "CLEANUP DONE"
```
Expected: `CLEANUP DONE`.

---

## Self-Review notes

- **Spec coverage:** path migration to `~/.bashrc.d` (Tasks 8–13, 16); subdir/flat model (Tasks 8–13); distro-loop sourcing (Task 12); `secret()` layered proxy→cli→plaintext + memoisation (Tasks 2,4); `withsecret` (Task 5); gnome-keyring rejected (no task — correctly omitted); delete dot/powerline/jumpmarks (Tasks 8,11,12); flatten dot-home/dot-ssh (Tasks 9,10); zoxide (Task 8); secret extraction (Tasks 6,7); history audit (Task 14); single publishable repo (Task 15); verification (Task 16). All spec items mapped.
- **Proxy-helper risk:** handled by Task 4 being self-contained and skippable; cli remains primary if the capability test fails.
- **Secret-leak safety:** inventory uses `grep -l`; extraction edits in `$EDITOR`; gitleaks redacts; explicit "do not add files with literal secrets" gates on every commit.
- **Ordering safety:** infrastructure (`secret`) built and tested before any extraction; repos deleted only after their content is flattened and verified; push gated on a clean history audit; backup retained until Task 16.
