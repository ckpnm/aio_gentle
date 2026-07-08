#!/bin/bash

# ==========================================
# FAIL2BAN
# ==========================================
step_fail2ban_setup() {
    draw_sub_header "Установка Fail2Ban"
    _do_fail2ban() {
        bash <(curl -sL https://raw.githubusercontent.com/Zover1337/Fail2Ban-AUTO/refs/heads/main/fail2ban-install.sh)
    }
    run_task "Инсталляция защитного скрипта Fail2Ban" "_do_fail2ban"
}

# ==========================================
# TRAFFIC GUARD
# ==========================================
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

# ==========================================
# БЛОКИРОВКА LEASEWEB & HE (АНТИ БОТНЕТ)
# ==========================================
step_block_asn() {
    draw_sub_header "Блокировка Leaseweb & HE"
    _do_block_asn() {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y ipset iptables-persistent whois curl >/dev/null 2>&1

cat << 'EOF_ASN' > /usr/local/bin/block_leaseweb.sh
#!/bin/bash
ASNS=("AS16265" "AS60781" "AS28753" "AS30633" "AS38731" "AS49367" "AS51395" "AS50673" "AS59253" "AS133752" "AS134351" "AS6939")
ipset create leaseweb_v4 hash:net family inet hashsize 4096 maxelem 131072 2>/dev/null
ipset create tmp_v4 hash:net family inet hashsize 4096 maxelem 131072 2>/dev/null
ipset flush tmp_v4
for ASN in "${ASNS[@]}"; do
    whois -h whois.radb.net -- "-i origin $ASN" | grep -E '^route:' | awk '{print $2}' | while read -r ip; do ipset add tmp_v4 $ip -quiet; done
done
ipset swap leaseweb_v4 tmp_v4
ipset destroy tmp_v4
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

        systemctl daemon-reload >/dev/null 2>&1
        systemctl enable ipset-persistent >/dev/null 2>&1

        /usr/local/bin/block_leaseweb.sh

        iptables -D INPUT -m set --match-set leaseweb_v4 src -j DROP 2>/dev/null || true
        iptables -D OUTPUT -m set --match-set leaseweb_v4 dst -j DROP 2>/dev/null || true
        iptables -D FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP 2>/dev/null || true

        iptables -I INPUT -m set --match-set leaseweb_v4 src -j DROP
        iptables -I OUTPUT -m set --match-set leaseweb_v4 dst -j DROP
        iptables -I FORWARD -m set --match-set leaseweb_v4 src,dst -j DROP

        netfilter-persistent save >/dev/null 2>&1

        (crontab -l 2>/dev/null | grep -v "block_leaseweb.sh"; echo "0 3 * * 1 /usr/local/bin/block_leaseweb.sh && netfilter-persistent save > /dev/null 2>&1") | crontab -
    }
    run_task "Настройка ipset, iptables и cron (AS6939+)" "_do_block_asn"
}

# ==========================================
# БЛОКИРОВКА ГРЧЦ (IP参PТаблицы Lorrr)
# ==========================================
step_block_custom_list() {
    draw_sub_header "Блокировка ГРЧЦ (Auto IPTables)"
    
    _do_block_lorrr() {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y ipset iptables-persistent curl >/dev/null 2>&1

        # Создаем бронебойный скрипт обновления на базе ipset restore (работает мгновенно и без Python)
cat << 'EOF_LORRR' > /usr/local/bin/update_lorrr.sh
#!/bin/bash
LIST_URL="https://raw.githubusercontent.com/Loorrr293/blocklist/main/blocklist.txt"
TMP_TXT="/tmp/lorrr_raw.txt"

ipset create lorrr_v4 hash:net family inet hashsize 4096 maxelem 524288 2>/dev/null || true

# Качаем список (только IPv4 для стабильности)
curl -4 -sSL "$LIST_URL" | grep -v '^#' | grep -v ':' | awk '{print $1}' | sed '/^$/d' | sort -u > "$TMP_TXT"

if [ -s "$TMP_TXT" ]; then
    {
      echo "create tmp_lorrr_v4 hash:net family inet hashsize 4096 maxelem 524288"
      echo "flush tmp_lorrr_v4"
      while read -r network; do
          echo "add tmp_lorrr_v4 $network"
      done < "$TMP_TXT"
      echo "swap lorrr_v4 tmp_lorrr_v4"
      echo "destroy tmp_lorrr_v4"
    } | ipset restore
fi
rm -f "$TMP_TXT"
EOF_LORRR

        chmod +x /usr/local/bin/update_lorrr.sh
        /usr/local/bin/update_lorrr.sh

        # Инжектим правила в iptables
        iptables -D INPUT -m set --match-set lorrr_v4 src -j DROP 2>/dev/null || true
        iptables -D OUTPUT -m set --match-set lorrr_v4 dst -j DROP 2>/dev/null || true
        iptables -D FORWARD -m set --match-set lorrr_v4 src,dst -j DROP 2>/dev/null || true

        iptables -I INPUT -m set --match-set lorrr_v4 src -j DROP
        iptables -I OUTPUT -m set --match-set lorrr_v4 dst -j DROP
        iptables -I FORWARD -m set --match-set lorrr_v4 src,dst -j DROP

        netfilter-persistent save >/dev/null 2>&1

        # Вешаем на ежедневный cron-таймер
        (crontab -l 2>/dev/null | grep -v "update_lorrr.sh"; echo "0 4 * * * /usr/local/bin/update_lorrr.sh && netfilter-persistent save > /dev/null 2>&1") | crontab -
    }
    run_task "Синхронизация списков ГРЧЦ через ipset" "_do_block_lorrr"
}
