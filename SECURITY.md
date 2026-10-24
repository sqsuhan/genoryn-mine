# Security

This manager downloads the official GENORYN miner and talks to a mining pool. Treat it like software that handles money.

## What the script does with trust

- Downloads `genoryn-<version>-mainnet-linux-x86_64.zip` from `https://github.com/genoryn/genoryn/releases`
- Checks the published `.sha256` next to that zip
- For the default version (v1.2.0) it also checks a **hash pinned in this repository**
- Unzips and runs `sha256sum -c SHA256SUMS` on the files inside the archive
- Refuses to continue if any of those checks fail

If you install a version that is not the pinned default, you must set `GNR_SHA256` yourself from the release page. The script will not auto-trust an unknown zip.

## Wallet

- The 24-word recovery phrase **is** the wallet. Anyone with those words can spend the coins.
- Write them on paper. Do not screenshot. Do not type them into chat, Discord, Telegram, email, or a “support” form.
- The password encrypts `~/.genoryn/mainnet-1.0/wallet.gnr` on this machine. There is no reset.
- `address.txt` is a public receiving address. It is not a secret.
- `backup` copies the encrypted wallet file. Move that copy **off the VM**. A file that only exists on the same disk as the original is not a backup.
- `uninstall` does not delete the wallet or `~/genoryn-backups`.

## What this script never does

- It never prints your recovery phrase to a log file.
- It never sends the phrase or password to the pool or to GitHub.
- It never asks you to paste a phrase into a website.
- It never mines to a hardcoded address. Mining uses **your** wallet address from `address.txt`.

Read `genoryn-mine.sh` before you run it. Confirm `POOL` and that `--wallet` is your address.

## VM / cloud

- Do not run this on a Google Cloud **free trial** (their terms forbid mining).
- Do not run this on a machine you do not own or are not allowed to use for mining.
- Compare VM cost with what you actually earn. Shared-vCPU boxes often lose money.
- After `backup`, `scp` the `.gnr` file to your laptop or encrypted USB, then consider deleting extra copies on the VM.

## Pool

AriaPool holds rewards until payout (hourly, 1 GNR minimum as documented in the script). That is custodial risk. Check [pool stats](https://pool.ariabrain.com/gnr.html) and `bash genoryn-mine.sh balance` after payouts.

## Reporting issues

Open an issue on this repo for problems in **this manager script**. Miner bugs belong at [genoryn/genoryn](https://github.com/genoryn/genoryn).
