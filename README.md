# homedirdotfiles

My `$HOME` dotfiles, managed as a **bare git repository** (no `~/.git`, so it
doesn't interfere with other repos). Shell configuration lives as small,
single-purpose snippets in `~/.bashrc.d/`, sourced automatically at login.
Secrets are **never stored in this repo** — they are read from KeePassXC at
runtime.

## The `config` alias

All git operations use a `config` alias defined in `~/.bashrc.d/homedir-git`:

```bash
config status
config add ~/.bashrc.d/foo
config commit -m "Add foo"
config push
```

It expands to `git --git-dir=$HOME/.homedirgit --work-tree=$HOME`.

## Setting up a new machine

Prerequisites: `git`, an SSH key registered with GitHub, and `~/.gitconfig`
containing your name.

```bash
# 1. Clone the bare repo into its side folder
git clone --bare git@github.com:DrGeoff/homedirdotfiles.git ~/.homedirgit

# 2. Define the alias for this shell
alias config='git --git-dir=$HOME/.homedirgit --work-tree=$HOME'

# 3. Local settings that git clone does NOT carry
config config --local status.showUntrackedFiles no
config config --local core.hooksPath ~/.config/git/hooks   # pre-commit secret scan

# 4. Check out into $HOME (move any conflicting pre-existing files aside first)
config checkout
```

Once `~/.bashrc.d/homedir-git` is checked out, the `config` alias and the
helper functions `config-onetime-init` / `config-replicate` are available in
every new shell. `config-replicate` automates steps 1–4.

## How snippets load

`~/.bashrc` sources every **top-level file** in `~/.bashrc.d/`:

```bash
if [ -d ~/.bashrc.d ]; then
    for bashrc_entry in ~/.bashrc.d/*; do
        [ -f "$bashrc_entry" ] && . "$bashrc_entry"
    done
fi
unset bashrc_entry
```

Snippets are flat files — one concern each (`atuin`, `starship`, `zoxide`,
`ssh-agent`, …). **Subdirectories are intentionally not sourced**, so the test
suite under `~/.bashrc.d/tests/` never runs at shell startup.

## Secrets

Snippets never hardcode secrets. They call `secret()`
(`~/.bashrc.d/secret`), which reads from KeePassXC, memoised per shell:

```bash
export OPENAI_API_KEY=$(secret openai)
```

Resolution order for the database (`~/.bashrc.d/keepass-env`):

1. an already-exported `$KPXC_DB`
2. **`~/.config/secret.local`** — an untracked, gitignored file you create per
   machine, e.g.:

   ```bash
   printf 'export KPXC_DB="$HOME/your-vault.kdbx"\n' > ~/.config/secret.local
   ```
3. autodetect: exactly one `*.kdbx` in `$HOME`

Backends are tried in order **keepassxc-cli → `~/.secrets/<name>` plaintext
fallback**. (A `keepassxc-proxy` tier can be added later.) `withsecret`
(`~/.bashrc.d/withsecret`) injects a secret into a single command's environment:

```bash
withsecret OPENAI_API_KEY=openai -- some-command
```

`~/.secrets/` (mode `700`, files `600`) and `~/.config/secret.local` are
gitignored and must never be committed.

## Pre-commit secret scanner

A pre-commit hook (`~/.config/git/hooks/secret-scan`) blocks any commit that
introduces a recognised secret (API keys, tokens, private-key blocks) or a
`.secrets/` path. It is enabled per repo via `core.hooksPath` (set automatically
by `config-onetime-init` / `config-replicate`). Override a false positive with
`config commit --no-verify`.

## Tests

```bash
bash ~/.bashrc.d/tests/run.sh
```

Tests use throwaway data only (e.g. a disposable KeePassXC database); they never
touch real vaults or secrets, and skip cleanly if a dependency is missing.

## Dependencies

`bash`, `git`, `keepassxc` (`keepassxc-cli`), plus the tools the snippets drive:
`zoxide`, `starship`, `atuin`. Optional: `gitleaks` for history audits.
