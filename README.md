# bw-secrets — Agent-friendly Bitwarden/Vaultwarden secrets helper

Single-file, pure-Python (stdlib only) helper for retrieving secrets from a
self-hosted Bitwarden/Vaultwarden vault. Designed for **agents** (AI coding
agents, kanban workers, cron jobs) and humans alike.

## Why this exists

The `bw` CLI is powerful but not agent-friendly: it needs a session token,
serves a stale local cache, and fails silently on non-ASCII item names.
`bw-secrets` wraps it with:

- **Auto-sync before every read** (the CLI serves a local cache)
- **Lookup by id, never by name** (avoids the em-dash silent-failure bug)
- **Agent exit codes**: `0` found, `1` not found, `2` ambiguous match
- **No session file on disk** — re-unlocks per invocation, token stays in-process
- **No jq, no pexpect** — pure Python 3 stdlib
- **Org-first by default** — `get`/`list`/`env` search the default org's
  collections; personal-vault items require `--personal` (or `--all`)
- **Org-aware, case-insensitive collection lookup**

## Organizations by default

`bw-secrets` is **org-first**: secrets for agents belong in an organization,
not in a personal vault. This gives you shared access control, collections,
and auditability — a personal vault is a single-user silo with none of that.

By default, `get`, `list`, and `env` search only the default org
(`BW_ORG_ID`). Personal-vault items are excluded unless you ask for them:

```bash
bw-secrets get <name>              # searches the default org only
bw-secrets get <name> --personal   # searches personal vault items only
bw-secrets get <name> --all        # searches everything
```

### Setting up an org for your agent (walkthrough)

If you don't have an org yet, here's the recommended setup. The pattern:
**one dedicated user account per agent**, added to the org with access to
only the collections it needs.

