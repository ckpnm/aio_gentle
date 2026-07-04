#!/bin/bash

export SCRIPT_VERSION="1.05"
export GITHUB_URL="https://github.com/ckpnm/aio_gentle"
export UPDATE_NEEDED=0

# Реальный путь к main.sh, даже если он запущен через симлинк
export SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" || echo "${BASH_SOURCE[0]}")")" &> /dev/null && pwd)"
export MODULES_DIR="$SCRIPT_DIR/modules"
export LOG_FILE="/var/log/aio_setup.log"

if [[ $EUID -ne 0 ]]; then
   echo -e "\e[1;31mОшибка: Скрипт должен быть запущен от имени root.\e[0m"
   exit 1
fi

echo -e "\n========================================" >> "$LOG_FILE"
echo "Запуск ΛIO VPN GENTLE UTILITY: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

# ==========================================
# ВИЗУАЛ И ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ
# ==========================================
export C_BASE='\e[0m'
export C_ACCENT='\e[1;36m' 
export C_DIM='\e[90m'      
export C_OK='\e[32m'       
export C_ERR='\e[31m'      
export C_INV='\e[7m'       
export C_WHITE='\e[97m'    
export C_BOLD='\e[1m'

cursor_off() { printf "\e[?25l"; }
cursor_on()  { printf "\e[?25h"; }
trap "cursor_on; echo; exit" SIGINT

pause() {
    cursor_off
    echo -e "\n${C_OK}Нажми любую клавишу для возврата в меню...${C_BASE}"
    read -rsn1
}

check_updates() {
    local remote_version
    remote_version=$(curl -s --max-time 3 "https://raw.githubusercontent.com/ckpnm/aio_gentle/main/main.sh?t=$RANDOM" | grep -E '^export SCRIPT_VERSION=' | awk -F'=' '{print $2}' | sed "s/['\"]//g" | tr -d '\r')
    
    if [[ -n "$remote_version" && "$remote_version" != "$SCRIPT_VERSION" ]]; then
        export UPDATE_NEEDED=1
        export REMOTE_VERSION="$remote_version"
    fi
}

