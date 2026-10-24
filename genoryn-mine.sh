#!/usr/bin/env bash
# =============================================================================
#  genoryn-mine.sh - GENORYN (GNR) CPU miner manager for Linux x86-64
#
#  Everything is built in: official release v1.2.0 (pinned SHA-256), the official
#  `genoryn-miner` in pool mode, the AriaPool TLS endpoint, wallet creation with
#  a recovery-phrase check, logs, mined stats, balance, backup and uninstall.
#
#    bash genoryn-mine.sh              first run = full automatic setup, then a menu
#    bash genoryn-mine.sh <command>    setup | start | stop | restart | status | logs
#                                      mined | balance | phrase | backup | address
#                                      autostart-on | autostart-off | update
#                                      install | uninstall
#
#  Optional overrides (environment): GNR_THREADS  GNR_WORKER  GNR_POOL  GNR_HOME
#                                    GNR_VERSION + GNR_SHA256 (install another release)
# =============================================================================
set -u

# ----------------------------- built-in settings -----------------------------
DEFAULT_VERSION="1.2.0"
# SHA-256 of genoryn-1.2.0-mainnet-linux-x86_64.zip. Verified against the file the
# project published; its manifest names commit 646ae96 = the v1.2.0 tag.
DEFAULT_SHA256="94b857f7f1bf04b4d5f894e2f0b6ffbfaf2a3a5bb62a8b53cb0e2eb9f7dc920d"
POOL="${GNR_POOL:-tls://gnr.ariabrain.com:3351}"       # AriaPool, official-miner TLS port
POOL_PAGE="https://pool.ariabrain.com/gnr.html"        # "My stats" lives here
REPO="genoryn/genoryn"

APP_DIR="${GNR_HOME:-$HOME/genoryn}"
WALLET_DIR="$HOME/.genoryn/mainnet-1.0"                # same default as the official wallet
WALLET_FILE="${GNR_WALLET_FILE:-$WALLET_DIR/wallet.gnr}"
BACKUP_DIR="$HOME/genoryn-backups"                     # outside APP_DIR: uninstall never touches it
LOG="$APP_DIR/miner.log"
PIDF="$APP_DIR/miner.pid"
RUNNER="$APP_DIR/run-miner.sh"
ADDR_FILE="$APP_DIR/address.txt"
BIN="$APP_DIR/current"                                 # symlink to the installed release
CRON_TAG="genoryn-mine-autostart"

VERSION="$DEFAULT_VERSION"
if [ "$VERSION" = "$DEFAULT_VERSION" ]; then EXPECTED_SHA256="${GNR_SHA256:-$DEFAULT_SHA256}"; fi
if [ -n "${GNR_VERSION:-}" ]; then
  VERSION="$GNR_VERSION"
  if [ "$VERSION" = "$DEFAULT_VERSION" ]; then EXPECTED_SHA256="${GNR_SHA256:-$DEFAULT_SHA256}"; else EXPECTED_SHA256="${GNR_SHA256:-}"; fi
fi
ASSET="genoryn-${VERSION}-mainnet-linux-x86_64"
BASE_URL="https://github.com/${REPO}/releases/download/v${VERSION}"

# --------------------------------- helpers -----------------------------------
say()  { printf '%s\n' "$*"; }
ok()   { printf '  [ok] %s\n' "$*"; }
warn() { printf '  [!]  %s\n' "$*" >&2; }
die()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }
pause() { echo; read -r -p "Press Enter to continue..." _; }
clear_screen_and_scrollback() { printf '\033[2J\033[3J\033[H'; }
version_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" = "$2" ]; }

need_tty() { [ -t 0 ] && [ -t 1 ] || die "Run this in an interactive terminal (the wallet password prompt needs one)."; }

wallet_exists() { [ -f "$WALLET_FILE" ]; }
installed()     { [ -x "$BIN/genoryn-miner" ] && [ -x "$BIN/genoryn-wallet-cli" ]; }
address()       { [ -f "$ADDR_FILE" ] && cat "$ADDR_FILE"; }

is_running() {
  [ -f "$PIDF" ] || return 1
  local p; p="$(cat "$PIDF" 2>/dev/null)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null && tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'run-miner'
}

