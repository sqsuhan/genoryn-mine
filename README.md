# GENORYN (GNR) miner for Linux VMs

One bash script that installs the **official** GENORYN CPU miner on Linux x86-64, creates a wallet, connects to AriaPool over TLS, and gives you a menu (or CLI) to start, stop, check stats, back up, and uninstall.

Tested as a drop-in for a fresh Ubuntu 22.04+ VM. Clone it, run it, leave it mining.

> This repository is a **manager**. It downloads [genoryn/genoryn](https://github.com/genoryn/genoryn) release **v1.2.0**, checks a **pinned SHA-256**, then runs `genoryn-miner` in pool mode. It does not ship the miner binary.

## Quick start (any Linux x86-64 VM)

```bash
# 1. Get the script
git clone https://github.com/sqsuhan/genoryn-mine.git
cd genoryn-mine

# 2. Optional: read it before you run it
less genoryn-mine.sh

# 3. First run = install + wallet + start + menu
bash genoryn-mine.sh
```

One-liner if `git` is not installed yet (Ubuntu/Debian):

```bash
sudo apt-get update && sudo apt-get install -y git
git clone https://github.com/sqsuhan/genoryn-mine.git
cd genoryn-mine && bash genoryn-mine.sh
```

The first run:

1. Checks Linux x86-64 and glibc 2.34+
2. Installs missing tools (`curl`, `unzip`, `python3`, …) via `apt-get` when passwordless sudo is available
3. Downloads the official `genoryn-1.2.0-mainnet-linux-x86_64.zip` and verifies SHA-256
4. Creates a wallet (password + 24 recovery words, then a 3-word quiz)
5. Starts the miner in the background
6. Enables `@reboot` autostart via cron
7. Opens an interactive menu

You need an **interactive terminal** for wallet creation (password prompt). SSH is fine. `curl | bash` is not, because stdin is not a TTY.

## Requirements

| Need | Detail |
|------|--------|
| OS | Linux **x86-64** only (official miner build) |
| glibc | **2.34+** (Ubuntu 22.04, Debian 12, or newer) |
| RAM | ~600 MiB minimum (light mode). ~2.4 GiB+ free for full RandomX (`auto`) |
| CPU | AES-NI recommended; without it RandomX is much slower |
| Network | outbound TLS to `gnr.ariabrain.com:3351` |
| Disk | a few hundred MiB under `~/genoryn` |

Cloud notes:

- **Google Cloud Free Trial forbids mining.** Use a paid VM and compare cost vs. earnings.
- Cheap shared-vCPU VMs often earn less than they cost. Check `status` hashrate after a few minutes.
- Do not run this as a hidden process on a machine you do not own.

## Commands

```text
bash genoryn-mine.sh                 # setup on first run, then menu
bash genoryn-mine.sh setup           # full automatic setup
bash genoryn-mine.sh start|stop|restart
bash genoryn-mine.sh status          # PID, pool, hashrate, last log lines
bash genoryn-mine.sh logs            # follow miner.log
bash genoryn-mine.sh mined           # accepted/rejected shares in this log
bash genoryn-mine.sh balance         # on-chain wallet balance (password)
bash genoryn-mine.sh address         # receiving address
bash genoryn-mine.sh phrase          # show 24 recovery words (password)
bash genoryn-mine.sh backup          # copy encrypted wallet to ~/genoryn-backups
bash genoryn-mine.sh autostart-on | autostart-off
bash genoryn-mine.sh update          # compare installed vs latest GitHub release
bash genoryn-mine.sh install         # (re)install the pinned miner
bash genoryn-mine.sh uninstall       # remove ~/genoryn; wallet and backups stay
bash genoryn-mine.sh help
```

After setup, the script also copies itself to `~/genoryn/genoryn-mine.sh`, so you can run it from there:

```bash
bash ~/genoryn/genoryn-mine.sh status
```

## Where things live

| Path | What |
|------|------|
| `~/genoryn/` | miner binary, logs, pid file, generated runner |
| `~/genoryn/address.txt` | receiving address (not a secret) |
| `~/genoryn/miner.log` | miner output (rotated around 50 MiB) |
| `~/.genoryn/mainnet-1.0/wallet.gnr` | **encrypted** wallet (official default path) |
| `~/genoryn-backups/` | copies from `backup`; **uninstall never deletes this** |

## Environment overrides

```bash
GNR_THREADS=4 bash genoryn-mine.sh start          # cap CPU threads
GNR_WORKER=rig-east bash genoryn-mine.sh start    # pool worker name
GNR_POOL=tls://gnr.ariabrain.com:3351 bash genoryn-mine.sh start
GNR_HOME=/opt/genoryn bash genoryn-mine.sh setup  # install dir (default ~/genoryn)
```

The script pins official miner **v1.2.0** and checks its SHA-256 on download. To install another [release](https://github.com/genoryn/genoryn/releases), copy that zip’s hash from the release page:

```bash
GNR_VERSION=<version> GNR_SHA256=<hash from the release page> bash genoryn-mine.sh install
```

## Pool and payouts

- Pool: AriaPool TLS `tls://gnr.ariabrain.com:3351`
- Stats: [https://pool.ariabrain.com/gnr.html](https://pool.ariabrain.com/gnr.html) → **My stats** → paste your address
- PPLNS, 3% pool fee (as documented in the script)
- An **accepted share is work**, not a coin. You earn when the pool finds a block; credit after ~60 confirmations
- AriaPool pays hourly once the pending balance reaches **1 GNR**
- Pool mining is **custodial** until payout hits your wallet. Check `balance` after payouts, not only pool stats

## Wallet safety (read this)

1. Write the **24 recovery words** on paper. They **are** the money.
2. Never screenshot them, never paste them in chat, Discord, Telegram, or a ticket.
3. The wallet password encrypts `wallet.gnr` on this machine. Nobody can reset it.
4. `backup` copies the encrypted file. A copy that stays on the same VM is not a backup — `scp` it off the box.
5. `uninstall` keeps the wallet and `~/genoryn-backups`. Delete those yourself only after the 24 words are on paper.

See [SECURITY.md](SECURITY.md).

## Typical VM session

```bash
ssh user@your-vm
git clone https://github.com/sqsuhan/genoryn-mine.git
cd genoryn-mine
bash genoryn-mine.sh          # create wallet, start miner
# later:
bash genoryn-mine.sh status
bash genoryn-mine.sh mined
bash genoryn-mine.sh backup
scp user@your-vm:~/genoryn-backups/wallet-*.gnr .
```

Hashrate in `status` appears after about 1–2 minutes. Full RandomX mode builds a ~2 GiB dataset first.

## Uninstall

```bash
bash genoryn-mine.sh uninstall    # type UNINSTALL
```

Removes `~/genoryn` (binaries, logs, pid). Leaves `~/.genoryn/.../wallet.gnr` and `~/genoryn-backups`.

## What this is not

- Not an official GENORYN product. Official software: [github.com/genoryn/genoryn](https://github.com/genoryn/genoryn)
- Not financial advice. GENORYN is new and not independently audited. Mine or hold only what you can lose.
- Not a GPU miner. CPU RandomX only.
- Not for macOS, Windows, ARM, or 32-bit Linux.

## License

MIT. See [LICENSE](LICENSE).

The GENORYN binaries this script downloads are licensed by their authors. This repo only ships the manager script and docs.