draw_header() {
    local c_light="\e[38;5;51m"   
    local c_dark="\e[38;5;24m"    
    local c_white="\e[38;5;255m"  
    local c_gray="\e[38;5;244m"   
    local c_red="\e[38;5;196m"    
    local c_reset="\e[0m"         

    local ver_color="$c_white"
    [[ "$UPDATE_NEEDED" -eq 1 ]] && ver_color="$c_red"

    local total_width=37
   
    local title_text="Λ I Ø - G E N T Ł E "
    local ver_text="v${SCRIPT_VERSION}"
    local title_len=$(( ${#title_text} + ${#ver_text} ))
    local pad_left=$(( (total_width - title_len) / 2 ))
    local pad_right=$(( total_width - title_len - pad_left ))
    
    local p_l=$(printf "%${pad_left}s" "")
    local p_r=$(printf "%${pad_right}s" "")

    local sub_text="by •skrım—"
    local sub_len=${#sub_text}
    local sub_pad_left=$(( pad_left + title_len - sub_len ))
    local sub_pad_right=$(( total_width - sub_pad_left - sub_len ))
    local sp_l=$(printf "%${sub_pad_left}s" "")
    local sp_r=$(printf "%${sub_pad_right}s" "")

    echo -e "\n${c_light}╭─────────────────────────────────────╮${c_reset}"
    echo -e "${c_dark}│${c_reset}${p_l}${c_white}\e[1m${title_text}${ver_color}${ver_text}${c_reset}${c_light}${p_r}│${c_reset}"
    echo -e "${c_dark}│${c_reset}${sp_l}${c_gray}${sub_text}${c_reset}${c_light}${sp_r}│${c_reset}"
    echo -e "${c_dark}╰─────────────────────────────────────╯${c_reset}"
}

draw_sub_header() {
    local text="$1"
    local c_light="\e[38;5;51m"
    local c_dark="\e[38;5;24m"
    local c_white="\e[38;5;255m"
    local c_reset="\e[0m"

    local total_width=37
    local text_len=${#text}
    local pad_left=$(( (total_width - text_len) / 2 ))
    local pad_right=$(( total_width - text_len - pad_left ))
    
    local p_l=$(printf "%${pad_left}s" "")
    local p_r=$(printf "%${pad_right}s" "")

    echo -e "\n${c_light}╭─────────────────────────────────────╮${c_reset}"
    echo -e "${c_dark}│${c_reset}${p_l}${c_white}\e[1m${text}${c_reset}${c_light}${p_r}│${c_reset}"
    echo -e "${c_dark}╰─────────────────────────────────────╯${c_reset}\n"
}

_draw_progress() {
    local pid=$1
    local width=15; local p=0; local delay=0.1; local ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        local bar="["
        for ((i=0; i<width; i++)); do
            if [ $i -lt $p ]; then bar+="■"; else bar+="·"; fi
        done
        bar+="]"
        printf "\e[u%b%s%b" "$C_ACCENT" "$bar" "$C_BASE"
        sleep $delay
        ((ticks++))
        if [ $p -lt $((width * 6 / 10)) ]; then
            if (( ticks % 2 == 0 )); then ((p++)); fi
        elif [ $p -lt $((width * 8 / 10)) ]; then
            if (( ticks % 5 == 0 )); then ((p++)); fi
        elif [ $p -lt $((width - 1)) ]; then
            if (( ticks % 15 == 0 )); then ((p++)); fi
        fi
    done
}

export MENU_CHOICE=""
render_menu() {
    local options=("$@")
    local cur=0

    while [[ "${options[$cur]}" == ---* ]]; do ((cur++)); done
    cursor_off
    printf "\e[H\e[J"

    while true; do
        printf "\e[H"
        draw_header
        
        echo -e " ${C_WHITE}[↑↓] Навигация | [Enter] Выбрать | Алиас: ${C_ACCENT}aio_gentle${C_BASE}\e[K"
        echo -e " ${C_DIM}GitHub: ${GITHUB_URL}${C_BASE}\e[K"
        if [[ "$UPDATE_NEEDED" -eq 1 ]]; then
            echo -e " \e[31m● - Требуется обновление (Актуальный билд: v${REMOTE_VERSION})\e[0m\e[K"
        fi
        
        echo -e "\e[K"

        for i in "${!options[@]}"; do
            if [[ "${options[$i]}" == ---* ]]; then
                local clean_title="${options[$i]#--- }"
                clean_title="${clean_title% ---}"
                echo -e "  ${C_DIM}::${C_BASE} ${C_ACCENT}${C_BOLD}${clean_title}${C_BASE} ${C_DIM}::${C_BASE}\e[K"
            elif [ "$i" -eq "$cur" ]; then
                echo -e "  ${C_ACCENT}● [ ${options[$i]} ]${C_BASE}\e[K"
            else
                echo -e "      ${C_WHITE}${options[$i]}${C_BASE}\e[K"
            fi
            
            if [[ "${options[$i+1]}" == ---* ]]; then
                echo -e "\e[K"
            fi
        done
        printf "\e[J"

        if ! read -rsn3 key; then
            cursor_on; exit 1
        fi

        case "$key" in
            $'\e[A') while true; do ((cur--)); [ "$cur" -lt 0 ] && cur=$((${#options[@]} - 1)); [[ "${options[$cur]}" != ---* ]] && break; done ;;
            $'\e[B') while true; do ((cur++)); [ "$cur" -ge "${#options[@]}" ] && cur=0; [[ "${options[$cur]}" != ---* ]] && break; done ;;
            "") cursor_on; MENU_CHOICE="$cur"; return 0 ;;
        esac
    done
}

run_task() {
    local task_name=$1
    local cmd_func=$2
    cursor_off
    local text_len=${#task_name}
    local pad_len=$(( 50 - text_len ))
    [[ $pad_len -lt 1 ]] && pad_len=1
    local pad_spaces=$(printf "%${pad_len}s" "")
    
    printf "  ${C_ACCENT}${C_BOLD}%s%s${C_BASE}" "$task_name" "$pad_spaces"
    printf "\e[s"

    { eval "$cmd_func"; } >> "$LOG_FILE" 2>&1 &
    local task_pid=$!

    _draw_progress "$task_pid" &
    local bar_pid=$!

    wait $task_pid
    local exit_code=$?
    kill $bar_pid 2>/dev/null; wait $bar_pid 2>/dev/null
    printf "\e[u\e[K"

    if [ $exit_code -eq 0 ]; then
        echo -e "${C_OK}✓${C_BASE}"
    else
        echo -e "${C_ERR}[ОШИБКА]${C_BASE}"
        echo -e "  ${C_WHITE}Смотри логи: $LOG_FILE${C_BASE}"
        cursor_on; exit 1
    fi
}

safe_download() { curl -sSL "$1" > "$2"; }
check_installed() { eval "$1" >/dev/null 2>&1 && { echo -e "\n  ${C_OK}[ ИНФО ]${C_BASE} Компонент уже установлен."; return 0; } || return 1; }
wait_for_apt() { while apt-get check 2>&1 | grep -q "lock"; do sleep 5; done; }

step_update_script() {
    draw_sub_header "Обновление утилиты"
    if curl -s --max-time 10 "https://raw.githubusercontent.com/ckpnm/aio_gentle/main/main.sh" -o "$SCRIPT_DIR/main.sh"; then
        chmod +x "$SCRIPT_DIR/main.sh"
        echo -e "${C_OK}Скрипт успешно обновлен! Перезапуск...${C_BASE}"
        sleep 2
        exec bash "$SCRIPT_DIR/main.sh"
    else
        echo -e "${C_ERR}Ошибка при скачивании обновления. Проверьте подключение к сети.${C_BASE}"
        return 1
    fi
}

step_uninstall_script() {
    draw_sub_header "Удаление утилиты"
    echo -e "${C_ERR}ВНИМАНИЕ: Это действие полностью удалит AIO Gentle Utility.${C_BASE}"
    read -p "Вы уверены, что хотите удалить скрипт? (y/n): " confirm
    if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
        echo -e "Удаление файлов..."
        rm -rf "$SCRIPT_DIR"
        rm -f /usr/local/bin/aio_gentle
        echo -e "${C_OK}Скрипт удален. Выход...${C_BASE}"
        cursor_on
        exit 0
    else
        echo -e "Удаление отменено."
    fi
}

step_info() {
    draw_sub_header "Информация и Благодарности"
    echo -e "  ${C_WHITE}Огромная благодарность авторам открытых скриптов и списков,${C_BASE}"
    echo -e "  ${C_WHITE}которые были использованы или адаптированы в этой утилите:${C_BASE}\n"
    
    echo -e "  ${C_ACCENT}● Zover1337${C_BASE} — ${C_DIM}https://github.com/Zover1337${C_BASE}"
    echo -e "  ${C_ACCENT}● jaywehosl${C_BASE} — ${C_DIM}https://github.com/jaywehosl${C_BASE}"
    echo -e "  ${C_ACCENT}● Loorrr293${C_BASE} — ${C_DIM}https://github.com/Loorrr293${C_BASE}\n"
    
    echo -e "  ${C_WHITE}Также спасибо всем мейнтейнерам Xray, Remnawave и других проектов.${C_BASE}"
}

# ПОДГРУЗКА ВНЕШНИХ МОДУЛЕЙ (ЕСЛИ ОНИ ЕСТЬ)
if [ -d "$MODULES_DIR" ]; then
    while IFS= read -r -d '' f; do
        source "$f"
    done < <(find "$MODULES_DIR" -type f -name "*.sh" -print0)
fi

# ==========================================
# ИСПОЛНЯЕМЫЕ СКРИПТЫ (ФУНКЦИОНАЛ)
# ==========================================

step_base_deps() {
    draw_sub_header "Базовая подготовка"
    _do_base_deps() {
        apt-get update -y
        apt-get install -y curl ufw logrotate sudo git dnsutils
    }
    run_task "Обновление кэша пакетов и установка зависимостей" "_do_base_deps"
}

step_bbr_ipv6() {
    draw_sub_header "Оптимизация сети (BBR)"
    _do_bbr_ipv6() {
        if ! grep -q "disable_ipv6" /etc/sysctl.conf; then
            echo "net.ipv6.conf.all.disable_ipv6=1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.default.disable_ipv6=1" >> /etc/sysctl.conf
            echo "net.ipv6.conf.lo.disable_ipv6=1" >> /etc/sysctl.conf
        fi
        if ! sysctl net.ipv4.tcp_congestion_control | grep -q bbr; then
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        fi
        sysctl -p
    }
    run_task "Отключение IPv6 и активация TCP BBR тюнинга" "_do_bbr_ipv6"
}

step_ssh_port() {
    draw_sub_header "Настройка SSH порта"
    read -p "Введите новый SSH порт (по умолчанию 22, Enter для пропуска): " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    if [[ "$SSH_PORT" == "22" ]]; then
        echo -e "${C_DIM}Изменение порта пропущено.${C_BASE}"
        return 0
    fi
    _do_ssh_port() {
        if grep -q "^#Port " /etc/ssh/sshd_config || grep -q "^Port " /etc/ssh/sshd_config; then
            sed -i -E "s/^#?Port [0-9]+/Port $SSH_PORT/" /etc/ssh/sshd_config
        else
            echo "Port $SSH_PORT" >> /etc/ssh/sshd_config
        fi
        systemctl restart sshd || systemctl restart ssh
    }
    run_task "Перевод SSH демона на порт $SSH_PORT" "_do_ssh_port"
}

step_ufw_setup() {
    draw_sub_header "Брандмауэр UFW"
    read -p "Если вы меняли порт SSH, укажите его для открытия (по умолч. 22): " UFW_SSH
    UFW_SSH=${UFW_SSH:-22}
    _do_ufw() {
        ufw default deny incoming
        ufw default allow outgoing
        ufw allow 22/tcp
        ufw allow OpenSSH
        ufw allow 2222/tcp
        ufw allow 80/tcp
        ufw allow 443/tcp
        ufw allow 443/udp
        ufw allow 9443/tcp
        ufw allow 61000/tcp
        ufw allow 45876/tcp
        if [[ "$UFW_SSH" != "22" ]]; then
            ufw allow "$UFW_SSH/tcp"
        fi
        echo "y" | ufw enable
    }
    run_task "Конфигурация правил и активация UFW" "_do_ufw"
}

step_fail2ban_setup() {
    draw_sub_header "Установка Fail2Ban"
    _do_fail2ban() {
        bash <(curl -s https://raw.githubusercontent.com/Zover1337/Fail2Ban-AUTO/refs/heads/main/fail2ban-install.sh)
    }
    run_task "Инсталляция защитного скрипта Fail2Ban" "_do_fail2ban"
}

step_docker_setup() {
    draw_sub_header "Среда Docker"
    _do_docker() {
        if ! command -v docker &> /dev/null; then
            curl -fsSL https://get.docker.com | sh
            systemctl enable docker
            systemctl start docker
        fi
        if ! docker compose version &> /dev/null; then
            apt-get update -y && apt-get install -y docker-compose-plugin
        fi
    }
    run_task "Установка Docker Engine и Compose Plugin" "_do_docker"
}

step_caddy_selfsteal() {
    draw_sub_header "Caddy Selfsteal"
    read -p "Введите домен сервера (например, node.example.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then
        echo -e "${C_ERR}Ошибка: Домен не может быть пустым!${C_BASE}"
        return 1
    fi

    SERVER_IP=$(curl -s https://ipinfo.io/ip || curl -s https://api.ipify.org || curl -s https://ifconfig.me)
    DOMAIN_IP=$(dig +short A "$DOMAIN" 2>/dev/null | tail -n1)
    if [[ "$DOMAIN_IP" != "$SERVER_IP" ]]; then
        echo -e "${C_DIM}[ВНИМАНИЕ] Домен указывает на IP ($DOMAIN_IP), текущий хост: $SERVER_IP.${C_BASE}"
    fi

    _do_selfsteal() {
        printf "%s\n1\n9443\ny\n" "$DOMAIN" | bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) @ install
    }
    run_task "Генерация маскировки и запуск Caddy Selfsteal" "_do_selfsteal"
}

step_remnanode_setup() {
    draw_sub_header "Развертывание Remnanode"
    read -p "Введите SecretKey из вашей панели Remnawave: " SECRET_KEY
    if [[ -z "$SECRET_KEY" ]]; then
        echo -e "${C_ERR}Ошибка: Ключ отсутствует!${C_BASE}"
        return 1
    fi

    _do_remnanode() {
        mkdir -p /opt/remnanode
        mkdir -p /var/log/xray
        chmod 777 /var/log/xray

        echo "services:" > /opt/remnanode/docker-compose.yml
        echo "  remnanode:" >> /opt/remnanode/docker-compose.yml
        echo "    container_name: remnanode" >> /opt/remnanode/docker-compose.yml
        echo "    hostname: remnanode" >> /opt/remnanode/docker-compose.yml
        echo "    image: remnawave/node:2.7.0" >> /opt/remnanode/docker-compose.yml
        echo "    network_mode: host" >> /opt/remnanode/docker-compose.yml
        echo "    restart: always" >> /opt/remnanode/docker-compose.yml
        echo "    cap_add:" >> /opt/remnanode/docker-compose.yml
        echo "      - NET_ADMIN" >> /opt/remnanode/docker-compose.yml
        echo "    ulimits:" >> /opt/remnanode/docker-compose.yml
        echo "      nofile:" >> /opt/remnanode/docker-compose.yml
        echo "        soft: 1048576" >> /opt/remnanode/docker-compose.yml
        echo "        hard: 1048576" >> /opt/remnanode/docker-compose.yml
        echo "    environment:" >> /opt/remnanode/docker-compose.yml
        echo "      - NODE_PORT=2222" >> /opt/remnanode/docker-compose.yml
        echo "      - SECRET_KEY=${SECRET_KEY}" >> /opt/remnanode/docker-compose.yml
        echo "    volumes:" >> /opt/remnanode/docker-compose.yml
        echo "      - '/var/log/xray:/var/log/xray'" >> /opt/remnanode/docker-compose.yml
        echo "      - /etc/letsencrypt:/etc/letsencrypt:ro" >> /opt/remnanode/docker-compose.yml

        cd /opt/remnanode
        docker compose down &>/dev/null || true
        docker compose up -d
    }
    run_task "Запись docker-compose и запуск ноды" "_do_remnanode"
}

step_logrotate_xray() {
    draw_sub_header "Ротация логов Xray"
    _do_logrotate() {
        echo "/var/log/xray/*.log {" > /etc/logrotate.d/xray
        echo "      size 50M" >> /etc/logrotate.d/xray
        echo "      rotate 5" >> /etc/logrotate.d/xray
        echo "      compress" >> /etc/logrotate.d/xray
        echo "      missingok" >> /etc/logrotate.d/xray
        echo "      notifempty" >> /etc/logrotate.d/xray
        echo "      copytruncate" >> /etc/logrotate.d/xray
        echo "}" >> /etc/logrotate.d/xray
    }
    run_task "Применение конфигурации Logrotate" "_do_logrotate"
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

step_warp_setup() {
    draw_sub_header "Cloudflare WARP"
    _do_warp() {
        bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh)
    }
    run_task "Установка native-клиента WARP" "_do_warp"
}

step_speedtest() {
    draw_sub_header "Speedtest (Ookla)"
    
    _do_install_speedtest() {
        if ! command -v speedtest &> /dev/null; then
            curl -sSL "https://install.speedtest.net/app/cli/ookla-speedtest-1.2.0-linux-x86_64.tgz" -o /tmp/speedtest.tgz
            tar -zxf /tmp/speedtest.tgz -C /tmp
            mv /tmp/speedtest /usr/local/bin/speedtest
            chmod +x /usr/local/bin/speedtest
            rm -f /tmp/speedtest.tgz /tmp/speedtest.*
        fi
    }
    
    run_task "Установка Ookla Speedtest CLI" "_do_install_speedtest"
    
    echo -e "\n${C_DIM}Запуск тестирования сети...${C_BASE}\n"
    # Запускаем открыто в терминале, чтобы юзер видел анимацию загрузки
    speedtest --accept-license --accept-gdpr
    echo
}

step_show_reality() {
    draw_sub_header "Ключи Reality и Инфо"
    if ! command -v docker &> /dev/null || ! docker ps | grep -q remnanode; then
        echo -e "${C_ERR}Контейнер remnanode не найден или остановлен!${C_BASE}"
        return 1
    fi
    
    echo -e "${C_DIM}Запрос ключей из активного контейнера...${C_BASE}\n"
    XRAY_KEYS=$(docker exec remnanode xray x25519 2>/dev/null)
    
    if [[ -n "$XRAY_KEYS" ]]; then
        echo -e "${C_OK}Reality Ключи получены успешнo:${C_BASE}"
        echo -e "${C_ACCENT}$XRAY_KEYS${C_BASE}"
    else
        echo -e "${C_ERR}Не удалось сгенерировать ключи автоматически.${C_BASE}"
        echo -e "Вызовите вручную: ${C_BOLD}docker exec -it remnanode xray x25519${C_BASE}"
    fi
    echo -e "\n${C_WHITE}Инфо по подключению ноды:${C_BASE}"
    echo -e "  NODE_PORT (в панели): ${C_ACCENT}2222${C_BASE}"
    echo -e "  Директория логов:     ${C_DIM}/var/log/xray${C_BASE}"
    echo -e "  Конфигурация:         ${C_DIM}/opt/remnanode/docker-compose.yml${C_BASE}"
}

step_ipregion() {
    draw_sub_header "IP Region Check"
    echo -e "${C_DIM}Инициализация и запуск проверки IP Region...${C_BASE}\n"
    
cat << 'EOF_IPREGION' > /usr/local/bin/ipregion
#!/usr/bin/env bash

SCRIPT_NAME="ipregion.sh"
SCRIPT_URL="https://github.com/vernette/ipregion"
USER_AGENT="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
SPINNER_SERVICE_FILE=$(mktemp "${TMPDIR:-/tmp}/ipregion_spinner_XXXXXX")
DEBUG_LOG_FILE="ipregion_debug_$(date +%Y%m%d_%H%M%S)_$$.log"

SPOTIFY_API_KEY="142b583129b2df829de3656f9eb484e6"
SPOTIFY_CLIENT_ID="9a8d2f0ce77a4e248bb71fefcb557637"
NETFLIX_API_KEY="YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm"
TWITCH_CLIENT_ID="kimne78kx3ncx6brgo4mv6wki5h1ko"
CHATGPT_STATSIG_API_KEY="client-zUdXdSTygXJdzoE0sWTkP8GKTVsUMF2IRM7ShVO2JAG"
REDDIT_BASIC_ACCESS_TOKEN="b2hYcG9xclpZdWIxa2c6"
YOUTUBE_SOCS_COOKIE="CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjUwNzMwLjA1X3AwGgJlbiACGgYIgPC_xAY"
DISNEY_PLUS_API_KEY="ZGlzbmV5JmFuZHJvaWQmMS4wLjA.bkeb0m230uUhv8qrAXuNu39tbE_mD5EEhM_NAcohjyA"
DISNEY_PLUS_JSON_BODY='{"query":"\n     mutation registerDevice($registerDevice: RegisterDeviceInput!) {\n       registerDevice(registerDevice: $registerDevice) {\n         __typename\n       }\n     }\n     ","variables":{"registerDevice":{"applicationRuntime":"android","attributes":{"operatingSystem":"Android","operatingSystemVersion":"13"},"deviceFamily":"android","deviceLanguage":"en","deviceProfile":"phone","devicePlatformId":"android"}},"operationName":"registerDevice"}'

VERBOSE=false
JSON_OUTPUT=false
GROUPS_TO_SHOW="all"
CURL_TIMEOUT=5
CURL_RETRIES=1
IPV4_ONLY=false
IPV6_ONLY=false
PROXY_ADDR=""
INTERFACE_NAME=""
DEBUG=false

RESULT_JSON=""
ARR_PRIMARY=()
ARR_CUSTOM=()
ARR_CDN=()

COLOR_HEADER="1;36"
COLOR_SERVICE="1;32"
COLOR_HEART="1;31"
COLOR_URL="1;90"
COLOR_ASN="1;33"
COLOR_TABLE_HEADER="1;97"
COLOR_TABLE_VALUE="1"
COLOR_NULL="0;90"
COLOR_ERROR="1;31"
COLOR_WARN="1;33"
COLOR_INFO="1;36"
COLOR_RESET="0"

LOG_INFO="INFO"
LOG_WARN="WARNING"
LOG_ERROR="ERROR"

STATUS_NA="N/A"
STATUS_DENIED="Denied"
STATUS_RATE_LIMIT="Rate-limit"
STATUS_SERVER_ERROR="Server error"

declare -A DEPENDENCIES=(
  [jq]="jq"
  [curl]="curl"
  [column]="util-linux"
  [nslookup]="bind-utils"
)

declare -A PACKAGE_MAPPING=(
  ["apt:nslookup"]="dnsutils"
  ["apt:column"]="bsdmainutils"
  ["pacman:nslookup"]="bind"
  ["dnf:nslookup"]="bind-utils"
  ["yum:nslookup"]="bind-utils"
  ["termux:column"]="util-linux"
)

declare -A PRIMARY_SERVICES=(
  [MAXMIND]="maxmind.com|geoip.maxmind.com|/geoip/v2.1/city/me"
  [RIPE]="rdap.db.ripe.net|rdap.db.ripe.net|/ip/{ip}"
  [IPINFO_IO]="ipinfo.io|ipinfo.io|/widget/demo/{ip}"
  [IPREGISTRY]="ipregistry.co|api.ipregistry.co|/{ip}?hostname=true&key=sb69ksjcajfs4c"
  [IPAPI_CO]="ipapi.co|ipapi.co|/{ip}/json"
  [CLOUDFLARE]="cloudflare.com|speed.cloudflare.com|/meta"
  [IFCONFIG_CO]="ifconfig.co|ifconfig.co|/country-iso?ip={ip}|plain"
  [IP2LOCATION_IO]="ip2location.io|api.ip2location.io|/?ip={ip}"
  [IPLOCATION_COM]="iplocation.com|iplocation.com"
  [COUNTRY_IS]="country.is|api.country.is|/{ip}"
  [GEOAPIFY_COM]="geoapify.com|api.geoapify.com|/v1/ipinfo?&ip={ip}&apiKey=b8568cb9afc64fad861a69edbddb2658"
  [GEOJS_IO]="geojs.io|get.geojs.io|/v1/ip/country.json?ip={ip}"
  [IPAPI_IS]="ipapi.is|api.ipapi.is|/?q={ip}"
  [IPBASE_COM]="ipbase.com|api.ipbase.com|/v2/info?ip={ip}"
  [IPQUERY_IO]="ipquery.io|api.ipquery.io|/{ip}"
  [IPWHO_IS]="ipwho.is|ipwho.is|/{ip}"
  [IPAPI_COM]="ip-api.com|demo.ip-api.com|/json/{ip}?fields=countryCode"
)

PRIMARY_SERVICES_ORDER=(
  "MAXMIND"
  "RIPE"
  "IPINFO_IO"
  "CLOUDFLARE"
  "IPREGISTRY"
  "IPAPI_CO"
  "IFCONFIG_CO"
  "IP2LOCATION_IO"
  "IPLOCATION_COM"
  "COUNTRY_IS"
  "GEOAPIFY_COM"
  "GEOJS_IO"
  "IPAPI_IS"
  "IPBASE_COM"
  "IPQUERY_IO"
  "IPWHO_IS"
  "IPAPI_COM"
)

declare -A PRIMARY_SERVICES_CUSTOM_HANDLERS=(
  [IPLOCATION_COM]="lookup_iplocation_com"
)

declare -A SERVICE_HEADERS=(
  [IPREGISTRY]="Origin: https://ipregistry.co"
  [MAXMIND]="Referer: https://www.maxmind.com"
  [IPAPI_COM]="Origin: https://ip-api.com"
  [CLOUDFLARE]="Referer: https://speed.cloudflare.com"
)

declare -A CUSTOM_SERVICES=(
  [GOOGLE]="Google"
  [YOUTUBE]="YouTube"
  [TWITCH]="Twitch"
  [CHATGPT]="ChatGPT"
  [NETFLIX]="Netflix"
  [SPOTIFY]="Spotify"
  [REDDIT]="Reddit"
  [DISNEY_PLUS]="Disney+"
  [GEMINI_SUPPORTED]="Gemini Supported"
  [REDDIT_GUEST_ACCESS]="Reddit (Guest Access)"
  [YOUTUBE_PREMIUM]="YouTube Premium"
  [GOOGLE_SEARCH_CAPTCHA]="Google Search Captcha"
  [SPOTIFY_SIGNUP]="Spotify Signup"
  [DISNEY_PLUS_ACCESS]="Disney+ Access"
  [APPLE]="Apple"
  [STEAM]="Steam"
  [TIKTOK]="Tiktok"
  [OOKLA_SPEEDTEST]="Ookla Speedtest"
  [JETBRAINS]="JetBrains"
  [PLAYSTATION]="PlayStation"
  [MICROSOFT]="Microsoft"
)

CUSTOM_SERVICES_ORDER=(
  "GOOGLE"
  "YOUTUBE"
  "TWITCH"
  "CHATGPT"
  "NETFLIX"
  "SPOTIFY"
  "REDDIT"
  "DISNEY_PLUS"
  "GEMINI_SUPPORTED"
  "REDDIT_GUEST_ACCESS"
  "YOUTUBE_PREMIUM"
  "GOOGLE_SEARCH_CAPTCHA"
  "SPOTIFY_SIGNUP"
  "DISNEY_PLUS_ACCESS"
  "APPLE"
  "STEAM"
  "TIKTOK"
  "OOKLA_SPEEDTEST"
  "JETBRAINS"
  "PLAYSTATION"
  "MICROSOFT"
)

declare -A CUSTOM_SERVICES_HANDLERS=(
  [GOOGLE]="lookup_google"
  [YOUTUBE]="lookup_youtube"
  [GEMINI_SUPPORTED]="lookup_gemini_supported"
  [TWITCH]="lookup_twitch"
  [CHATGPT]="lookup_chatgpt"
  [NETFLIX]="lookup_netflix"
  [SPOTIFY]="lookup_spotify"
  [REDDIT]="lookup_reddit"
  [DISNEY_PLUS]="lookup_disney_plus"
  [REDDIT_GUEST_ACCESS]="lookup_reddit_guest_access"
  [YOUTUBE_PREMIUM]="lookup_youtube_premium"
  [GOOGLE_SEARCH_CAPTCHA]="lookup_google_search_captcha"
  [SPOTIFY_SIGNUP]="lookup_spotify_signup"
  [DISNEY_PLUS_ACCESS]="lookup_disney_plus_access"
  [APPLE]="lookup_apple"
  [STEAM]="lookup_steam"
  [TIKTOK]="lookup_tiktok"
  [CLOUDFLARE_CDN]="lookup_cloudflare_cdn"
  [YOUTUBE_CDN]="lookup_youtube_cdn"
  [NETFLIX_CDN]="lookup_netflix_cdn"
  [OOKLA_SPEEDTEST]="lookup_ookla_speedtest"
  [JETBRAINS]="lookup_jetbrains"
  [PLAYSTATION]="lookup_playstation"
  [MICROSOFT]="lookup_microsoft"
)

declare -A CDN_SERVICES=(
  [CLOUDFLARE_CDN]="Cloudflare CDN"
  [YOUTUBE_CDN]="YouTube CDN"
  [NETFLIX_CDN]="Netflix CDN"
)

CDN_SERVICES_ORDER=(
  "CLOUDFLARE_CDN"
  "YOUTUBE_CDN"
  "NETFLIX_CDN"
)

declare -A SERVICE_GROUPS=(
  [primary]="${PRIMARY_SERVICES_ORDER[*]}"
  [custom]="${CUSTOM_SERVICES_ORDER[*]}"
  [cdn]="${CDN_SERVICES_ORDER[*]}"
)

EXCLUDED_SERVICES=(
  "GOOGLE_SEARCH_CAPTCHA"
)

IDENTITY_SERVICES=(
  "ident.me"
  "ifconfig.me"
  "api64.ipify.org"
  "ifconfig.co"
  "ifconfig.me"
)

IPV6_OVER_IPV4_SERVICES=(
  "IPINFO_IO"
  "IPAPI_IS"
  "IPLOCATION_COM"
  "IPWHO_IS"
  "IPAPI_COM"
)

color() {
  local color_name="$1" text="$2" code
  case "$color_name" in
    HEADER) code="$COLOR_HEADER" ;;
    SERVICE) code="$COLOR_SERVICE" ;;
    HEART) code="$COLOR_HEART" ;;
    URL) code="$COLOR_URL" ;;
    ASN) code="$COLOR_ASN" ;;
    TABLE_HEADER) code="$COLOR_TABLE_HEADER" ;;
    TABLE_VALUE) code="$COLOR_TABLE_VALUE" ;;
    NULL) code="$COLOR_NULL" ;;
    ERROR) code="$COLOR_ERROR" ;;
    WARN) code="$COLOR_WARN" ;;
    INFO) code="$COLOR_INFO" ;;
    RESET) code="$COLOR_RESET" ;;
    *) code="$color_name" ;;
  esac
  printf "\033[%sm%s\033[0m" "$code" "$text"
}