# ------------------------------ platform / deps ------------------------------
check_platform() {
  [ "$(uname -s)" = "Linux" ] || die "This script is for Linux."
  [ "$(uname -m)" = "x86_64" ] || die "The official Linux build is x86-64 only (this machine: $(uname -m))."
  local g; g="$(ldd --version 2>&1 | head -n1 | grep -oE '[0-9]+\.[0-9]+$')"
  if [ -n "$g" ] && ! version_ge "$g" "2.34"; then
    die "glibc $g is too old; the miner needs 2.34+ (Ubuntu 22.04 or newer)."
  fi
  grep -qw aes /proc/cpuinfo 2>/dev/null || warn "CPU reports no AES-NI: RandomX will be much slower."
}

ensure_deps() {
  local missing=() pkgs=() c
  for c in curl unzip python3 sha256sum setsid nohup awk shuf; do
    command -v "$c" >/dev/null 2>&1 || missing+=("$c")
  done
  [ "${#missing[@]}" -eq 0 ] && return 0
  warn "Missing tools: ${missing[*]}"
  for c in "${missing[@]}"; do
    case "$c" in sha256sum|nohup|shuf) pkgs+=(coreutils) ;; setsid) pkgs+=(util-linux) ;; awk) pkgs+=(gawk) ;; *) pkgs+=("$c") ;; esac
  done
  command -v apt-get >/dev/null 2>&1 || die "Install these first: ${missing[*]}"
  local SUDO=""; [ "$(id -u)" -ne 0 ] && SUDO="sudo -n"
  if $SUDO true 2>/dev/null; then
    say "Installing: ${pkgs[*]}"
    $SUDO apt-get update -qq && $SUDO apt-get install -y -qq "${pkgs[@]}" || die "apt-get failed."
  else
    die "Run:  sudo apt-get install -y ${pkgs[*]}   then start this script again."
  fi
}

# -------------------------------- install ------------------------------------
install_miner() {
  mkdir -p "$APP_DIR/dl" || die "Cannot create $APP_DIR"
  local dir="$APP_DIR/$ASSET" zip="$APP_DIR/dl/$ASSET.zip" sumf="$APP_DIR/dl/$ASSET.zip.sha256"
  if [ -f "$dir/.verified" ] && [ -x "$dir/genoryn-miner" ]; then
    ln -sfn "$dir" "$BIN"; ok "v$VERSION already installed"; return 0
  fi
  say "Downloading GENORYN v$VERSION (official GitHub release)..."
  curl -fL# --retry 3 --connect-timeout 20 -o "$zip" "$BASE_URL/$ASSET.zip" || die "Download failed: $BASE_URL/$ASSET.zip"
  curl -fsSL --retry 3 --connect-timeout 20 -o "$sumf" "$BASE_URL/$ASSET.zip.sha256" || die "Could not download the published checksum."
  local actual published
  actual="$(sha256sum "$zip" | awk '{print $1}')"
  published="$(awk '{print $1}' "$sumf" | head -n1)"
  [ "$actual" = "$published" ] || { rm -f "$zip"; die "Checksum does not match the one published with the release. Refusing to continue."; }
  if [ -n "${EXPECTED_SHA256:-}" ]; then
    [ "$actual" = "$EXPECTED_SHA256" ] || { rm -f "$zip"; die "Archive differs from the build this script was written against (pinned hash). Refusing to continue."; }
    ok "SHA-256 matches the pinned hash and the published checksum"
  else
    warn "No pinned hash for v$VERSION; only the checksum published next to the file was checked."
    warn "Compare it yourself on the release page: $actual"
  fi
  rm -rf "$dir.tmp"; mkdir -p "$dir.tmp"
  unzip -q "$zip" -d "$dir.tmp" || die "unzip failed"
  [ -d "$dir.tmp/$ASSET" ] || die "Unexpected archive layout."
  ( cd "$dir.tmp/$ASSET" && sha256sum -c SHA256SUMS --quiet ) || die "File checks inside the archive failed."
  ok "every file matches the archive's own SHA256SUMS"
  rm -rf "$dir"; mv "$dir.tmp/$ASSET" "$dir"; rm -rf "$dir.tmp"
  chmod +x "$dir"/genoryn-miner "$dir"/genoryn-wallet-cli "$dir"/genorynd 2>/dev/null
  touch "$dir/.verified"
  ln -sfn "$dir" "$BIN"
  rm -f "$zip"
  ok "installed to $dir"
}

