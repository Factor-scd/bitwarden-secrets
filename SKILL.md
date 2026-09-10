---
name: bitwarden-secrets
description: Retrieve secrets from a self-hosted Bitwarden/Vaultwarden vault via the bw-secrets helper. Use when you need API keys, tokens, passwords, database credentials, or any sensitive value. Auto-syncs before reads, agent-friendly exit codes, no session file on disk.
version: 3.0.0
---

# Bitwarden Secrets Skill

Secure access to a self-hosted Bitwarden/Vaultwarden vault for retrieving
secrets at runtime.

## When to use

- You need an API key, token, password, or credential for any service
- You need to know what secrets exist and where they live
- You are writing a script, cron job, or agent flow that needs a secret

## ⚠️ Standing rules

1. **Secrets ALWAYS live in Bitwarden.** Never `.env`, never config.yaml,
   never plaintext anywhere. Fetch at runtime.
2. **ALL items go in an org vault**, never the personal vault.
3. **ALWAYS `bw sync` before reads** — the CLI serves a local cache; external
   updates are invisible until sync. `bw-secrets` does this automatically.
4. **Look items up by id, never by name** — em-dash names cause silent 0-byte
   responses from `bw get item`. `bw-secrets` handles this internally.
5. **Never write the session token to disk.** Re-unlock per invocation.

## Quick reference

```bash
# Get a secret (password is default) — searches the default org
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

# Discovery
bw-secrets org list
bw-secrets org collections

# Environment-style output (for sourcing)
bw-secrets env <name> [field]

# Maintenance
bw-secrets sync
bw-secrets status
bw-secrets unlock
```

## Exit codes (agent contract)

| Code | Meaning |
|---|---|
| `0` | Found, value on stdout |
| `1` | Not found / error |
| `2` | Ambiguous match — refine the search |

## Org-first behavior

`bw-secrets` is **org-first** — `get`/`list`/`env` search the default org's
collections by default. Personal-vault items (no collection) require
`--personal` or `--all`:

```bash
bw-secrets get "some-personal-item" --personal username
```

Org membership is determined by collectionIds intersecting the org's
collection IDs — NOT by item.organizationId, which is null on items created
via `bw create item`.

## The Python pattern (primary agent interface)

For agents, the canonical way to use a secret is a `get_secret()` helper —
it never puts the secret in a shell command line, log, or process listing:

```python
import json, subprocess, os

def get_secret(substring, collection_id=None, field='password'):
    """Fetch a secret from Bitwarden by item-name substring."""
    env = {**os.environ, 'PATH': '/usr/bin:/bin'}
    session = subprocess.run(
        ['bw', 'unlock', '--passwordfile', '<master-pw-file>', '--raw'],
        capture_output=True, text=True, env=env, check=True,
    ).stdout.strip()
    items = json.loads(subprocess.run(
        ['bw', 'list', 'items', '--session', session],
        capture_output=True, text=True, env=env, check=True,
    ).stdout)
    matches = [i for i in items if substring.lower() in i.get('name','').lower()]
    if collection_id is not None:
        scoped = [i for i in matches if collection_id in i.get('collectionIds', [])]
        if scoped:
            matches = scoped
    for it in matches:
        item = json.loads(subprocess.run(
            ['bw', 'get', 'item', it['id'], '--session', session],
            capture_output=True, text=True, env=env, check=True,
        ).stdout)
        if field == 'password':
            return item['login']['password']
        if field in [f['name'] for f in item.get('fields', [])]:
            return {f['name']: f['value'] for f in item['fields']}[field]
        return item
    raise KeyError(f"No item matching {substring!r}")
```

## Common patterns

### Get a token for an API call

```bash
# Inline — secret never stored in a variable
curl -H "Authorization: token $(bw-secrets get 'my-token')" \
     https://api.example.com/v1/user
```

### Get a credential from a collection

```bash
bw-secrets org get Infrastructure "my-server" username
bw-secrets org get Infrastructure "my-server" password
bw-secrets org get Applications "my-app" custom:URL
```

### Generate an env file (only when absolutely necessary)

```bash
bw-secrets sync
cat > .env << EOF
DATABASE_URL=$(bw-secrets get my-db url)
API_KEY=$(bw-secrets get my-api password)
EOF
chmod 600 .env
```

### In a deployment script

```bash
#!/bin/bash
set -euo pipefail
# ✅ CORRECT — inline usage, secret never stored
ssh $(bw-secrets get production-server username)@server.com \
    "docker login -u $(bw-secrets get docker-hub username) -p $(bw-secrets get docker-hub password) registry.com"
```

## Security guidelines

### DO

- Sync before every read (auto-synced in `bw-secrets`)
- Use secrets inline in commands — never persist to disk, never echo
- Use the helper script for all vault operations
- Use appropriate collections for different secret types
- Use `set +x` before commands that handle secrets

### DON'T

- Never write the session token to disk
- Never log secret values in plain text
- Never commit `.env` files or credentials
- Never share secrets in chat or documentation
- Never store secrets in git repositories
- Never hardcode credentials in scripts

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `ERROR: no items found matching 'X'` | Item doesn't exist, or is in a different collection | `bw-secrets list X --all` to search everything |
| `ERROR: ambiguous match for 'X'` | Multiple items match | Add `--collection <name>` or refine the name |
| `ERROR: collection 'X' not found` | Wrong collection name | `bw-secrets org collections` to list real names |
| `ERROR: master password file not found` | Wrong path | Set `BW_MASTER_PW_FILE` |
| `bw: command not found` | Not on PATH | Install the Bitwarden CLI and add it to PATH |
| `ERROR: BW_SERVER is not set` | Missing config | Set `BW_SERVER` in `~/.config/bw/config.env` |
| Stale values after external update | CLI local cache | `bw-secrets sync` (auto-done on every get/list) |

## Development

Repo: `bitwarden-secrets` (self-hosted git).
Single-file tool: `bw-secrets` (pure Python 3, stdlib only).
Install: `./install.sh` → `~/.local/bin/bw-secrets`.