bold() { printf "\033[1m%s\033[0m" "$1"; }
get_timestamp() { date +"$1"; }

log() {
  local log_level="$1" message="${*:2}" timestamp color_code
  if [[ "$VERBOSE" == true ]]; then
    timestamp=$(get_timestamp "%d.%m.%Y %H:%M:%S")
    case "$log_level" in
      "$LOG_ERROR") color_code=ERROR ;;
      "$LOG_WARN") color_code=WARN ;;
      "$LOG_INFO") color_code=INFO ;;
      *) color_code=RESET ;;
    esac
    printf "[%s] [%s]: %s\n" "$timestamp" "$(color $color_code "$log_level")" "$message" >&2
  fi
}

error_exit() {
  local message="$1" exit_code="${2:-1}"
  printf "%s %s\n" "$(color ERROR '[ERROR]')" "$(color TABLE_HEADER "$message")" >&2
  display_help
  exit "$exit_code"
}

display_help() { cat <<EOF
Usage: $SCRIPT_NAME [OPTIONS]
EOF
}

setup_debug() {
  if [[ "$DEBUG" != true ]]; then return 1; fi
  exec 3>&1 4>&2
  exec 1> >(tee -a "$DEBUG_LOG_FILE" >&3)
  exec 2> >(tee -a "$DEBUG_LOG_FILE" >&4)
  set -x
  return 0
}

