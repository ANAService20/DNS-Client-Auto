#!/usr/bin/env bash
set -euo pipefail

# =========================================
# DNS-Client-Auto install.sh (final)
# Put this file in your GitHub repo as install.sh
# Then run: bash <(curl -fsSL https://raw.githubusercontent.com/ANAService20/DNS-Client-Auto/main/install.sh)
# =========================================

# --- Telegram bot (put your token & chat id here) ---
BOT_TOKEN="8461715014:AAEHfDDnMV4jXgcmTkHhxqGdSlzK2psM7lc"
CHAT_ID="1827703560"

PROJECT_DIR="$HOME/dns_client"
RESULTS_DIR="$PROJECT_DIR/results"

print_banner(){
  echo "=========================================="
  echo "DNS Client Auto Installer"
  echo "Channel: @ANA_Service"
  echo "=========================================="
  echo ""
  echo "This installer will prepare Termux and then show interactive menu."
  echo "You will be asked to type: @ana_service  (exact) to enter the menu."
  echo ""
  read -p "Press Enter to start (Ctrl+C to cancel)..."
}

install_termux_packages(){
  echo "[1/6] Updating Termux packages..."
  pkg update -y || true
  pkg upgrade -y || true

  echo "[2/6] Installing base packages (python, git, curl, wget, nano)..."
  pkg install -y python git curl wget nano || true
}

ensure_python_and_pip(){
  # detect python command
  if command -v python3 >/dev/null 2>&1; then
    PY=python3
  elif command -v python >/dev/null 2>&1; then
    PY=python
  else
    echo "[!] python not found, installing..."
    pkg install -y python
    PY=python
  fi

  echo "[3/6] Ensuring pip and ~/.local/bin in PATH..."
  export PATH="$HOME/.local/bin:$PATH"
  $PY -m ensurepip --upgrade >/dev/null 2>&1 || true
  # use --user to avoid system pip issues on Termux
  $PY -m pip install --upgrade --user pip setuptools wheel >/dev/null 2>&1 || true
}

install_python_deps(){
  echo "[4/6] Installing python packages (dnspython, requests, tqdm, tabulate)..."
  # try user install
  if ! $PY -m pip install --user dnspython requests tqdm tabulate; then
    echo "[!] pip --user failed, trying system install..."
    $PY -m pip install dnspython requests tqdm tabulate
  fi
}