cmd_install() {
  check_platform; ensure_deps; install_miner
  is_running && { say "Restarting the miner on the new version..."; cmd_restart; }
}

# --------------------------------- wallet ------------------------------------
parse_json_field() { python3 -I -c 'import sys,json;print(json.load(sys.stdin)[sys.argv[1]])' "$1"; }

show_phrase() {
  local i=0 w
  printf '\n'
  for w in $1; do
    i=$((i+1)); printf '%2d. %-11s' "$i" "$w"; [ $((i % 4)) -eq 0 ] && printf '\n'
  done
  printf '\n'
}

confirm_phrase() {
  local phrase="$1" words n ans ok
  read -r -a words <<<"$phrase"
  while true; do
    ok=1
    for n in $(shuf -i 1-24 -n 3 | sort -n); do
      read -r -p "  Type word #$n from your paper copy: " ans
      ans="$(printf '%s' "$ans" | tr 'A-Z' 'a-z' | tr -d '[:space:]')"
      [ "$ans" = "${words[$((n-1))]}" ] || ok=0
    done
    [ "$ok" -eq 1 ] && return 0
    warn "That did not match. Check your paper copy against the words below."
    read -r -p "  Press Enter to show the words again..." _
    show_phrase "$phrase"
  done
}

create_wallet() {
  need_tty
  mkdir -p "$WALLET_DIR" && chmod 700 "$WALLET_DIR"
  local attempt out addr phrase check
  for attempt in 1 2 3; do
    cat <<'EOF'

 ============================  NEW WALLET  ============================
  You will be asked for a wallet password ONCE (it cannot be shown again).
   - at least 12 characters and not guessable: use 4+ random words
   - it encrypts the wallet file on this machine; no one can reset it
  Then 24 recovery words appear. They ARE your money. Write them on paper,
  never type them anywhere else, never screenshot them.
 =======================================================================
EOF
    out="$("$BIN/genoryn-wallet-cli" --network mainnet --wallet "$WALLET_FILE" create)" || { unset out; die "Wallet creation failed."; }
    addr="$(printf '%s' "$out" | parse_json_field address)"
    phrase="$(printf '%s' "$out" | parse_json_field seed_phrase)"
    unset out
    [ -n "$addr" ] && [ -n "$phrase" ] || die "Unexpected wallet output."

    say; say "YOUR 24 RECOVERY WORDS (write them down in order):"
    show_phrase "$phrase"
    say "Anyone with these words can take your coins. Nobody can recover them for you."
    read -r -p "Press Enter when they are written down, then you will be quizzed on 3 of them..." _
    clear_screen_and_scrollback
    say "Recovery check: type the requested words from your PAPER copy."
    confirm_phrase "$phrase"
    unset phrase
    clear_screen_and_scrollback

    say "Re-enter the same wallet password to confirm it was typed correctly."
    check="$("$BIN/genoryn-wallet-cli" --network mainnet --wallet "$WALLET_FILE" address 2>/dev/null | parse_json_field address 2>/dev/null)"
    if [ "$check" = "$addr" ]; then
      printf '%s\n' "$addr" > "$ADDR_FILE"
      ok "Wallet created and password verified."
      say "  Receiving address: $addr"
      return 0
    fi
    warn "Password check failed (typo at creation?). This brand-new wallet is empty, so it is being discarded and recreated."
    rm -f "$WALLET_FILE" "${WALLET_FILE%.*}.scan" "$WALLET_DIR"/*.scan 2>/dev/null
  done
  die "Could not create a verified wallet after 3 tries."
}

ensure_wallet() {
  if wallet_exists; then
    if [ ! -s "$ADDR_FILE" ]; then
      need_tty
      say "Wallet found at $WALLET_FILE. Enter its password once to read the receiving address."
      local out a
      out="$("$BIN/genoryn-wallet-cli" --network mainnet --wallet "$WALLET_FILE" address)" || die "Could not open the wallet."
      a="$(printf '%s' "$out" | parse_json_field address)"
      [ -n "$a" ] || die "Could not read the address."
      mkdir -p "$APP_DIR"; printf '%s\n' "$a" > "$ADDR_FILE"
    fi
    ok "wallet: $(address)"
  else
    create_wallet
  fi
}

# --------------------------- sizing (threads / RAM) --------------------------
size_miner() {
  local cpus mem_mb t light_t max
  cpus="$(nproc 2>/dev/null || echo 1)"
  mem_mb="$(awk '/MemAvailable/ {printf "%d", $2/1024}' /proc/meminfo 2>/dev/null)"; mem_mb="${mem_mb:-1024}"
  t="${GNR_THREADS:-$cpus}"
  case "$t" in ''|*[!0-9]*) t="$cpus" ;; esac
  [ "$t" -ge 1 ] || t=1
  light_t=$(( t < 16 ? t : 16 ))
  MODE="light"
  if [ "$mem_mb" -ge $(( 2400 + 256 * light_t )) ]; then
    MODE="auto"                          # one shared ~2 GiB dataset: several times faster
  else
    max=$(( (mem_mb - 300) / 256 ))
    [ "$max" -ge 1 ] || die "Only ${mem_mb} MiB RAM free; the miner needs at least ~600 MiB."
    [ "$t" -gt "$max" ] && t="$max"
    [ "$t" -gt 16 ] && t=16
  fi
  THREADS="$t"
  WORKER="${GNR_WORKER:-$(hostname -s 2>/dev/null | tr -cd 'A-Za-z0-9' | cut -c1-24)}"
  WORKER="${WORKER:-rig1}"
}

# ------------------------------ start / stop ---------------------------------
write_runner() {
  local addr="$1"
  cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
# generated by genoryn-mine.sh - do not edit (rewritten at every start)
cd "$APP_DIR" || exit 1
rotate() {
  if [ -f "$LOG" ] && [ "\$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 52428800 ]; then
    tail -c 5242880 "$LOG" > "$LOG.tmp" && cat "$LOG.tmp" > "$LOG"; rm -f "$LOG.tmp"
  fi
}
( while sleep 1800; do rotate; done ) &
trap 'kill 0' EXIT TERM INT
while true; do
  rotate
  echo "[\$(date -u +%FT%TZ)] starting genoryn-miner (threads=$THREADS mode=$MODE worker=$WORKER)"
  nice -n 10 "$BIN/genoryn-miner" --network mainnet --pool "$POOL" --wallet "$addr" \\
      --worker "$WORKER" --threads $THREADS --randomx-mode $MODE
  echo "[\$(date -u +%FT%TZ)] miner exited (code \$?), restarting in 15s"
  sleep 15
done
EOF
  chmod 700 "$RUNNER"
}

cmd_start() {
  installed || die "Not installed yet. Run:  bash $0 setup"
  address >/dev/null || die "No wallet address yet. Run:  bash $0 setup"
  is_running && { say "Already running (PID $(cat "$PIDF"))."; return 0; }
  size_miner
  local host port; host="${POOL#*://}"; port="${host##*:}"; host="${host%:*}"
  timeout 8 bash -c "exec 3<>/dev/tcp/$host/$port" 2>/dev/null || warn "Cannot reach the pool at $host:$port right now; the miner will keep retrying."
  write_runner "$(address)"
  setsid nohup bash "$RUNNER" >> "$LOG" 2>&1 < /dev/null &
  echo $! > "$PIDF"
  sleep 2
  if is_running; then
    ok "mining started: $THREADS thread(s), RandomX $MODE mode, worker '$WORKER'"
    say "  Hashrate appears after ~1-2 minutes (full mode builds a 2 GiB dataset first)."
  else
    die "Miner did not stay up. See:  tail -n 30 $LOG"
  fi
}

cmd_stop() {
  if is_running; then
    local p g; p="$(cat "$PIDF")"; g="$(ps -o pgid= -p "$p" 2>/dev/null | tr -d ' ')"
    if [ -n "$g" ] && [ "$g" = "$p" ]; then kill -TERM -- "-$g" 2>/dev/null; else pkill -TERM -P "$p" 2>/dev/null; kill -TERM "$p" 2>/dev/null; fi
    sleep 2
    kill -0 "$p" 2>/dev/null && { [ -n "$g" ] && kill -KILL -- "-$g" 2>/dev/null; kill -KILL "$p" 2>/dev/null; }
    rm -f "$PIDF"; ok "stopped"
  else
    rm -f "$PIDF"; say "Not running."
  fi
}
cmd_restart() { cmd_stop; cmd_start; }

# ------------------------------ status / logs --------------------------------
render_stats() { # stdin: one pool_mining JSON line
  python3 -I -c '
import sys,json
d=json.loads(sys.stdin.read())
def f(k,fmt="{}"):
    v=d.get(k); return "-" if v is None else fmt.format(v)
print("  Hashrate        : "+f("hashrate_hs","{:.1f}")+" H/s  (average since this miner start)")
print("  Accepted shares : "+f("accepted_shares")+"   rejected: "+f("rejected_shares"))
print("  Accepted work   : "+f("accepted_work"))
print("  Block candidates: "+f("block_candidates"))
print("  Chain height    : "+f("height")+"   network difficulty: "+f("network_difficulty"))
print("  RandomX mode    : "+f("randomx_mode")+"   threads: "+f("threads"))
if d.get("last_reject"): print("  Last reject     : "+str(d["last_reject"]))
'
}

cmd_status() {
  say "================ GENORYN miner status ================"
  if is_running; then
    local p; p="$(cat "$PIDF")"
    say "  State           : RUNNING (PID $p, up $(ps -o etime= -p "$p" 2>/dev/null | tr -d ' '))"
  else
    say "  State           : STOPPED"
  fi
  say "  Pool            : $POOL"
  say "  Address         : $(address || echo 'not created yet')"
  installed && say "  Version         : $(basename "$(readlink -f "$BIN")")"
  local last=""
  [ -f "$LOG" ] && last="$(grep -a '"event":"pool_mining"' "$LOG" 2>/dev/null | tail -n1)"
  if [ -n "$last" ]; then render_stats <<<"$last"; else say "  (no stats yet - the first report arrives after the first pool job)"; fi
  if [ -f "$LOG" ]; then
    say "  --- last log lines ---"
    tail -n 6 "$LOG" | cut -c1-200 | sed 's/^/  /'
  fi
  say "  Pool stats page : $POOL_PAGE  (paste your address under 'My stats')"
}

cmd_logs() {
  [ -f "$LOG" ] || { say "No log yet."; return; }
  say "Live log - press Ctrl+C to leave."
  tail -n 30 -f "$LOG"
}

cmd_mined() {
  [ -f "$LOG" ] || { say "No log yet - start the miner first."; return; }
  say "================ How much has been mined ================"
  python3 -I - "$LOG" <<'PY'
import sys,json
tot=dict(a=0,r=0,w=0,b=0); cur=None; runs=0
def flush():
    global cur
    if cur:
        tot["a"]+=cur.get("accepted_shares",0); tot["r"]+=cur.get("rejected_shares",0)
        tot["w"]+=cur.get("accepted_work",0);   tot["b"]+=cur.get("block_candidates",0)
    cur=None
for line in open(sys.argv[1],errors="replace"):
    if "starting genoryn-miner" in line:
        flush(); runs+=1
    elif '"event":"pool_mining"' in line:
        try: cur=json.loads(line)
        except ValueError: pass
last=cur
flush()
if last:
    print("  This run     : %s accepted / %s rejected shares, accepted work %s"%(last.get("accepted_shares",0),last.get("rejected_shares",0),last.get("accepted_work",0)))
print("  In this log  : %s accepted / %s rejected shares across %s start(s), %s block candidate(s)"%(tot["a"],tot["r"],runs,tot["b"]))
PY
  cat <<EOF

  What this means:
   - An accepted share is verified WORK the pool recorded for you. It is not a coin yet.
   - You earn only when the pool finds a block; the reward is credited after 60
     confirmations (~1 hour), shared by work (PPLNS, 3% pool fee).
   - AriaPool pays automatically every hour once your balance reaches 1 GNR.
   - Your pending balance and payments: $POOL_PAGE  -> "My stats" -> paste
     $(address || echo '<your address>')
   - Coins that already arrived in your wallet:  bash $0 balance
EOF
}

cmd_balance() {
  installed || die "Not installed yet."
  wallet_exists || die "No wallet yet. Run:  bash $0 setup"
  need_tty
  say "Checking your wallet (the first check syncs the chain over Tor and can take a few minutes)."
  local out
  out="$("$BIN/genoryn-wallet-cli" --network mainnet --wallet "$WALLET_FILE" balance)" || die "Balance check failed (wrong password, or no node reachable)."
  printf '%s' "$out" | python3 -I -c '
import sys,json
d=json.loads(sys.stdin.read())
def gnr(v):
    v=int(v); s="%d.%012d"%(v//10**12, v%10**12); return s.rstrip("0").rstrip(".") or "0"
print("")
for k in sorted(d):
    v=d[k]
    if k.endswith("_atomic") and isinstance(v,(str,int)) and str(v).isdigit():
        print("  %-28s %s GNR"%(k[:-7].replace("_"," "),gnr(v)))
for k in ("height","spendable_notes","stale","mode"):
    if k in d: print("  %-28s %s"%(k.replace("_"," "),d[k]))
print("")
print("  Pool payouts show up here only after the pool pays them (hourly, 1 GNR minimum).")
'
}

cmd_address() { address || say "No address yet. Run: bash $0 setup"; }

# ------------------------- phrase / backup / autostart -----------------------
cmd_phrase() {
  installed || die "Not installed yet."
  wallet_exists || die "No wallet yet."
  need_tty
  say "The 24 recovery words will be shown after you enter the wallet password."
  "$BIN/genoryn-wallet-cli" --network mainnet --wallet "$WALLET_FILE" recovery-phrase || die "Could not show the phrase."
  echo; read -r -p "Press Enter to clear the screen..." _
  clear_screen_and_scrollback
}

cmd_backup() {
  wallet_exists || die "No wallet file at $WALLET_FILE"
  mkdir -p "$BACKUP_DIR" && chmod 700 "$BACKUP_DIR"
  local out; out="$BACKUP_DIR/wallet-$(date +%Y%m%d-%H%M%S).gnr"
  cp "$WALLET_FILE" "$out" && chmod 600 "$out"
  ok "encrypted wallet copied to $out"
  say "  sha256: $(sha256sum "$out" | awk '{print $1}')"
  cat <<EOF

  Next steps (a backup on this same VM is NOT a backup):
   1. Download it: in Termius open SFTP and copy  $out  to your computer,
      or:  scp $(id -un)@<VM-IP>:$out .
   2. Keep a copy offline (USB / encrypted storage).
   3. The file is useless without your password, and the 24 words restore the
      wallet even if the file is lost:  bash $0 phrase
EOF
}

autostart_on() {
  command -v crontab >/dev/null 2>&1 || { warn "cron is not installed (sudo apt-get install cron); autostart skipped."; return 1; }
  local self="$APP_DIR/genoryn-mine.sh"
  [ -f "$self" ] || cp "$0" "$self" 2>/dev/null
  chmod 700 "$self" 2>/dev/null
  ( crontab -l 2>/dev/null | grep -v "$CRON_TAG"
    echo "@reboot sleep 30 && /usr/bin/env bash $self start >> $APP_DIR/boot.log 2>&1 # $CRON_TAG" ) | crontab -
  ok "auto-start on reboot enabled   (turn off: bash $0 autostart-off)"
}
autostart_off() {
  command -v crontab >/dev/null 2>&1 || return 0
  crontab -l 2>/dev/null | grep -v "$CRON_TAG" | crontab - 2>/dev/null
  ok "auto-start on reboot disabled"
}

# ---------------------------------- update -----------------------------------
cmd_update() {
  local latest
  latest="$(curl -fsSL --max-time 20 "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null | python3 -I -c 'import sys,json;print(json.load(sys.stdin)["tag_name"])' 2>/dev/null)"
  say "Installed: v$(basename "$(readlink -f "$BIN" 2>/dev/null)" | sed 's/^genoryn-//; s/-mainnet.*//')"
  if [ -z "$latest" ]; then warn "Could not read the latest release from GitHub."; return 1; fi
  say "Latest release on GitHub: $latest"
  if [ "${latest#v}" = "$VERSION" ] && installed; then ok "up to date"; return 0; fi
  cat <<EOF

  A different release exists. Read its notes first:
    https://github.com/$REPO/releases/tag/$latest
  This script only auto-trusts the build it was written against. To install another
  release, copy its SHA-256 from the release page and run:
    GNR_VERSION=${latest#v} GNR_SHA256=<hash from the release page> bash $0 install
EOF
}

# --------------------------------- uninstall ---------------------------------
cmd_uninstall() {
  cat <<EOF
This stops the miner and deletes the program, logs and settings in:
  $APP_DIR
It does NOT delete your wallet ($WALLET_FILE) or your backups ($BACKUP_DIR).
Make sure your 24 words are on paper before you ever delete the wallet yourself.
EOF
  read -r -p "Type UNINSTALL to continue: " c
  [ "$c" = "UNINSTALL" ] || { say "Cancelled."; return; }
  cmd_stop
  autostart_off >/dev/null
  case "$APP_DIR" in ""|"/"|"$HOME") die "Refusing to delete '$APP_DIR'." ;; esac
  rm -rf "$APP_DIR"
  ok "removed $APP_DIR"
  say "  Wallet kept: $WALLET_FILE"
  say "  Backups kept: $BACKUP_DIR"
}