grep_wrapper() {
  local grep_args=()
  if [[ "$1" == "--perl" ]]; then grep_args+=("-oP"); shift; fi
  grep "${grep_args[@]}" "$@"
}

upload_debug() {
  local ip_version=4 user_agent="ipregion-script/1.0 (github.com/vernette/ipregion)"
  curl_wrapper POST "https://0x0.st" --user-agent "$user_agent" --form "file=@$DEBUG_LOG_FILE" --form "secret=" --form "expires=24" --ip-version "$ip_version"
}

cleanup_debug() {
  local debug_url
  if [[ ! -f "$DEBUG_LOG_FILE" ]]; then return 1; fi
  set +x
  exec 1>&3 2>&4 3>&- 4>&-
  debug_url="$(upload_debug)"
  printf "\n%s\n  %s\n  %s\n\n" "$(color WARN 'Debug information:')" "Local file: $DEBUG_LOG_FILE" "Remote URL: $debug_url"
}

is_command_available() { command -v "$1" >/dev/null 2>&1; }

detect_distro() {
  if [[ -f /etc/os-release ]]; then source /etc/os-release; distro="$ID"
  elif [[ -f /etc/redhat-release ]]; then distro="rhel"
  elif [[ -d /data/data/com.termux ]]; then distro="termux"; fi
}

detect_package_manager() {
  local pkg_manager
  case "$distro" in
    ubuntu | debian | termux) pkg_manager="apt" ;;
    arch | manjaro) pkg_manager="pacman" ;;
    fedora) pkg_manager="dnf" ;;
    centos | rhel) if is_command_available "dnf"; then pkg_manager="dnf"; else pkg_manager="yum"; fi ;;
    opensuse*) pkg_manager="zypper" ;;
    alpine) pkg_manager="apk" ;;
    *) error_exit "Unknown distro: $distro" ;;
  esac
  echo "$pkg_manager"
}

get_missing_commands() {
  local missing=()
  for cmd in "${!DEPENDENCIES[@]}"; do if ! is_command_available "$cmd"; then missing+=("$cmd"); fi; done
  printf '%s\n' "${missing[@]}"
}

get_package_name() {
  local pkg_manager="$1" command="$2" mapping_key="${pkg_manager}:${command}"
  if [[ -n "${PACKAGE_MAPPING[$mapping_key]}" ]]; then echo "${PACKAGE_MAPPING[$mapping_key]}"; return; fi
  echo "${DEPENDENCIES[$command]:-$command}"
}

is_sudo_required() {
  if [[ "${EUID:-$(id -u)}" -eq 0 || "$distro" == "termux" ]]; then return 1; fi
  return 0
}

get_install_args() {
  local pkg_manager="$1" install_args
  case "$pkg_manager" in
    apt) install_args=("install" "-y") ;;
    pacman) install_args=("-Sy" "--noconfirm") ;;
    dnf | yum | zypper) install_args=("install" "-y") ;;
    apk) install_args=("add" "--no-cache") ;;
  esac
  echo "${install_args[@]}"
}

install_packages() {
  local pkg_manager="$1"
  shift
  local packages=("$@") cmd_prefix=() install_cmd=()
  if is_sudo_required; then cmd_prefix=("sudo"); fi
  cmd_prefix+=("$pkg_manager")
  if [[ "$pkg_manager" == "apt" ]]; then "${cmd_prefix[@]}" update >/dev/null 2>&1 || true; fi
  read -ra install_args <<<"$(get_install_args "$pkg_manager")"
  install_cmd+=("${cmd_prefix[@]}" "${install_args[@]}" "${packages[@]}")
  "${install_cmd[@]}" >/dev/null 2>&1 || true
}

