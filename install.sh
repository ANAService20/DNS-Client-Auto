#!/usr/bin/env bash
set -euo pipefail

clear
echo "======================================="
echo "Welcome! Please join my Telegram channel:"
echo "@ANA_Service"
echo "======================================="
echo ""
echo "To run the DNS Client menu, type @ANA_Service and press Enter:"
read user_input

if [ "$user_input" != "@ANA_Service" ]; then
    echo "You did not type @ANA_Service. Exiting..."
    exit 1
fi

echo ""
echo "Setting up Termux environment..."
echo "[1/6] Updating packages..."
pkg update -y || true
pkg upgrade -y || true

echo "[2/6] Installing base packages (python, git, curl, nano)..."
pkg install -y python git curl nano || true

echo "[3/6] Ensuring pip (user) and adding ~/.local/bin to PATH..."
# termux python already provides pip; avoid reinstalling system pip
export PATH="$HOME/.local/bin:$PATH" || true

echo "[4/6] Installing Python packages (user install)..."
python -m pip install --user --upgrade pip || true
python -m pip install --user dnspython requests tqdm tabulate || true

echo "[5/6] Creating project folder ~/dns_client ..."
PROJECT_DIR="$HOME/dns_client"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

echo "[6/6] Creating scripts (dns_full_fullcheck.py and dns_run_menu.sh) ..."

# ---------------- dns_full_fullcheck.py ----------------
cat > dns_full_fullcheck.py <<'PY'
#!/usr/bin/env python3
"""
dns_full_fullcheck.py
Full DNS checker (numeric + DoH) — outputs dns_full_results.csv
Usage:
  python3 dns_full_fullcheck.py --vpn ON|OFF
"""
import dns.resolver
import requests
import time
import csv
import socket
import argparse
from tqdm import tqdm
import statistics

# CONFIG
DOMAIN = "google.com"
ATTEMPTS = 3
TIMEOUT = 5
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

NUMERIC_DNS = [
# <- full numeric list from your provided lists (kept comprehensive)
"64.6.65.6","64.6.64.6","156.154.71.2","156.154.70.2","159.250.35.251","159.250.35.250",
"208.67.220.220","208.67.222.222","37.220.84.124","1.0.0.1","1.1.1.1","199.85.127.1",
"185.231.182.126","37.152.82.112","2.17.64.0","2.17.46.25","194.36.174.161","178.22.122.100",
"10.202.10.10","10.202.10.11","185.55.226.26","185.55.225.25","85.15.1.14","85.15.1.15",
"78.157.42.101","172.29.2.100","194.104.158.48","194.104.158.78","209.244.0.3","209.244.0.4",
"185.43.135.1","185.231.182.126","156.154.70.1","156.154.71.1","149.112.112.112","149.112.112.10",
"185.108.22.133","185.108.22.134","85.214.41.206","89.15.250.41","9.9.9.9","109.69.8.51",
"8.26.56.26","8.26.247.20","185.121.177.177","169.239.202.202","46.16.216.25","185.213.182.126",
"37.152.182.112","87.135.66.81","76.76.10.4","91.239.100.100","89.233.43.71","46.224.1.221",
"46.224.1.220","208.67.220.200","208.67.222.222","74.82.42.42","0.0.0.0","8.8.8.8","8.8.4.4",
"4.2.2.4","195.46.39.39","195.46.39.40","10.44.8.8","199.85.127.10","199.85.126.10",
"176.10.118.132","176.10.118.133","94.187.170.2","94.187.170.3","195.235.194.7","195.235.194.8",
"45.81.37.0","45.81.37.1","192.168.11.11","192.168.12.12","172.16.16.16","10.202.10.202",
"172.16.30.30","10.202.10.102","10.10.34.34","185.51.200.2","185.51.200.10","178.22.122.100",
"78.157.42.100","76.223.113.79","76.223.86.98","13.248.236.200","13.248.221.253","75.2.69.210",
"3.33.246.91","85.203.37.1","85.203.37.2","103.86.99.100","103.86.96.100","162.252.172.57",
"149.154.159.92","194.242.2.2","194.242.2.3","194.242.2.4","194.242.2.5","194.242.2.6","194.242.2.9",
"81.218.119.11","209.88.198.133","78.47.119.102","218.67.222.222","218.67.220.220",
"80.67.169.40","80.67.169.12","199.2.252.10","204.97.212.10","195.92.195.94","195.92.195.95",
"84.200.69.80","84.200.70.40"
]

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

