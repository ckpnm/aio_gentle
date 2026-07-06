#!/bin/bash

step_fail2ban_setup() {
    draw_sub_header "Установка Fail2Ban"
    _do_fail2ban() {
        bash <(curl -s https://raw.githubusercontent.com/Zover1337/Fail2Ban-AUTO/refs/heads/main/fail2ban-install.sh)
    }
    run_task "Инсталляция защитного скрипта Fail2Ban" "_do_fail2ban"
}

step_traffic_guard_setup() {
    draw_sub_header "Traffic Guard"
    _do_tg() {
        curl -fsSL https://raw.githubusercontent.com/dotX12/traffic-guard/master/install.sh | bash
        traffic-guard full \
          -u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/government_networks.list \
          -u https://raw.githubusercontent.com/shadow-netlab/traffic-guard-lists/refs/heads/main/public/antiscanner.list \
          --enable-logging
    }
    run_task "Блокировка сканеров и госорганов" "_do_tg"
}

step_block_asn() {
    draw_sub_header "Блокировка Leaseweb & HE"
    _do_block_asn() {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y -qq -o=Dpkg::Use-Pty=0 ipset iptables-persistent whois curl

cat << 'EOF_ASN' > /usr/local/bin/block_leaseweb.sh
#!/bin/bash
ASNS=("AS16265" "AS60781" "AS28753" "AS30633" "AS38731" "AS49367" "AS51395" "AS50673" "AS59253" "AS133752" "AS134351" "AS6939")
ipset create leaseweb_v4 hash:net family inet hashsize 4096 maxelem 131072 2>/dev/null
ipset create leaseweb_v6 hash:net family inet6 hashsize 4096 maxelem 131072 2>/dev/null
ipset create tmp_v4 hash:net family inet hashsize 4096 maxelem 131072 2>/dev/null
ipset flush tmp_v4
ipset create tmp_v6 hash:net family inet6 hashsize 4096 maxelem 131072 2>/dev/null
ipset flush tmp_v6
for ASN in "${ASNS[@]}"; do
    whois -h whois.radb.net -- "-i origin $ASN" | grep -E '^route:' | awk '{print $2}' | while read -r ip; do ipset add tmp_v4 $ip -quiet; done
    whois -h whois.radb.net -- "-i origin $ASN" | grep -E '^route6:' | awk '{print $2}' | while read -r ip; do ipset add tmp_v6 $ip -quiet; done
done
ipset swap leaseweb_v4 tmp_v4
ipset swap leaseweb_v6 tmp_v6
ipset destroy tmp_v4
ipset destroy tmp_v6
ipset save > /etc/ipset.conf
EOF_ASN

        chmod +x /usr/local/bin/block_leaseweb.sh

cat << 'EOF_SRV' > /etc/systemd/system/ipset-persistent.service
[Unit]
Description=Restore ipset sets before iptables
Before=network.target netfilter-persistent.service
ConditionFileNotEmpty=/etc/ipset.conf
[Service]
Type=oneshot
ExecStart=/sbin/ipset restore -file /etc/ipset.conf
ExecStop=/sbin/ipset save -file /etc/ipset.conf
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF_SRV

        systemctl daemon-reload
        systemctl enable ipset-persistent

        /usr/local/bin/block_leaseweb.sh

        iptables -D INPUT -m set --match-set leaseweb_v4 src -j DROP 2>/dev/null || true
        iptables -D OUTPUT -m set --match-set leaseweb_v4 dst -j DROP 2>/dev/null || true
        iptables -D FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP 2>/dev/null || true
        ip6tables -D INPUT -m set --match-set leaseweb_v6 src -j DROP 2>/dev/null || true
        ip6tables -D OUTPUT -m set --match-set leaseweb_v6 dst -j DROP 2>/dev/null || true
        ip6tables -D FORWARD -m set --match-set leaseweb_v6 src,dst -j DROP 2>/dev/null || true

        iptables -I INPUT -m set --match-set leaseweb_v4 src -j DROP
        iptables -I OUTPUT -m set --match-set leaseweb_v4 dst -j DROP
        iptables -I FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP
        ip6tables -I INPUT -m set --match-set leaseweb_v6 src -j DROP
        ip6tables -I OUTPUT -m set --match-set leaseweb_v6 dst -j DROP
        ip6tables -I FORWARD -m set --match-set leaseweb_v6 src,dst -j DROP

        netfilter-persistent save

        (crontab -l 2>/dev/null | grep -v "block_leaseweb.sh"; echo "0 3 * * 1 /usr/local/bin/block_leaseweb.sh && netfilter-persistent save > /dev/null 2>&1") | crontab -
    }
    run_task "Настройка ipset, iptables и cron (AS6939+)" "_do_block_asn"
    
    local count_v4 count_v6
    count_v4=$(ipset list leaseweb_v4 2>/dev/null | grep -c '/')
    count_v6=$(ipset list leaseweb_v6 2>/dev/null | grep -c '/')
    echo -e "  ${C_OK}[ ИНФО ]${C_BASE} Забанено ${count_v4} IPv4 и ${count_v6} IPv6 подсетей."
}

step_block_custom_list() {
    draw_sub_header "Блокировка по URL (nftables)"
    _do_block_nft() {
        export DEBIAN_FRONTEND=noninteractive
        LIST_URL="https://raw.githubusercontent.com/Loorrr293/blocklist/main/blocklist.txt"

        apt-get update -y
        apt-get install -y nftables curl python3

cat << 'EOF_NFT' > /usr/local/sbin/update-blocklist-nft.sh
#!/usr/bin/env bash
set -euo pipefail

URL="${1:?Usage: update-blocklist-nft.sh <URL>}"

nft add table inet blocklist 2>/dev/null || true
nft add set inet blocklist v4 '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
nft add set inet blocklist v6 '{ type ipv6_addr; flags interval; }' 2>/dev/null || true

nft add chain inet blocklist input '{ type filter hook input priority raw; policy accept; }' 2>/dev/null || true
nft list chain inet blocklist input | grep -q '@v4' || nft add rule inet blocklist input ip saddr @v4 drop
nft list chain inet blocklist input | grep -q '@v6' || nft add rule inet blocklist input ip6 saddr @v6 drop

tmp="$(mktemp)"
cleaned="$(mktemp)"
v4="$(mktemp)"
v6="$(mktemp)"
nf="$(mktemp)"
trap 'rm -f "$tmp" "$cleaned" "$v4" "$v6" "$nf"' EXIT

curl -fsSL "$URL" > "$tmp"
sed 's/#.*//g' "$tmp" | tr -s ' \t\r' '\n' | sed '/^$/d' | sort -u > "$cleaned"

python3 - "$cleaned" > "$v4" <<'PY'
import sys, ipaddress
path = sys.argv[1]
nets=[]
for line in open(path,'r',encoding='utf-8',errors='ignore'):
    s=line.strip()
    if not s or ':' in s:
        continue
    try:
        nets.append(ipaddress.ip_network(s, strict=False))
    except ValueError:
        pass
collapsed = sorted(ipaddress.collapse_addresses(nets), key=lambda n:(int(n.network_address), n.prefixlen))
for n in collapsed:
    print(n.with_prefixlen)
PY

python3 - "$cleaned" > "$v6" <<'PY'
import sys, ipaddress
path = sys.argv[1]
nets=[]
for line in open(path,'r',encoding='utf-8',errors='ignore'):
    s=line.strip()
    if not s or ':' not in s:
        continue
    try:
        nets.append(ipaddress.ip_network(s, strict=False))
    except ValueError:
        pass
collapsed = sorted(ipaddress.collapse_addresses(nets), key=lambda n:(int(n.network_address), n.prefixlen))
for n in collapsed:
    print(n.with_prefixlen)
PY

{
  echo "flush set inet blocklist v4"
  echo "flush set inet blocklist v6"
  if [[ -s "$v4" ]]; then
    echo -n "add element inet blocklist v4 { "
    paste -sd, "$v4"
    echo " }"
  fi
  if [[ -s "$v6" ]]; then
    echo -n "add element inet blocklist v6 { "
    paste -sd, "$v6"
    echo " }"
  fi
} > "$nf"

nft -f "$nf"
EOF_NFT

        chmod +x /usr/local/sbin/update-blocklist-nft.sh

cat << 'EOF_UNIT' > /etc/systemd/system/blocklist-update.service
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/update-blocklist-nft.sh ${LIST_URL}
EOF_UNIT

cat << 'EOF_TIMER' > /etc/systemd/system/blocklist-update.timer
[Timer]
OnBootSec=1min
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF_TIMER

        systemctl daemon-reload
        systemctl enable --now blocklist-update.timer
        systemctl start blocklist-update.service
    }
    run_task "Настройка nftables, скриптов и systemd timer" "_do_block_nft"
}