prompt_for_installation() {
  local missing=("$@") response
  printf "\n%s\n%s " "$(color WARN 'Missing dependencies. Do you want to install them? [y/N]:')"
  read -r response
  response=${response,,}
  case "$response" in y | yes) return 0 ;; *) return 1 ;; esac
}

install_dependencies() {
  local missing_dependencies=() missing_commands pkg_manager package_name
  mapfile -t missing_commands < <(get_missing_commands)
  if [[ "${missing_commands[*]}" =~ ^[[:space:]]*$ ]]; then return 0; fi
  pkg_manager=$(detect_package_manager)
  for cmd in "${missing_commands[@]}"; do
    package_name=$(get_package_name "$pkg_manager" "$cmd")
    missing_dependencies+=("$package_name")
  done
  install_packages "$pkg_manager" "${missing_dependencies[@]}"
}

is_valid_json() { jq -e . >/dev/null 2>&1 <<<"$1"; }

process_json() {
  local json="$1" jq_filter="$2"
  if is_status_string "$json"; then echo "$json"; return; fi
  jq -r "$jq_filter" <<<"$json"
}

format_value() {
  local value="$1"
  case "$value" in
    "$STATUS_NA") color NULL "$value" ;;
    "$STATUS_DENIED" | "$STATUS_SERVER_ERROR") color ERROR "$value" ;;
    "$STATUS_RATE_LIMIT") color WARN "$value" ;;
    *) bold "$value" ;;
  esac
}

print_value_or_colored() {
  local value="$1" color_name="$2"
  if [[ "$JSON_OUTPUT" == true ]]; then echo "$value"; return; fi
  color "$color_name" "$value"
}

mask_ipv4() { echo "${1%.*.*}.*.*"; }
mask_ipv6() { echo "$1" | awk -F: '{ for(i=1;i<=NF;i++) if($i=="") $i="0"; while(NF<8) for(i=1;i<=8;i++) if($i=="0"){NF++; break;} printf "%s:%s:%s::\n", $1, $2, $3 }'; }

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help) display_help; exit 0 ;;
      -v | --verbose) VERBOSE=true; shift ;;
      -d | --debug) DEBUG=true; shift ;;
      -j | --json) JSON_OUTPUT=true; shift ;;
      -g | --group) GROUPS_TO_SHOW="$2"; shift 2 ;;
      -t | --timeout) CURL_TIMEOUT="$2"; shift 2 ;;
      -4 | --ipv4) IPV4_ONLY=true; shift ;;
      -6 | --ipv6) IPV6_ONLY=true; shift ;;
      -p | --proxy) PROXY_ADDR="$2"; shift 2 ;;
      -i | --interface) INTERFACE_NAME="$2"; shift 2 ;;
      *) error_exit "Unknown option: $1" ;;
    esac
  done
}

is_status_string() {
  case "$1" in "$STATUS_DENIED" | "$STATUS_SERVER_ERROR" | "$STATUS_RATE_LIMIT" | "$STATUS_NA") return 0 ;; *) return 1 ;; esac
}

status_from_http_code() {
  case "$1" in
    403) echo "$STATUS_DENIED" ;; 429) echo "$STATUS_RATE_LIMIT" ;; 5*) echo "$STATUS_SERVER_ERROR" ;; 4*) echo "$STATUS_NA" ;; *) echo "" ;;
  esac
}

get_ping_command() {
  local version="$1" ping_cmd
  if [[ "$version" == "4" ]]; then if is_command_available "ping"; then ping_cmd="ping"; fi
  else if is_command_available "ping6"; then ping_cmd="ping6"; elif is_command_available "ping"; then ping_cmd="ping -6"; fi; fi
  if [[ -n "$ping_cmd" ]]; then echo "$ping_cmd"; return 0; else return 1; fi
}

check_ip_interfaces() {
  if [[ -n $(ip -"$1" addr show scope global 2>/dev/null) ]]; then return 0; fi
  return 1
}

check_ip_connectivity() {
  local version="$1"
  local test_hosts_v4=("8.8.8.8" "8.8.4.4" "1.1.1.1" "1.0.0.1" "9.9.9.9")
  local test_hosts_v6=("2001:4860:4860::8888" "2001:4860:4860::8844" "2606:4700:4700::1111" "2606:4700:4700::1001" "2620:fe::9")
  local timeout=3 count=1 test_hosts ping_cmd
  ping_cmd=($(get_ping_command "$version"))
  if [[ ${#ping_cmd[@]} -eq 0 ]]; then return 1; fi
  if [[ "$version" == "4" ]]; then test_hosts=("${test_hosts_v4[@]}"); else test_hosts=("${test_hosts_v6[@]}"); fi
  for host in "${test_hosts[@]}"; do
    if "${ping_cmd[@]}" -c "$count" -W "$timeout" "$host" >/dev/null 2>&1; then return 0; fi
  done
  return 1
}

check_ip_dns() {
  local version="$1" test_domain="google.com" record_type
  if [[ "$version" == "4" ]]; then record_type="A"; else record_type="AAAA"; fi
  if nslookup -type="$record_type" "$test_domain" >/dev/null 2>&1; then return 0; fi
  return 1
}

check_ip_support() {
  local version="$1"
  local -a checks=("interfaces" "connectivity" "dns") failed=()
  spinner_update "IPv$version support"
  for check in "${checks[@]}"; do if ! "check_ip_${check}" "$version"; then failed+=("$check"); fi; done
  if [[ ${#failed[@]} -eq 0 ]]; then return 0; else return 1; fi
}

ipv4_enabled() { [[ "$IPV6_ONLY" != true ]] && [[ "$IPV4_SUPPORTED" -eq 0 ]]; }
ipv6_enabled() { [[ "$IPV4_ONLY" != true ]] && [[ "$IPV6_SUPPORTED" -eq 0 ]]; }
can_use_ipv4() { ipv4_enabled && [[ -n "$EXTERNAL_IPV4" ]]; }
can_use_ipv6() { ipv6_enabled && [[ "$IPV6_SUPPORTED" -eq 0 ]] && [[ -n "$EXTERNAL_IPV6" ]]; }
preferred_ip_version() { can_use_ipv4 && echo 4 || echo 6; }
preferred_ip() { can_use_ipv4 && echo "$EXTERNAL_IPV4" || echo "$EXTERNAL_IPV6"; }

shuffle_identity_services() {
  local i tmp size rand_idx
  size=${#IDENTITY_SERVICES[@]}
  for ((i = size - 1; i > 0; i--)); do
    rand_idx=$((RANDOM % (i + 1)))
    if ((rand_idx != i)); then tmp=${IDENTITY_SERVICES[i]}; IDENTITY_SERVICES[i]=${IDENTITY_SERVICES[rand_idx]}; IDENTITY_SERVICES[rand_idx]=$tmp; fi
  done
}

fetch_ip_from_service() {
  local response=$(curl_wrapper GET "https://$1" --ip-version "$2")
  if [[ -n "$response" ]]; then echo "$response"; fi
}

fetch_external_ip() {
  local ip_version="$1" service ip
  spinner_update "External IPv$ip_version address"
  shuffle_identity_services
  for service in "${IDENTITY_SERVICES[@]}"; do
    ip=$(fetch_ip_from_service "$service" "$ip_version")
    if [[ -n "$ip" ]]; then echo "$ip"; return; fi
  done
}

discover_external_ips() {
  if ipv4_enabled; then EXTERNAL_IPV4=$(fetch_external_ip 4); fi
  if ipv6_enabled; then EXTERNAL_IPV6=$(fetch_external_ip 6); fi
}

get_asn() {
  local ip_version=4 response traits
  spinner_update "ASN info"
  response=$(curl_wrapper GET "https://geoip.maxmind.com/geoip/v2.1/city/me" --header "Referer: https://www.maxmind.com" --ip-version "$ip_version")
  traits=$(process_json "$response" ".traits")
  asn=$(process_json "$traits" ".autonomous_system_number")
  asn_name=$(process_json "$traits" ".autonomous_system_organization")
}

get_registered_country() {
  local response=$(curl_wrapper GET "https://geoip.maxmind.com/geoip/v2.1/city/me" --header "Referer: https://www.maxmind.com" --ip-version "$1")
  process_json "$response" ".registered_country.names.en"
}

get_iata_location() {
  local response=$(curl_wrapper POST "https://www.air-port-codes.com/api/v1/single" --header "APC-Auth: 96dc04b3fb" --header "Referer: https://www.air-port-codes.com/" --data "iata=$1" --ip-version 4)
  process_json "$response" ".airport.country.iso"
}

is_ipv6_over_ipv4_service() {
  for s in "${IPV6_OVER_IPV4_SERVICES[@]}"; do [[ "$s" == "$1" ]] && return 0; done
  return 1
}

spinner_start() {
  local delay=0.1 spinstr='|/-\\' current_service
  spinner_running=true
  (
    while $spinner_running; do
      for ((i = 0; i < ${#spinstr}; i++)); do
        current_service=""
        if [[ -f "$SPINNER_SERVICE_FILE" ]]; then current_service="$(cat "$SPINNER_SERVICE_FILE")"; fi
        printf "\r\033[K%s %s %s" "$(color HEADER "${spinstr:$i:1}")" "$(color HEADER "Checking:")" "$(color SERVICE "$current_service")"
        sleep $delay
      done
    done
  ) &
  spinner_pid=$!
}

spinner_stop() {
  spinner_running=false
  if [[ -n "$spinner_pid" ]]; then kill "$spinner_pid" 2>/dev/null; wait "$spinner_pid" 2>/dev/null; spinner_pid=""; printf "\\r%*s\\r" 40 " "; fi
  if [[ -f "$SPINNER_SERVICE_FILE" ]]; then rm -f "$SPINNER_SERVICE_FILE"; unset SPINNER_SERVICE_FILE; fi
}

spinner_update() { if [[ -n "$SPINNER_SERVICE_FILE" ]]; then echo "$1" >"$SPINNER_SERVICE_FILE"; fi; }
spinner_cleanup() { spinner_stop; exit 130; }

curl_wrapper() {
  local method="$1" url="$2"
  shift 2
  local ip_version user_agent json data file forms headers response_with_code response http_code
  local curl_args=(--silent --compressed --location --retry-connrefused --retry "$CURL_RETRIES" --max-time "$CURL_TIMEOUT" -w '\n%{http_code}')
  case "$method" in HEAD) curl_args+=(--head) ;; *) curl_args+=(--request "$method") ;; esac
  while (($#)); do
    case "$1" in
      --ip-version) ip_version="$2"; shift 2 ;; --user-agent) user_agent="$2"; shift 2 ;; --header) headers+=("$2"); shift 2 ;;
      --json) json="$2"; shift 2 ;; --data) data="$2"; shift 2 ;; --file) file="$2"; shift 2 ;; --form) forms+=("$2"); shift 2 ;;
    esac
  done
  if [[ "$ip_version" == "4" ]]; then curl_args+=(-4); else curl_args+=(-6); fi
  for h in "${headers[@]}"; do curl_args+=(-H "$h"); done
  if [[ -n "$user_agent" ]]; then curl_args+=(-A "$user_agent"); fi
  if [[ -n "$json" ]]; then curl_args+=(--json "$json"); fi
  if [[ -n "$data" ]]; then curl_args+=(--data "$data"); fi
  if [[ -n "$file" ]]; then curl_args+=(--upload-file "$file"); fi
  for f in "${forms[@]}"; do curl_args+=(-F "$f"); done
  if [[ -n "$PROXY_ADDR" ]]; then curl_args+=(--proxy "socks5://$PROXY_ADDR"); fi
  if [[ -n "$INTERFACE_NAME" ]]; then curl_args+=(--interface "$INTERFACE_NAME"); fi
  curl_args+=("$url")
  response_with_code=$(curl "${curl_args[@]}")
  http_code=$(tail -n1 <<<"$response_with_code")
  response=$(head -n -1 <<<"$response_with_code")
  if [[ "$http_code" == 4* || "$http_code" == 5* ]]; then status_from_http_code "$http_code"; return 0; fi
  echo "$response"
}

service_build_request() {
  local service="$1" ip="$2" ip_version="$3"
  local cfg="${PRIMARY_SERVICES[$service]}"
  local display_name domain url_template url headers_str response_format
  
  IFS='|' read -r display_name domain url_template response_format <<<"$cfg"
  if [[ -z "$display_name" ]]; then display_name="$service"; fi
  url="https://$domain${url_template//\{ip\}/$ip}"
  if [[ -n "${SERVICE_HEADERS[$service]}" ]]; then headers_str="${SERVICE_HEADERS[$service]}"; fi
  printf "%s\n%s\n%s\n%s" "$display_name" "$url" "${response_format:-json}" "$headers_str"
}

probe_service() {
  local service="$1" ip_version="$2" ip="$3"
  local built display_name url response_format headers_line request_params response
  
  mapfile -t built < <(service_build_request "$service" "$ip" "$ip_version")
  display_name="${built[0]}"
  url="${built[1]}"
  response_format="${built[2]}"
  headers_line="${built[3]}"
  
  if [[ -n "$headers_line" ]]; then
    IFS='||' read -ra hs <<<"$headers_line"
    for h in "${hs[@]}"; do if [[ -n "$h" ]]; then request_params+=(--header "$h"); fi; done
  fi
  
  if [[ "$ip_version" == "6" ]] && is_ipv6_over_ipv4_service "$service"; then ip_version="4"; fi
  response=$(curl_wrapper GET "$url" "${request_params[@]}" --ip-version "$ip_version")
  process_response "$service" "$response" "$display_name" "$response_format"
}

process_response() {
  local service="$1" response="$2" display_name="$3" response_format="${4:-json}" jq_filter
  
  if is_status_string "$response"; then echo "$response"; return; fi
  if [[ -z "$response" || "$response" == *"<html"* ]]; then echo "$STATUS_NA"; return; fi
  if [[ "$response_format" == "plain" ]]; then echo "$response" | tr -d '\r\n '; return; fi
  if ! is_valid_json "$response"; then return 1; fi
  
  case "$service" in
    MAXMIND) jq_filter='.country.iso_code' ;; RIPE) jq_filter='.country' ;; IP2LOCATION_IO) jq_filter='.country_code' ;;
    IPINFO_IO) jq_filter='.data.country' ;; IPREGISTRY) jq_filter='.location.country.code' ;; IPAPI_CO) jq_filter='.country' ;;
    CLOUDFLARE) jq_filter='.country' ;; COUNTRY_IS) jq_filter='.country' ;; GEOAPIFY_COM) jq_filter='.country.iso_code' ;;
    GEOJS_IO) jq_filter='.[0].country' ;; IPAPI_IS) jq_filter='.location.country_code' ;; IPBASE_COM) jq_filter='.data.location.country.alpha2' ;;
    IPQUERY_IO) jq_filter='.location.country_code' ;; IPWHO_IS) jq_filter='.country_code' ;; IPAPI_COM) jq_filter='.countryCode' ;;
    *) echo "$response" ;;
  esac
  process_json "$response" "$jq_filter"
}

