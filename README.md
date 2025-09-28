# upgrade_fabric_server

This repository contains `upgrade_fabric_server.sh`, a shell script to upgrade a Minecraft server running Fabric API.

Prerequisite
------------
The script expects the `jq` utility to be available on the system PATH. `jq` is a lightweight command-line JSON processor used by the script to parse JSON output.
Installation instructions can be found at: https://stedolan.github.io/jq/.

Usage
-----

Basic invocation:

```bash
./upgrade_fabric_server.sh
```

Useful flags:

- `--dry-run` — show actions the script would take without making changes.
- `--yes` or `--non-interactive` — automatically confirm prompts (useful for automation).
- `--help` or `-h` — print a short usage message.

Examples:

Show what would happen without changing files:

```bash
./upgrade_fabric_server.sh --dry-run
```

Run non-interactively (use with care):

```bash
./upgrade_fabric_server.sh --yes
```
