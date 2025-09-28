# upgrade_fabric_server

This repository contains `upgrade_fabric_server.sh`, a shell script to upgrade a Minecraft server running Fabric API.

Prerequisite
------------

The script expects the `jq` utility to be available on the system PATH. `jq` is a lightweight command-line JSON processor used by the script to parse JSON output.

Install `jq`
--------------

Use one of the following commands depending on your platform.

Linux (Debian/Ubuntu):

```bash
sudo apt update
sudo apt install -y jq
```

Linux (RHEL/CentOS/Fedora):

```bash
sudo dnf install -y jq
```

Verify installation
-------------------

Run:

```bash
jq --version
```

It should print a version string, for example `jq-1.6`.

Notes
-----

- If you cannot install `jq`, the script may fail or produce incorrect output. Consider installing `jq` or modifying the script to avoid JSON parsing with `jq`.


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