process_with_custom_handler() {
  local service="$1" display_name="$2"
  local handler_func="${PRIMARY_SERVICES_CUSTOM_HANDLERS[$service]}" 
  local ipv4_result="" ipv6_result=""
  
  if can_use_ipv4; then ipv4_result=$("$handler_func" 4 4); fi
  if can_use_ipv6; then
    local transport=6
    if is_ipv6_over_ipv4_service "$service"; then transport=4; fi
    ipv6_result=$("$handler_func" "$transport" 6)
  fi
  add_result "primary" "$display_name" "$ipv4_result" "$ipv6_result"
}

process_with_probe() {
  local service="$1" display_name="$2" ipv4_result="" ipv6_result=""
  if can_use_ipv4; then ipv4_result=$(probe_service "$service" 4 "$EXTERNAL_IPV4"); fi
  if can_use_ipv6; then ipv6_result=$(probe_service "$service" 6 "$EXTERNAL_IPV6"); fi
  add_result "primary" "$display_name" "$ipv4_result" "$ipv6_result"
}

process_service() {
  local service="$1" custom="${2:-false}"
  local service_config="${PRIMARY_SERVICES[$service]}"
  local display_name domain url_template response_format handler_func
  
  IFS='|' read -r display_name domain url_template response_format <<<"$service_config"
  display_name="${display_name:-$service}"
  spinner_update "$display_name"
  
  if [[ "$custom" == true ]]; then process_custom_service "$service"; return; fi
  if [[ -n "${PRIMARY_SERVICES_CUSTOM_HANDLERS[$service]}" ]]; then process_with_custom_handler "$service" "$display_name"; return; fi
  process_with_probe "$service" "$display_name"
}

process_custom_service() {
  local service="$1" ipv4_result="" ipv6_result="" display_name handler_func group
  
  if [[ -n "${CUSTOM_SERVICES[$service]}" ]]; then
    display_name="${CUSTOM_SERVICES[$service]}"; handler_func="${CUSTOM_SERVICES_HANDLERS[$service]}"; group="custom"
  elif [[ -n "${CDN_SERVICES[$service]}" ]]; then
    display_name="${CDN_SERVICES[$service]}"; handler_func="${CUSTOM_SERVICES_HANDLERS[$service]}"; group="cdn"
  else
    display_name="$service"; handler_func="${CUSTOM_SERVICES_HANDLERS[$service]}"; group="custom"
  fi
  
  spinner_update "$display_name"
  if [[ -z "$handler_func" ]]; then return; fi
  
  if can_use_ipv4; then ipv4_result=$("$handler_func" 4); fi
  if can_use_ipv6; then ipv6_result=$("$handler_func" 6); fi
  add_result "$group" "$display_name" "$ipv4_result" "$ipv6_result"
}

run_service_group() {
  local group="$1"
  local services_string="${SERVICE_GROUPS[$group]}" 
  local is_custom=false is_cdn=false services_array service_name
  
  read -ra services_array <<<"$services_string"
  for service_name in "${services_array[@]}"; do
    if printf "%s\n" "${EXCLUDED_SERVICES[@]}" | grep_wrapper -Fxq "$service_name"; then continue; fi
    case "$group" in custom) is_custom=true ;; cdn) is_cdn=true ;; esac
    
    if [[ "$is_custom" == true ]]; then process_service "$service_name" true
    elif [[ "$is_cdn" == true ]]; then process_custom_service "$service_name"
    else process_service "$service_name"
    fi
  done
}