1. **Create the agent's Bitwarden account** (a dedicated user, e.g.
   `agent-name@yourdomain.com` — never share your personal account with an
   agent):
   [Create a Bitwarden account](https://bitwarden.com/help/create-bitwarden-account/)

2. **Create an organization** (free for personal use; this is where shared
   secrets live):
   [Getting started with organizations](https://bitwarden.com/help/getting-started-organizations/) ·
   [About organizations](https://bitwarden.com/help/about-organizations/)

3. **Invite the agent's user account to the org** and assign it a role
   (User is enough for read access; Owner/Admin only if the agent must manage
   the org):
   [Manage users in your organization](https://bitwarden.com/help/managing-users/)

4. **Create collections** for the agent's secret types (e.g.
   `infrastructure`, `applications`, `credentials`, `devops`):
   [Create collections](https://bitwarden.com/help/create-collections/)

5. **Assign the agent user to the collections** it needs and set
   permissions (Read-only is the safe default for an agent):
   [Assign users to collections](https://bitwarden.com/help/assign-users-to-collections/) ·
   [Collection permissions](https://bitwarden.com/help/collection-permissions/)

6. **Point `bw-secrets` at the org**: set `BW_ORG_ID` to the new org's id in
   `~/.config/bw/config.env` (or export it), then verify with
   `bw-secrets org collections`.

### Self-hosted option: Vaultwarden

Don't want to pay for Bitwarden or send secrets to their cloud? **Vaultwarden**
is a free, open-source, self-hosted Bitwarden-compatible server — drop-in
compatible with the `bw` CLI and this tool. Just set `BW_SERVER` to your
instance URL.

- [Vaultwarden on GitHub](https://github.com/dani-garcia/vaultwarden)
- [Self-host Bitwarden (official docs)](https://bitwarden.com/help/self-host-bitwarden/) ·
  [Self-host an organization](https://bitwarden.com/help/self-host-an-organization/)

## Requirements

- `bw` CLI (Bitwarden CLI) — on PATH
- Master password file (default `~/.config/bw/master_pw`, chmod 600)
- Python 3.8+

## Install

```bash
./install.sh          # copies bw-secrets to ~/.local/bin/bw-secrets
```

Or manually: copy `bw-secrets` to `~/.local/bin/`, `chmod 700`.

## Configuration

All values are overridable via environment variables or
`~/.config/bw/config.env` (highest wins: env var > config file > default).

| Variable | Default | Purpose |
|---|---|---|
| `BW_SERVER` | *(required)* | Vaultwarden URL |
| `BW_ORG_ID` | *(required for org-first)* | Default org id |
| `BW_MASTER_PW_FILE` | `~/.config/bw/master_pw` | Master password file |
| `BW_BIN` | `bw` | bw CLI path |

```bash
# ~/.config/bw/config.env (chmod 600)
BW_SERVER=https://vault.example.com
BW_ORG_ID=<your-org-id>
BW_MASTER_PW_FILE=/path/to/master_pw
```

## Agent onboarding (copy-paste prompt)

Paste the block below to any agent to configure this tool interactively. The
agent should run each step, confirm the result, and only proceed on success.

````text
You are configuring the `bw-secrets` tool — an agent-friendly wrapper around
the Bitwarden CLI for retrieving secrets from a self-hosted vault. Work
through these steps in order, running every command and reporting the result
of each before moving on.

STEP 1 — Install
Clone the repo to a temp dir, run ./install.sh, then remove the clone:
  git clone <repo-url> /tmp/bw-secrets-setup
  cd /tmp/bw-secrets-setup && ./install.sh
  cd / && rm -rf /tmp/bw-secrets-setup
Confirm: `~/.local/bin/bw-secrets` exists and is executable (chmod 700).

STEP 2 — Configure
Create ~/.config/bw/config.env (chmod 600) with:
  BW_SERVER=<vault-url>
  BW_ORG_ID=<org-id>
  BW_MASTER_PW_FILE=<path-to-master-password-file>
Ask the user for these values if they are not already set. Do NOT ask for or
store the master password itself — it must never be typed or stored anywhere
except the master password file.

STEP 3 — Verify the environment
Run `bw-secrets status`. You should see JSON with "status":"locked" and the
serverUrl you configured. If `bw` is not found, install the Bitwarden CLI and
ensure it is on PATH.

STEP 4 — Test retrieval (live vault)
Run these and confirm each returns a value (do not print full secret values —
show only the first 6 and last 4 characters):
  bw-secrets org list
  bw-secrets org collections
  bw-secrets list --all
  bw-secrets get <some-known-item> --all username
If any command errors with "could not parse", re-run it — the tool retries
internally, but a stale session can still fail once; a second run succeeds.

STEP 5 — Verify exit codes (agent contract)
  bw-secrets get "definitely-not-a-real-item-xyz"; echo $?   # expect: 1
  bw-secrets get "a"; echo $?                                # expect: 2 (ambiguous)
  bw-secrets get <some-known-item> --all >/dev/null; echo $? # expect: 0

When all five steps pass, report: "bw-secrets configured and verified —
install OK, retrieval OK, exit codes 0/1/2 OK." If any step fails, stop and
report the exact error rather than guessing.
````

## Usage

```bash
# Get a secret (password is default field) — searches the default org
bw-secrets get <name>
bw-secrets get <name> username
bw-secrets get <name> custom:<field>
bw-secrets get <name> json

# Search scope (default: org only)
bw-secrets get <name> --personal   # personal vault items only
bw-secrets get <name> --all        # everything (org + personal)

# Scoped to a collection (case-insensitive)
bw-secrets get <name> --collection Infrastructure
bw-secrets org get Infrastructure <name> [field]

# List / search
bw-secrets list [search]
bw-secrets list [search] --personal
bw-secrets org items Infrastructure [search]

# Org / collection discovery
bw-secrets org list
bw-secrets org collections

# Environment-style output (for sourcing)
bw-secrets env <name> [field]

# Maintenance
bw-secrets sync
bw-secrets status
bw-secrets unlock
```

### Fields

| Field | Description |
|---|---|
| `password` (default) | Login password |
| `username` | Login username |
| `notes` | Item notes |
| `totp` | TOTP URI |
| `url` | First login URI |
| `custom:<name>` | Custom field by name |
| `json` | Full item JSON |
| `<dotted.path>` | Any dotted path into the item, e.g. `login.uris.0.uri` |

### Exit codes

| Code | Meaning |
|---|---|
| `0` | Found, value printed to stdout |
| `1` | Not found / error |
| `2` | Ambiguous match (multiple items) — refine your search |

## Security rules

- **Secrets ALWAYS live in Bitwarden.** This tool only reads them at runtime.
- **Never write the session token to disk.** Re-unlock per invocation.
- **Never echo secrets to logs.** Use `set +x` around secret handling.
- **Never commit `.env` files or credentials.**
- The master password file is the ONLY secret on disk (chmod 600).

## Development

```bash
git clone <repo-url>
# edit bw-secrets, test against the live vault, commit, push
```

See `SKILL.md` for the agent-facing usage documentation.
