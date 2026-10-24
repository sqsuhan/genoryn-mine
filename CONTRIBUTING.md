# Contributing

This repo is a small manager around the official GENORYN Linux miner. Keep it that way.

## Rules of thumb

- One script: `genoryn-mine.sh`. Do not split it unless there is a strong reason.
- Pin a SHA-256 for the default release. Never auto-download an unverified zip.
- Do not log recovery phrases, passwords, or seed material.
- Do not hardcode a mining address. Always use the local wallet.
- Docs stay in the repo root: `README.md`, `SECURITY.md`.

## Checks before a PR

```bash
bash -n genoryn-mine.sh
bash genoryn-mine.sh help
```

Test `setup` on a throwaway Ubuntu 22.04+ x86-64 VM when you change install, start/stop, or wallet flow.