def main(vpn_flag):
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
    p.add_argument("--vpn", choices=["ON","OFF"], default="OFF", help="Set VPN flag for record")
    args = p.parse_args()
    main(args.vpn)
PY

# make python script executable
chmod +x dns_full_fullcheck.py

# ---------------- dns_run_menu.sh (with Back option support) ----------------
cat > dns_run_menu.sh <<'SH'
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$HOME/dns_client"
RESULTS_DIR="${PROJECT_DIR}/results"
mkdir -p "$RESULTS_DIR"
cd "$PROJECT_DIR"

if [ ! -f dns_full_fullcheck.py ]; then
  echo "Error: dns_full_fullcheck.py not found in $PROJECT_DIR"
  exit 1
fi

while true; do
  clear
  echo "======================================="
  echo "DNS Client Menu"
  echo "======================================="
  echo "Select your ISP (or 0 to exit):"
  echo "1) Hamrah Aval"
  echo "2) Irancell"
  echo "3) Shatel"
  echo "4) RighTel"
  echo "5) Mokhaberat (MCI)"
  echo "6) Other ISPs"
  echo "0) Exit"
  read -p "Choice: " isp_choice

  case "$isp_choice" in
    0) echo "Exiting..."; exit 0;;
    1) isp_name="Hamrah";;
    2) isp_name="Irancell";;
    3) isp_name="Shatel";;
    4) isp_name="RighTel";;
    5) isp_name="Mokhaberat";;
    6) isp_name="Other";;
    *) echo "Invalid choice. Press Enter to continue..."; read; continue;;
  esac

  # second menu: VPN or no VPN, with Back option
  while true; do
    clear
    echo "Selected ISP: $isp_name"
    echo "Choose test mode (or 0 to go back):"
    echo "1) Test WITHOUT VPN"
    echo "2) Test WITH VPN"
    echo "0) Back"
    read -p "Choice: " vpn_choice

    if [ "$vpn_choice" = "0" ]; then
      break
    elif [ "$vpn_choice" = "1" ]; then
      vpn_flag="OFF"
    elif [ "$vpn_choice" = "2" ]; then
      vpn_flag="ON"
      echo "If you selected VPN ON, please connect your VPN now, then press Enter to continue..."
      read -p ""
    else
      echo "Invalid choice. Press Enter to retry..."; read; continue
    fi

    echo "Starting DNS tests for $isp_name (VPN=$vpn_flag)..."
    python3 dns_full_fullcheck.py --vpn "$vpn_flag"

    ts=$(date +%Y%m%d_%H%M%S)
    outname="${isp_name}_${vpn_flag}_${ts}.csv"
    if [ -f dns_full_results.csv ]; then
      mv dns_full_results.csv "${RESULTS_DIR}/${outname}"
      echo "Results saved to: ${RESULTS_DIR}/${outname}"
    else
      echo "dns_full_results.csv not found - something went wrong."
    fi

    echo ""
    echo "Press Enter to return to main menu..."
    read -p ""
    break
  done
done
SH

chmod +x dns_run_menu.sh

echo
echo "======================================="
echo "Install complete."
echo "To start menu: cd ~/dns_client && bash dns_run_menu.sh"
echo "Results will be stored in ~/dns_client/results/"
echo "Channel: https://t.me/ANA_Service  (@ANA_Service)"
echo "======================================="
