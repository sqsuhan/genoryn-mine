# Run on any Linux VM

This is the short path for a **fresh Ubuntu 22.04 / 24.04 x86-64** VM (Hetzner, DigitalOcean, Linode, AWS, a home box, etc.).

## 1. SSH in

```bash
ssh user@YOUR_VM_IP
```

You need a real TTY. Wallet creation asks for a password.

## 2. Install git (once)

```bash
sudo apt-get update
sudo apt-get install -y git
```

The miner script will install `curl`, `unzip`, `python3` and friends if they are missing (needs passwordless sudo, or you install them yourself).

## 3. Clone and run

```bash
git clone https://github.com/sqsuhan/genoryn-mine.git
cd genoryn-mine
bash genoryn-mine.sh
```

First run: platform check → download official miner (SHA-256 pinned) → create wallet → start mining → enable reboot autostart → menu.

Write the **24 recovery words on paper** when they appear. You will be quizzed on 3 of them.

## 4. Detach and come back later

The miner keeps running after you close SSH (`setsid` + `nohup`).

```bash
bash ~/genoryn/genoryn-mine.sh status
bash ~/genoryn/genoryn-mine.sh logs
bash ~/genoryn/genoryn-mine.sh mined
```

Or clone again on another session and use the same commands from the repo directory.

## 5. Copy the wallet off the VM

```bash
bash ~/genoryn/genoryn-mine.sh backup
# on your laptop:
scp user@YOUR_VM_IP:~/genoryn-backups/wallet-*.gnr .
```

A backup that only lives on the VM dies with the VM.

## 6. Pool stats

1. `bash ~/genoryn/genoryn-mine.sh address`
2. Open https://pool.ariabrain.com/gnr.html
3. Paste the address under **My stats**

## Sizing

| VM RAM | What the script does |
|--------|----------------------|
| ~1 GiB | light RandomX, fewer threads |
| ≥ ~2.4 GiB free + threads | `auto` mode (~2 GiB dataset, faster) |

Override threads:

```bash
GNR_THREADS=2 bash ~/genoryn/genoryn-mine.sh restart
```

## Cloud terms

- Google Cloud **Free Trial: no mining**.
- On a paid VM, watch the bill vs. GNR earned. Tiny shared-vCPU instances often lose money.
- You must be allowed to run a miner on that machine.

## Reboot

`setup` turns on cron `@reboot`. Confirm:

```bash
crontab -l | grep genoryn
```

Turn off: `bash ~/genoryn/genoryn-mine.sh autostart-off`