write_scripts(){
  echo "[5/6] Creating project folder and scripts..."
  mkdir -p "$RESULTS_DIR"
  cd "$PROJECT_DIR"

  # ---------------- dns_full_fullcheck.py ----------------
  cat > dns_full_fullcheck.py <<'PY'
#!/usr/bin/env python3
# dns_full_fullcheck.py
# Full DNS checker (numeric + DoH). Outputs dns_full_results.csv per run.

import dns.resolver
import requests
import time
import csv
import socket
import statistics
import sys
from tqdm import tqdm

# Config
DOMAIN = "google.com"
ATTEMPTS = 3
TIMEOUT = 5  # seconds
OUTPUT = "dns_full_results.csv"

def is_private_ip(s):
    try:
        socket.inet_aton(s)
        parts = s.split(".")
        if len(parts) != 4:
            return False
        a = int(parts[0]); b = int(parts[1])
        if a == 10: return True
        if a == 172 and 16 <= b <= 31: return True
        if a == 192 and b == 168: return True
        return False
    except Exception:
        return False

# Numeric DNS list: (collected from your lists)
NUMERIC_DNS = [
"64.6.65.6","64.6.64.6","156.154.71.2","156.154.70.2",
"159.250.35.251","159.250.35.250","208.67.220.220","208.67.222.222",
"37.220.84.124","1.0.0.1","1.1.1.1","199.85.127.1","185.231.182.126",
"37.152.82.112","2.17.64.0","2.17.46.25","194.36.174.161","178.22.122.100",
"10.202.10.10","10.202.10.11","185.55.226.26","185.55.225.25",
"85.15.1.14","85.15.1.15","78.157.42.101","172.29.2.100",
"194.104.158.48","194.104.158.78","209.244.0.3","209.244.0.4",
"185.43.135.1","156.154.70.1","156.154.71.1","149.112.112.112",
"149.112.112.10","185.108.22.133","185.108.22.134","85.214.41.206","89.15.250.41",
"9.9.9.9","109.69.8.51","8.26.56.26","8.26.247.20","185.121.177.177","169.239.202.202",
"46.16.216.25","185.213.182.126","37.152.182.112","87.135.66.81","76.76.10.4",
"91.239.100.100","89.233.43.71","46.224.1.221","46.224.1.220","208.67.220.200",
"74.82.42.42","0.0.0.0","8.8.8.8","8.8.4.4","4.2.2.4","195.46.39.39","195.46.39.40",
"10.44.8.8","199.85.127.10","199.85.126.10","176.10.118.132","176.10.118.133",
"94.187.170.2","94.187.170.3","195.235.194.7","195.235.194.8","45.81.37.0","45.81.37.1",
"192.168.11.11","192.168.12.12","172.16.16.16","10.202.10.202","172.16.30.30",
"10.202.10.102","10.10.34.34","185.51.200.2","185.51.200.10","178.22.122.100","78.157.42.100",
"76.223.113.79","76.223.86.98","13.248.236.200","13.248.221.253","75.2.69.210","3.33.246.91",
"85.203.37.1","85.203.37.2","103.86.99.100","103.86.96.100","162.252.172.57","149.154.159.92",
"194.242.2.2","194.242.2.3","194.242.2.4","194.242.2.5","194.242.2.6","194.242.2.9",
"81.218.119.11","209.88.198.133","78.47.119.102","218.67.222.222","218.67.220.220",
"80.67.169.40","80.67.169.12","199.2.252.10","204.97.212.10","195.92.195.94","195.92.195.95",
"84.200.69.80","84.200.70.40"
]

# DoH list (from your lists)
DOH_DNS = [
"https://ipv4-zepto-mci-1.edge.nextdns.io/dns-query",
"https://dns.controld.com/",
"https://170.176.145.150/",
"https://zepto-sto-1.edge.nextdns.io",
"https://nsc.torgues.net/dns-query",
"https://jp-kix2.doh.sb/",
"https://dns.gi.co.id/dns-query",
"https://xmission-slc-1.edge.nextdns.io/dns-query",
"https://xtom-osa-1.edge.nextdns.io/",
"https://dns.aa.net.uk/dns-query",
"https://cloudflare-dns.com/dns-query",
"https://dns.google/dns-query",
"https://dns.melalandia.tk/dns-query",
"https://dns.quad9.net/dns-query",
"https://res-acst3.absolight.net/"
]

def test_numeric_resolver(resolver_ip):
    resolver = dns.resolver.Resolver(configure=False)
    resolver.nameservers = [resolver_ip]
    resolver.timeout = TIMEOUT
    resolver.lifetime = TIMEOUT
    latencies = []
    success = 0
    last_err = ""
    for i in range(ATTEMPTS):
        t0 = time.time()
        try:
            # perform a query; use A record
            ans = resolver.resolve(DOMAIN, "A")
            dt = int((time.time() - t0) * 1000)
            latencies.append(dt)
            success += 1
        except Exception as e:
            latencies.append(None)
            last_err = str(e)
    ok = [x for x in latencies if x is not None]
    median = int(statistics.median(ok)) if ok else None
    avg = int(sum(ok)/len(ok)) if ok else None
    return {"resolver": resolver_ip, "type": "numeric", "is_private": is_private_ip(resolver_ip),
            "attempts": ATTEMPTS, "success_count": success, "median_ms": median, "avg_ms": avg, "example": last_err}

def test_doh_resolver(url):
    latencies = []
    success = 0
    last_body = ""
    headers = {"accept": "application/dns-json", "User-Agent": "dns-full-checker/1"}
    for i in range(ATTEMPTS):
        t0 = time.time()
        try:
            r = requests.get(url, params={"name": DOMAIN, "type": "A"}, headers=headers, timeout=TIMEOUT)
            dt = int((time.time() - t0) * 1000)
            latencies.append(dt)
            if r.status_code == 200:
                success += 1
                last_body = (r.text[:300]).replace("\n"," ")
            else:
                last_body = f"HTTP {r.status_code}"
        except Exception as e:
            latencies.append(None)
            last_body = str(e)
    ok = [x for x in latencies if x is not None]
    median = int(statistics.median(ok)) if ok else None
    avg = int(sum(ok)/len(ok)) if ok else None
    return {"resolver": url, "type": "doh", "is_private": False,
            "attempts": ATTEMPTS, "success_count": success, "median_ms": median, "avg_ms": avg, "example": last_body}

def main(isp, vpn_flag):
    rows = []
    print("Testing numeric resolvers...")
    for ip in tqdm(NUMERIC_DNS):
        r = test_numeric_resolver(ip)
        r["vpn"] = vpn_flag
        rows.append(r)
        if r["success_count"]>0:
            print(f"{ip} → OK | median: {r['median_ms']} ms | success {r['success_count']}/{r['attempts']}")
        else:
            print(f"{ip} → FAIL | err: {r['example']}")

    print("\nTesting DoH resolvers...")
    for u in tqdm(DOH_DNS):
        r = test_doh_resolver(u)
        r["vpn"] = vpn_flag
        rows.append(r)
        if r["success_count"]>0:
            print(f"{u} → OK | median: {r['median_ms']} ms | success {r['success_count']}/{r['attempts']}")
        else:
            print(f"{u} → FAIL | example: {r['example']}")

    header = ["resolver","type","is_private","attempts","success_count","median_ms","avg_ms","example","vpn"]
    with open(OUTPUT, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(header)
        for it in rows:
            writer.writerow([it.get(h) for h in header])

    # print summary and recommended top
    responders = [r for r in rows if r["success_count"]>0]
    scored = []
    for r in responders:
        rate = r["success_count"]/r["attempts"]
        median = r["median_ms"] if r["median_ms"] is not None else 999999
        score = rate * 1000 - median/10.0
        scored.append((score, rate, median, r))
    scored.sort(reverse=True, key=lambda x: (x[0], x[1], -x[2]))

    print("\nSummary:")
    print(f"Total tested: {len(rows)} | Responders: {len(responders)}")
    print(f"CSV saved: {OUTPUT}\n")

    if scored:
        print("Top results (score, success_rate, median_ms, resolver):")
        for sc, sr, med, r in scored[:15]:
            print(f"{sc:.1f} | {sr*100:.0f}% | {med} ms | {r['resolver']} ({r['type']})")
        best = scored[0][3]
        print("\n=> Recommended (best):", best["resolver"], "| type:", best["type"], "| median:", best["median_ms"], "ms | success:", best["success_count"], "/", best["attempts"])
    else:
        print("No responsive resolvers found.")

if __name__ == "__main__":
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument("isp", help="ISP name")
    p.add_argument("vpn", choices=["ON","OFF"], help="VPN flag")
    args = p.parse_args()
    # set constants
    ATTEMPTS = 3
    TIMEOUT = 5
    OUTPUT = "dns_full_results.csv"
    main(args.isp, args.vpn)
PY

  chmod +x dns_full_fullcheck.py

  # ---------------- dns_run_menu.sh ----------------
  cat > dns_run_menu.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

BOT_TOKEN="8461715014:AAEHfDDnMV4jXgcmTkHhxqGdSlzK2psM7lc"
CHAT_ID="1827703560"
PROJECT_DIR="$HOME/dns_client"
RESULTS_DIR="${PROJECT_DIR}/results"

mkdir -p "$RESULTS_DIR"
cd "$PROJECT_DIR"

# helper: send a file to telegram via bot token
send_file_to_telegram(){
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "File not found: $file"
    return 1
  fi
  # use curl to send document
  curl -s -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
    -F chat_id="${CHAT_ID}" \
    -F document=@"${file}" >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    echo "Sent: $(basename "$file")"
    return 0
  else
    echo "Failed to send: $(basename "$file")"
    return 2
  fi
}

# initial prompt: ask user to type @ana_service (finglish)
while true; do
  clear
  echo "======================================="
  echo "Baray Ejraye Menu Matn  @ana_service  Ra Vared Konid Va Enter Ra Bezanid"
  echo "======================================="
  read -p "Type here: " confirm
  if [[ "$confirm" == "@ana_service" || "$confirm" == "@ANA_Service" ]]; then
    break
  else
    echo "Type exactly: @ana_service"
    sleep 1
  fi
done

while true; do
  clear
  echo "======================================="
  echo "DNS Client Menu (finglish)"
  echo "======================================="
  echo "Select your ISP (or 0 to exit):"
  echo "1) Hamrah Aval"
  echo "2) Irancell"
  echo "3) Shatel"
  echo "4) RighTel"
  echo "5) MobinNet"
  echo "6) Other ISPs"
  echo "7) Hazf Natije Testha (Delete all results)"
  echo "8) Ersal Natije Testha Be Telegram (send all results)"
  echo "0) Exit"
  read -p "Choice: " isp_choice

  case "$isp_choice" in
    0) echo "Exiting..."; exit 0;;
    1) isp_name="Hamrah";;
    2) isp_name="Irancell";;
    3) isp_name="Shatel";;
    4) isp_name="RighTel";;
    5) isp_name="MobinNet";;
    6) isp_name="Other";;
    7)
      echo "Deleting all CSV results..."
      rm -f "${RESULTS_DIR}"/*.csv 2>/dev/null || true
      echo "All results deleted."
      read -p "Press Enter to continue..."
      continue
      ;;
    8)
      echo "Sending all CSV results to Telegram..."
      for f in "${RESULTS_DIR}"/*.csv; do
        [[ -f "$f" ]] || continue
        send_file_to_telegram "$f"
      done
      echo "All done. Press Enter to continue..."
      read -p ""
      continue
      ;;
    *)
      echo "Invalid choice. Press Enter to retry..."; read -p ""; continue;;
  esac

  # choose VPN mode
  while true; do
    clear
    echo "Selected ISP: $isp_name"
    echo "Choose test mode (or 0 to go back):"
    echo "1) Test WITHOUT VPN"
    echo "2) Test WITH VPN"
    echo "0) Back"
    read -p "Choice: " vpn_choice

    if [[ "$vpn_choice" == "0" ]]; then
      break
    elif [[ "$vpn_choice" == "1" ]]; then
      vpn_flag="OFF"
    elif [[ "$vpn_choice" == "2" ]]; then
      vpn_flag="ON"
      echo "If you selected VPN ON, please connect your VPN now, then press Enter to continue..."
      read -p ""
    else
      echo "Invalid choice. Press Enter to retry..."; read -p ""; continue
    fi

    echo "Starting DNS tests for $isp_name (VPN=$vpn_flag)..."

    # find python command
    if command -v python3 >/dev/null 2>&1; then
      PY=python3
    elif command -v python >/dev/null 2>&1; then
      PY=python
    else
      echo "python not found. Please install python and retry."
      exit 1
    fi

    # run test
    ${PY} dns_full_fullcheck.py "$isp_name" "$vpn_flag"

    # move output to results with timestamped name
    ts=$(date +%Y%m%d_%H%M%S)
    outname="${isp_name}_${vpn_flag}_${ts}.csv"
    if [[ -f dns_full_results.csv ]]; then
      mv dns_full_results.csv "${RESULTS_DIR}/${outname}"
      echo "Results saved to: ${RESULTS_DIR}/${outname}"
    else
      echo "dns_full_results.csv not found - something went wrong."
    fi

    echo ""
    echo "Complete Test. Please Enter And Sent to Telegram bot"
    read -p "Press Enter to send latest result to Telegram..." _enter

    # send the latest file only (the one we just moved)
    if [[ -f "${RESULTS_DIR}/${outname}" ]]; then
      send_file_to_telegram "${RESULTS_DIR}/${outname}" || echo "Send failed."
    else
      echo "Result file not found for sending."
    fi

    echo "Well done, please Enter And Back to Menu"
    read -p "Press Enter to return to menu..." _enter2

    break
  done

done
SH

  chmod +x dns_run_menu.sh

  echo ""
  echo "======================================="
  echo "Install complete."
  echo "To start menu now: bash $PROJECT_DIR/dns_run_menu.sh"
  echo "Or simply run the installer command again to re-run installer."
  echo "Results stored at: $RESULTS_DIR"
  echo "======================================="

# launch menu automatically
bash "$PROJECT_DIR/dns_run_menu.sh"
