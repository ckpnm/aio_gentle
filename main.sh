#!/bin/bash

export SCRIPT_VERSION="1.11"
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
   
    local title_text="AIO - GENTLE"
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
    if curl -s --max-time 10 "https://raw.githubusercontent.com/ckpnm/aio_gentle_utility/main/main.sh" -o "$SCRIPT_DIR/main.sh"; then
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

        cat << EOF > /opt/remnanode/docker-compose.yml
services:
  remnanode:
    container_name: remnanode
    hostname: remnanode
    image: remnawave/node:2.7.0
    network_mode: host
    restart: always
    cap_add:
      - NET_ADMIN
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    environment:
      - NODE_PORT=2222
      - SECRET_KEY=${SECRET_KEY}
    volumes:
      - '/var/log/xray:/var/log/xray'
      - /etc/letsencrypt:/etc/letsencrypt:ro
EOF
        cd /opt/remnanode
        docker compose down &>/dev/null || true
        docker compose up -d
    }
    run_task "Запись docker-compose и запуск ноды" "_do_remnanode"
}

step_logrotate_xray() {
    draw_sub_header "Ротация логов Xray"
    _do_logrotate() {
        cat << 'EOF' > /etc/logrotate.d/xray
/var/log/xray/*.log {
      size 50M
      rotate 5
      compress
      missingok
      notifempty
      copytruncate
}
EOF
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

        cat << 'EOF' > /usr/local/bin/block_leaseweb.sh
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