# ----------------------------------- setup -----------------------------------
cmd_setup() {
  check_platform
  ensure_deps
  cat <<'EOF'

 NOTICE
  - Google Cloud's Free Trial terms forbid mining during the trial. Do not run this
    on a trial account; on a paid VM, compare the VM cost with what you earn.
  - GENORYN is new and not independently audited: mine or hold only what you can lose.
  - Pool mining is custodial: AriaPool holds rewards until it pays them out.

EOF
  install_miner
  ensure_wallet
  cmd_start
  autostart_on
  mkdir -p "$APP_DIR"; [ -f "$APP_DIR/genoryn-mine.sh" ] || cp "$0" "$APP_DIR/genoryn-mine.sh" 2>/dev/null
  echo
  cmd_status
  cat <<EOF

  All set. Handy commands:
    bash $0 status      bash $0 logs      bash $0 mined     bash $0 balance
    bash $0 backup      bash $0 stop      bash $0 uninstall
EOF
}

# ------------------------------------ menu -----------------------------------
menu() {
  while true; do
    clear
    echo "================= GENORYN (GNR) MINER ================="
    if is_running; then echo " State: RUNNING"; else echo " State: STOPPED"; fi
    echo "-------------------------------------------------------"
    echo "  1) Status                 7) Show recovery phrase"
    echo "  2) Live logs              8) Backup wallet"
    echo "  3) How much mined         9) Start"
    echo "  4) Wallet balance        10) Stop"
    echo "  5) Show my address       11) Restart"
    echo "  6) Check for updates     12) Auto-start on/off"
    echo "                           13) Uninstall"
    echo "  0) Exit"
    read -r -p "Choose: " ch
    case "$ch" in
      1) cmd_status; pause ;;   2) cmd_logs ;;            3) cmd_mined; pause ;;
      4) cmd_balance; pause ;;  5) cmd_address; pause ;;  6) cmd_update; pause ;;
      7) cmd_phrase ;;          8) cmd_backup; pause ;;   9) cmd_start; pause ;;
      10) cmd_stop; pause ;;    11) cmd_restart; pause ;;
      12) read -r -p "  on or off? " o; if [ "$o" = "on" ]; then autostart_on; else autostart_off; fi; pause ;;
      13) cmd_uninstall; pause ;;
      0) exit 0 ;;              *) echo "Invalid choice"; sleep 1 ;;
    esac
  done
}

main() {
  local cmd="${1:-auto}"
  case "$cmd" in
    setup)          cmd_setup ;;
    install)        cmd_install ;;
    start)          cmd_start ;;
    stop)           cmd_stop ;;
    restart)        cmd_restart ;;
    status)         cmd_status ;;
    logs)           cmd_logs ;;
    mined)          cmd_mined ;;
    balance)        cmd_balance ;;
    address)        cmd_address ;;
    phrase)         cmd_phrase ;;
    backup)         cmd_backup ;;
    autostart-on)   autostart_on ;;
    autostart-off)  autostart_off ;;
    update)         cmd_update ;;
    uninstall)      cmd_uninstall ;;
    auto|menu)      if installed && wallet_exists && [ -s "$ADDR_FILE" ]; then menu; else cmd_setup; pause; menu; fi ;;
    -h|--help|help) sed -n '2,17p' "$0" ;;
    *)              die "Unknown command '$cmd'. Try:  bash $0 help" ;;
  esac
}
main "$@"