finalize_json() {
  local t_primary t_custom t_cdn IFS=$'\n'
  if ((${#ARR_PRIMARY[@]} > 0)); then t_primary=$(printf '%s\n' "${ARR_PRIMARY[@]//|||/$'\t'}"); fi
  if ((${#ARR_CUSTOM[@]} > 0)); then t_custom=$(printf '%s\n' "${ARR_CUSTOM[@]//|||/$'\t'}"); fi
  if ((${#ARR_CDN[@]} > 0)); then t_cdn=$(printf '%s\n' "${ARR_CDN[@]//|||/$'\t'}"); fi

  RESULT_JSON=$(
    jq -n \
      --rawfile p <(printf "%s" "$t_primary") \
      --rawfile c <(printf "%s" "$t_custom") \
      --rawfile d <(printf "%s" "$t_cdn") \
      --arg ipv4 "$EXTERNAL_IPV4" \
      --arg ipv6 "$EXTERNAL_IPV6" \
      --arg version "1" '
        def lines_to_array($raw):
          if ($raw | length) == 0 then [] else
          ($raw | split("\n")) | map(select(length > 0)) | map((split("\t")) as $f | { service: $f[0], ipv4: (($f[1] // "") | if length>0 then . else null end), ipv6: (($f[2] // "") | if length>0 then . else null end) })
          end;
        { version: ($version|tonumber), ipv4: ($ipv4 | select(length > 0) // null), ipv6: ($ipv6 | select(length > 0) // null), results: { primary: lines_to_array($p), custom: lines_to_array($c), cdn: lines_to_array($d) } }
      '
  )
}

add_result() {
  local group="$1" service="$2" ipv4="$3" ipv6="$4"
  ipv4=${ipv4//$'\n'/}; ipv4=${ipv4//$'\t'/ }; ipv6=${ipv6//$'\n'/}; ipv6=${ipv6//$'\t'/ }
  case "$group" in
    primary) ARR_PRIMARY+=("$service|||$ipv4|||$ipv6") ;;
    custom) ARR_CUSTOM+=("$service|||$ipv4|||$ipv6") ;;
    cdn) ARR_CDN+=("$service|||$ipv4|||$ipv6") ;;
  esac
}

print_table_group() {
  local group="$1" group_title="$2" na="N/A" show_ipv4=0 show_ipv6=0 separator=$'\t'
  if can_use_ipv4; then show_ipv4=1; fi
  if can_use_ipv6; then show_ipv6=1; fi
  printf "%s\n\n" "$(color HEADER "$group_title")"
  {
    printf "%s" "$(color TABLE_HEADER 'Service')"
    if [[ $show_ipv4 -eq 1 ]]; then printf "%s%s" "$separator" "$(color TABLE_HEADER 'IPv4')"; fi
    if [[ $show_ipv6 -eq 1 ]]; then printf "%s%s" "$separator" "$(color TABLE_HEADER 'IPv6')"; fi
    printf "\n"
    jq -r --arg group "$group" '(.results // {}) as $r | ($r[$group] // []) | .[] | [ .service, (.ipv4 // "N/A"), (.ipv6 // "N/A") ] | @tsv' <<<"$RESULT_JSON" | while IFS=$'\t' read -r s v4 v6; do
      printf "%s" "$(color SERVICE "$s")"
      if [[ $show_ipv4 -eq 1 ]]; then
        if [[ "$v4" == "null" || -z "$v4" ]]; then v4="$na"; fi
        printf "%s%s" "$separator" "$(format_value "$v4")"
      fi
      if [[ $show_ipv6 -eq 1 ]]; then
        if [[ "$v6" == "null" || -z "$v6" ]]; then v6="$na"; fi
        printf "%s%s" "$separator" "$(format_value "$v6")"
      fi
      printf "\n"
    done
  } | column -t -s "$separator"
}

print_header() {
  local ipv4 ipv6
  ipv4=$(process_json "$RESULT_JSON" ".ipv4")
  ipv6=$(process_json "$RESULT_JSON" ".ipv6")
  printf "%s\n%s\n\n" "$(color URL "Made with ")$(color HEART "<3")$(color URL " by vernette")" "$(color URL "$SCRIPT_URL")"
  if [[ "$ipv4" != "null" ]]; then printf "%s: %s, %s %s\n" "$(color HEADER 'IPv4')" "$(bold "$(mask_ipv4 "$ipv4")")" "registered in" "$(bold "$(get_registered_country 4)")"; fi
  if [[ "$ipv6" != "null" ]]; then printf "%s: %s, %s %s\n" "$(color HEADER 'IPv6')" "$(bold "$(mask_ipv6 "$ipv6")")" "registered in" "$(bold "$(get_registered_country 6)")"; fi
  printf "%s: %s\n\n" "$(color HEADER 'ASN')" "$(bold "AS$asn $asn_name")"
}

print_results() {
  finalize_json
  if [[ "$JSON_OUTPUT" == true ]]; then echo "$RESULT_JSON" | jq; return; fi
  print_header
  case "$GROUPS_TO_SHOW" in
    primary) print_table_group "primary" "GeoIP services" ;;
    custom) print_table_group "custom" "Popular services" ;;
    cdn) print_table_group "cdn" "CDN services" ;;
    *) print_table_group "custom" "Popular services"; printf "\n"; print_table_group "cdn" "CDN services"; printf "\n"; print_table_group "primary" "GeoIP services" ;;
  esac
}

lookup_maxmind() { process_service "MAXMIND"; }
lookup_ripe() { process_service "RIPE"; }
lookup_ip2location_io() { process_service "IP2LOCATION_IO"; }
lookup_ipinfo_io() { process_service "IPINFO_IO"; }
lookup_ipregistry() { process_service "IPREGISTRY"; }
lookup_ipapi_co() { process_service "IPAPI_CO"; }
lookup_cloudflare() { process_service "CLOUDFLARE"; }
lookup_ifconfig_co() { process_service "IFCONFIG_CO"; }

lookup_iplocation_com() {
  local ip_version="$1" response ip
  ip="$(preferred_ip)"
  response=$(curl_wrapper POST "https://iplocation.com" --ip-version "$ip_version" --user-agent "$USER_AGENT" --data "ip=$ip")
  process_json "$response" ".country_code"
}

lookup_google() {
  local ip_version="$1" response
  response=$(curl_wrapper GET "https://accounts.google.com/v3/signin/identifier?flowName=GlifSetupAndroid" \
    --user-agent "$USER_AGENT" \
    --ip-version "$ip_version")
  grep_wrapper --perl 'name="region" value="\K[^"]*' <<<"$response"
}

lookup_gemini_supported() {
  local ip_version="$1" country_code country_name available color_name
  local gemini_regions_url="https://ai.google.dev/gemini-api/docs/available-regions.md.txt"
  country_code=$(lookup_google "$ip_version")
  if [[ -z "$country_code" ]]; then echo ""; return; fi
  country_name=$(curl_wrapper GET "https://www.apicountries.com/alpha/${country_code}" --ip-version "4")
  country_name=$(process_json "$country_name" ".name")
  if [[ -z "$country_name" || "$country_name" == "null" ]]; then echo ""; return; fi
  local regions_md
  regions_md=$(curl_wrapper GET "$gemini_regions_url" --ip-version "$ip_version")
  if grep_wrapper -qi "^- ${country_name}$" <<<"$regions_md"; then available="Yes"; color_name="SERVICE"; else available="No"; color_name="HEART"; fi
  print_value_or_colored "$available" "$color_name"
}

lookup_youtube() {
  local ip_version="$1" response json_result
  response=$(curl_wrapper GET "https://www.youtube.com/sw.js_data" --ip-version "$ip_version")
  json_result=$(tail -n +3 <<<"$response")
  process_json "$json_result" ".[0][2][0][0][1]"
}

lookup_twitch() {
  local ip_version="$1" response
  response=$(curl_wrapper POST "https://gql.twitch.tv/gql" \
    --header "Client-Id: $TWITCH_CLIENT_ID" \
    --json '[{"operationName":"VerifyEmail_CurrentUser","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f9e7dcdf7e99c314c82d8f7f725fab5f99d1df3d7359b53c9ae122deec590198"}}}]' \
    --ip-version "$ip_version")
  process_json "$response" ".[0].data.requestInfo.countryCode"
}

lookup_chatgpt() {
  local ip_version="$1" response
  response=$(curl_wrapper POST "https://ab.chatgpt.com/v1/initialize" --ip-version "$ip_version" \
    --header "Statsig-Api-Key: $CHATGPT_STATSIG_API_KEY")
  process_json "$response" ".derived_fields.country"
}

lookup_netflix() {
  local ip_version="$1" response
  response=$(curl_wrapper GET "https://api.fast.com/netflix/speedtest/v2?https=true&token=$NETFLIX_API_KEY&urlCount=1" --ip-version "$ip_version")
  if is_valid_json "$response"; then process_json "$response" ".client.location.country"; return; fi
  echo "$response"
}

lookup_spotify() {
  local ip_version="$1" response
  response=$(curl_wrapper GET "https://spclient.wg.spotify.com/signup/public/v1/account/?validate=1&key=$SPOTIFY_API_KEY" \
    --header "X-Client-Id: $SPOTIFY_CLIENT_ID" \
    --ip-version "$ip_version")
  process_json "$response" ".country"
}

lookup_reddit() {
  local ip_version="$1" basic_access_token="Basic $REDDIT_BASIC_ACCESS_TOKEN" user_agent="Reddit/Version 2025.29.0/Build 2529021/Android 13" response access_token
  response=$(curl_wrapper POST "https://www.reddit.com/auth/v2/oauth/access-token/loid" \
    --ip-version "$ip_version" \
    --user-agent "$user_agent" \
    --header "Authorization: $basic_access_token" \
    --json '{"scopes":["email"]}')
  access_token=$(process_json "$response" ".access_token")
  response=$(curl_wrapper POST "https://gql-fed.reddit.com" \
    --ip-version "$ip_version" \
    --user-agent "$user_agent" \
    --header "Authorization: Bearer $access_token" \
    --json '{"operationName":"UserLocation","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f07de258c54537e24d7856080f662c1b1268210251e5789c8c08f20d76cc8ab2"}}}')
  process_json "$response" ".data.userLocation.countryCode"
}

lookup_disney_plus() {
  local ip_version="$1" response
  response=$(curl_wrapper POST "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" \
    --header "Authorization: Bearer $DISNEY_PLUS_API_KEY" \
    --json "$DISNEY_PLUS_JSON_BODY" \
    --ip-version "$ip_version")
  process_json "$response" ".extensions.sdk.session.location.countryCode"
}

lookup_reddit_guest_access() {
  local ip_version="$1" response is_available color_name
  response=$(curl_wrapper GET "https://www.reddit.com" --ip-version "$ip_version" --user-agent "$USER_AGENT")
  if [[ "$response" != "Denied" ]]; then is_available="Yes"; color_name="SERVICE"; else is_available="No"; color_name="HEART"; fi
  print_value_or_colored "$is_available" "$color_name"
}

lookup_youtube_premium() {
  local ip_version="$1" response is_available
  response=$(curl_wrapper GET "https://www.youtube.com/premium" \
    --ip-version "$ip_version" \
    --user-agent "$USER_AGENT" \
    --header "Cookie: SOCS=$YOUTUBE_SOCS_COOKIE" \
    --header "Accept-Language: en-US,en;q=0.9")
  if [[ -z "$response" ]]; then echo ""; return; fi
  is_available=$(grep_wrapper -io "youtube premium is not available in your country" <<<"$response")
  if [[ -z "$is_available" ]]; then is_available="Yes"; color_name="SERVICE"; else is_available="No"; color_name="HEART"; fi
  print_value_or_colored "$is_available" "$color_name"
}

lookup_google_search_captcha() {
  local ip_version="$1" response is_captcha color_name
  response=$(curl_wrapper GET "https://www.google.com/search?q=cats" --ip-version "$ip_version" \
    --user-agent "$USER_AGENT" \
    --header "Accept-Language: en-US,en;q=0.9")
  if [[ -z "$response" ]]; then echo ""; return; fi
  is_captcha=$(grep_wrapper -iE "unusual traffic from|is blocked|unaddressed abuse" <<<"$response")
  if [[ -z "$is_captcha" ]]; then is_captcha="No"; color_name="SERVICE"; else is_captcha="Yes"; color_name="HEART"; fi
  print_value_or_colored "$is_captcha" "$color_name"
}

lookup_spotify_signup() {
  local ip_version="$1" response status is_country_launched available color_name
  response=$(curl_wrapper GET "https://spclient.wg.spotify.com/signup/public/v1/account/?validate=1&key=$SPOTIFY_API_KEY" \
    --header "X-Client-Id: $SPOTIFY_CLIENT_ID" \
    --ip-version "$ip_version")
  status=$(process_json "$response" ".status")
  is_country_launched=$(process_json "$response" ".is_country_launched")
  if [[ "$status" == "120" || "$status" == "320" || "$is_country_launched" == "false" ]]; then available="No"; color_name="HEART"; else available="Yes"; color_name="SERVICE"; fi
  print_value_or_colored "$available" "$color_name"
}

lookup_disney_plus_access() {
  local ip_version="$1" response errors_count in_supported_location is_available color_name
  response=$(curl_wrapper POST "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" \
    --header "Authorization: Bearer $DISNEY_PLUS_API_KEY" \
    --json "$DISNEY_PLUS_JSON_BODY" \
    --ip-version "$ip_version")
  errors_count=$(process_json "$response" ".errors | length")
  in_supported_location=$(process_json "$response" ".extensions.sdk.session.inSupportedLocation")
  if [[ "$errors_count" == "0" && "$in_supported_location" == "true" ]]; then is_available="Yes"; color_name="SERVICE"; else is_available="No"; color_name="HEART"; fi
  print_value_or_colored "$is_available" "$color_name"
}

lookup_apple() { curl_wrapper GET "https://gspe1-ssl.ls.apple.com/pep/gcc" --ip-version "$1"; }

lookup_steam() {
  local response=$(curl_wrapper HEAD "https://store.steampowered.com" --ip-version "$1")
  grep_wrapper --perl 'steamCountry=\K[^%;]*' <<<"$response"
}

lookup_tiktok() {
  local response=$(curl_wrapper GET "https://www.tiktok.com/api/v1/web-cookie-privacy/config?appId=1988" --ip-version "$1")
  process_json "$response" ".body.appProps.region"
}

lookup_cloudflare_cdn() {
  local response=$(curl_wrapper GET "https://speed.cloudflare.com/meta" --header "Referer: https://speed.cloudflare.com" --ip-version "$1")
  local iata=$(process_json "$response" ".colo.iata")
  echo "$(get_iata_location "$iata") ($iata)"
}

lookup_youtube_cdn() {
  local response=$(curl_wrapper GET "https://redirector.googlevideo.com/report_mapping?di=no" --ip-version "$1")
  local iata=$(echo "$response" | awk '{print $3}' | cut -f2 -d'-' | cut -c1-3)
  iata=${iata^^}
  if [[ -z "$iata" ]]; then echo ""; return; fi
  echo "$(get_iata_location "$iata") ($iata)"
}

lookup_netflix_cdn() {
  local response=$(curl_wrapper GET "https://api.fast.com/netflix/speedtest/v2?https=true&token=$NETFLIX_API_KEY&urlCount=1" --ip-version "$1")
  if is_valid_json "$response"; then process_json "$response" ".targets[0].location.country"; else echo ""; fi
}

lookup_ookla_speedtest() {
  local response=$(curl_wrapper GET "https://www.speedtest.net/api/js/config-sdk" --ip-version "$1")
  process_json "$response" ".location.countryCode"
}

lookup_jetbrains() {
  local response=$(curl_wrapper GET "https://data.services.jetbrains.com/geo" --ip-version "$1")
  process_json "$response" ".code"
}

lookup_playstation() {
  local response=$(curl_wrapper HEAD "https://www.playstation.com" --ip-version "$1")
  grep_wrapper --perl 'country=\K[^;]*' <<<"$response" | head -n1
}

lookup_microsoft() {
  local response=$(curl_wrapper GET "https://login.live.com" --ip-version "$1")
  grep_wrapper --perl '"sRequestCountry":"\K[^"]*' <<<"$response"
}

main() {
  parse_arguments "$@"
  setup_debug
  trap spinner_cleanup EXIT INT TERM
  detect_distro
  install_dependencies
  if [[ "$JSON_OUTPUT" != "true" && "$VERBOSE" != "true" ]]; then spinner_start; fi
  if ipv4_enabled; then check_ip_support 4; IPV4_SUPPORTED=$?; fi
  if ipv6_enabled; then check_ip_support 6; IPV6_SUPPORTED=$?; fi
  discover_external_ips
  get_asn
  case "$GROUPS_TO_SHOW" in
    primary) run_service_group "primary" ;;
    custom) run_service_group "custom" ;;
    cdn) run_service_group "cdn" ;;
    *) run_service_group "primary"; run_service_group "custom"; run_service_group "cdn" ;;
  esac
  if [[ "$JSON_OUTPUT" != "true" && "$VERBOSE" != "true" ]]; then spinner_stop; fi
  print_results
  cleanup_debug
  trap - EXIT INT TERM
}

main "$@"
EOF_IPREGION

    chmod +x /usr/local/bin/ipregion
    /usr/local/bin/ipregion
    echo
}

# ==========================================
# ГЛАВНЫЙ ЦИКЛ И НАВИГАЦИЯ
# ==========================================
options=(
    "--- БАЗОВАЯ ПОДГОТОВКА ---"
    "Базовые утилиты и зависимости"
    "BBR & TCP (Отключение IPv6)"
    "Изменение SSH порта"
    "Настройка брандмауэра UFW"
    "Установка Fail2Ban"
    "--- РАЗВЕРТЫВАНИЕ REMNAWAVE ---"
    "Установка Docker & Compose"
    "Caddy Selfsteal (Сертификаты)"
    "Установка Remnanode (Docker)"
    "Настройка ротации логов Xray"
    "--- ЗАЩИТА И ДОПОЛНЕНИЯ ---"
    "Установка Traffic Guard"
    "Блокировка Leaseweb & HE (iptables)"
    "Блокировка по URL (nftables)"
    "Установка Cloudflare WARP"
    "--- ДИАГНОСТИКА ---"
    "Получить Reality ключи и инфо"
    "IP Region Check"
    "Speedtest (Ookla)"
    "--- СКРИПТ ---"
    "Информация"
    "Обновить утилиту"
    "Удалить утилиту"
    "Выход"
)

check_updates

while true; do
    render_menu "${options[@]}"
    choice=$MENU_CHOICE
    NEEDS_PAUSE=1
    
    clear
    case "${options[$choice]}" in
        "Базовые утилиты и зависимости") step_base_deps ;;
        "BBR & TCP (Отключение IPv6)")   step_bbr_ipv6 ;;
        "Изменение SSH порта")           step_ssh_port ;;
        "Настройка брандмауэра UFW")     step_ufw_setup ;;
        "Установка Fail2Ban")            step_fail2ban_setup ;;
        "Установка Docker & Compose")    step_docker_setup ;;
        "Caddy Selfsteal (Сертификаты)") step_caddy_selfsteal ;;
        "Установка Remnanode (Docker)")  step_remnanode_setup ;;
        "Настройка ротации логов Xray")  step_logrotate_xray ;;
        "Установка Traffic Guard")       step_traffic_guard_setup ;;
        "Блокировка Leaseweb & HE (iptables)") step_block_asn ;;
        "Блокировка по URL (nftables)")  step_block_custom_list ;;
        "Установка Cloudflare WARP")     step_warp_setup ;;
        "Получить Reality ключи и инфо") step_show_reality ;;
        "IP Region Check")               step_ipregion ;;
        "Speedtest (Ookla)")             step_speedtest ;;
        "Информация")                    step_info ;;
        "Обновить утилиту")              step_update_script ;;
        "Удалить утилиту")               step_uninstall_script ;;
        "Выход") cursor_on; exit 0 ;;
    esac
    
    if [ "$NEEDS_PAUSE" -eq 1 ]; then pause; fi
done
