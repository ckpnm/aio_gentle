#!/bin/bash

# ==========================================
# ПОДМЕНЮ WARP
# ==========================================
step_warp_menu() {
    local sub_options=(
        "--- CLOUDFLARE WARP ---"
        "Установить WARP (Native)"
        "Удалить WARP"
        "Назад в главное меню"
    )
    
    while true; do
        render_menu "${sub_options[@]}"
        local sub_choice=$MENU_CHOICE
        local SUB_NEEDS_PAUSE=1
        
        clear
        case "${sub_options[$sub_choice]}" in
            "Установить WARP (Native)") step_warp_install ;;
            "Удалить WARP")             step_warp_uninstall ;;
            "Назад в главное меню")     return 0 ;;
        esac
        
        if [ "$SUB_NEEDS_PAUSE" -eq 1 ]; then pause; fi
    done
}

# ==========================================
# УСТАНОВКА WARP
# ==========================================
step_warp_install() {
    draw_sub_header "Установка Cloudflare WARP"

    if command -v wgcf &> /dev/null && ip link show warp &>/dev/null; then
        echo -e "  ${C_OK}[ ИНФО ]${C_BASE} WARP уже установлен. Для переустановки сначала удалите его."
        return 0
    fi

    echo -e "  ${C_WHITE}Если у вас есть ключ WARP+, вы можете применить его сейчас.${C_BASE}"
    read -p "  Ключ WARP+ (Enter - использовать бесплатный): " WARP_LICENSE

    echo -e "\n  ${C_WHITE}Выберите интервал проверки соединения (Watchdog):${C_BASE}"
    echo -e "  ${C_ACCENT}1.${C_BASE} Каждые 5 минут"
    echo -e "  ${C_ACCENT}2.${C_BASE} Каждые 10 минут (по умолчанию)"
    echo -e "  ${C_ACCENT}3.${C_BASE} Каждые 15 минут"
    echo -e "  ${C_ACCENT}4.${C_BASE} Каждые 30 минут"
    
    read -p "  Ваш выбор [1-4]: " wdog_choice

    export W_INT=10
    export W_CRON="*/10 * * * *"
    case "$wdog_choice" in
        1) W_INT=5;  W_CRON="*/5 * * * *" ;;
        2) W_INT=10; W_CRON="*/10 * * * *" ;;
        3) W_INT=15; W_CRON="*/15 * * * *" ;;
        4) W_INT=30; W_CRON="*/30 * * * *" ;;
        *) W_INT=10; W_CRON="*/10 * * * *" ;;
    esac
    echo ""

    _do_warp_install() {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y wireguard jq curl wget >/dev/null 2>&1
        
        # Назначение временных DNS для надежной регистрации wgcf
        cp /etc/resolv.conf /etc/resolv.conf.backup
        echo -e "nameserver 1.1.1.1\nnameserver 8.8.8.8" > /etc/resolv.conf
        
        # Загрузка актуального wgcf
        local WGCF_RELEASE_URL="https://api.github.com/repos/ViRb3/wgcf/releases/latest"
        local WGCF_VERSION=$(curl -s "$WGCF_RELEASE_URL" | grep '"tag_name":' | cut -d '"' -f 4)
        local ARCH=$(uname -m)
        local WGCF_ARCH="amd64"
        [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && WGCF_ARCH="arm64"
        
        local WGCF_URL="https://github.com/ViRb3/wgcf/releases/download/${WGCF_VERSION}/wgcf_${WGCF_VERSION#v}_linux_${WGCF_ARCH}"
        
        curl -sL "$WGCF_URL" -o /usr/local/bin/wgcf
        chmod +x /usr/local/bin/wgcf
        
        cd /root
        rm -f wgcf-account.toml wgcf-profile.conf
        
        # Регистрация устройства в Cloudflare (с повтором при ошибках Rate Limit / 500)
        for i in {1..3}; do
            timeout 60 bash -c 'yes | wgcf register' && break
            sleep 5
        done
        
        wgcf generate
        
        if [[ -n "$WARP_LICENSE" ]]; then
            wgcf update --license-key "$WARP_LICENSE"
            wgcf generate
        fi
        
        # Редактирование конфига (критично для VPN - не берем DNS на себя)
        local CONF="wgcf-profile.conf"
        sed -i '/^DNS =/d' "$CONF"
        grep -q "Table = off" "$CONF" || sed -i '/^MTU =/aTable = off' "$CONF"
        grep -q "PersistentKeepalive = 25" "$CONF" || sed -i '/^Endpoint =/aPersistentKeepalive = 25' "$CONF"
        
        # Удаление IPv6 (часто мешает маршрутизации Xray)
        sed -i 's/,\s*[0-9a-fA-F:]\+\/128//' "$CONF"
        sed -i '/Address = [0-9a-fA-F:]\+\/128/d' "$CONF"
        
        mkdir -p /etc/wireguard
        mv "$CONF" /etc/wireguard/warp.conf
        
        # Восстанавливаем DNS
        cp /etc/resolv.conf.backup /etc/resolv.conf
        
        # Запуск интерфейса
        systemctl enable wg-quick@warp >/dev/null 2>&1
        systemctl start wg-quick@warp >/dev/null 2>&1
        
        # Установка Watchdog (Скрипт мониторинга соединения)
        mkdir -p /opt/warp-native/logs
        cat > /opt/warp-native/config.env <<EOF
HANDSHAKE_THRESHOLD=180
RESTART_COOLDOWN=120
LOG_MAX_LINES=1000
EOF
        cat > /opt/warp-native/warp-watchdog.sh <<'WATCHDOG_EOF'
#!/bin/bash
CONFIG="/opt/warp-native/config.env"
LOG="/opt/warp-native/logs/watchdog.log"
COOLDOWN_FILE="/opt/warp-native/logs/.last_restart"
[[ -f "$CONFIG" ]] && source "$CONFIG"
HANDSHAKE_THRESHOLD="${HANDSHAKE_THRESHOLD:-180}"
RESTART_COOLDOWN="${RESTART_COOLDOWN:-120}"
LOG_MAX_LINES="${LOG_MAX_LINES:-1000}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$1] $2" >> "$LOG"; }

if [[ -f "$LOG" ]] && [[ $(wc -l < "$LOG") -gt $LOG_MAX_LINES ]]; then
    tail -n "$LOG_MAX_LINES" "$LOG" > "${LOG}.tmp" && mv "${LOG}.tmp" "$LOG"
fi

do_restart() {
    if [[ -f "$COOLDOWN_FILE" ]]; then
        local diff=$(( $(date +%s) - $(cat "$COOLDOWN_FILE") ))
        [[ $diff -lt $RESTART_COOLDOWN ]] && return
    fi
    log "RESTART" "Reason: $1"
    systemctl restart wg-quick@warp
    date +%s > "$COOLDOWN_FILE"
}

if ! systemctl is-active --quiet wg-quick@warp; then do_restart "not active"; exit 0; fi
handshake_ts=$(wg show warp latest-handshakes 2>/dev/null | awk '{print $2}')
if [[ -z "$handshake_ts" || "$handshake_ts" -eq 0 ]]; then do_restart "no handshake"; exit 0; fi
age=$(( $(date +%s) - handshake_ts ))
if [[ $age -gt $HANDSHAKE_THRESHOLD ]]; then do_restart "handshake old (${age}s)"; exit 0; fi
if ! ping -I warp -c 2 -W 3 1.1.1.1 &>/dev/null; then do_restart "ping failed"; exit 0; fi
log "OK" "WARP is healthy"
WATCHDOG_EOF

        chmod +x /opt/warp-native/warp-watchdog.sh
        echo "$W_CRON root /opt/warp-native/warp-watchdog.sh" > /etc/cron.d/warp-native
        chmod 644 /etc/cron.d/warp-native
        
        # Установка алиаса для пользователя
        cat > /usr/local/bin/warp <<'WARP_CMD_EOF'
#!/bin/bash
if [[ "$1" == "log" ]]; then tail -f /opt/warp-native/logs/watchdog.log; exit 0; fi
wg show warp
WARP_CMD_EOF
        chmod +x /usr/local/bin/warp
    }

    run_task "Установка и конфигурация туннеля WARP" "_do_warp_install"

    # Финальная диагностика
    echo -e "\n  ${C_ACCENT}Интерфейс WARP запущен!${C_BASE}"
    local tunnel_ip=$(ip addr show warp 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
    [[ -z "$tunnel_ip" ]] && tunnel_ip="—"
    
    local acc_type="Free"
    wgcf status 2>/dev/null | grep -qi "unlimited" && acc_type="WARP+"
    
    echo -e "  ${C_WHITE}Тип аккаунта:${C_BASE} ${C_OK}${acc_type}${C_BASE}"
    echo -e "  ${C_WHITE}IP туннеля:${C_BASE}   ${C_DIM}${tunnel_ip}${C_BASE}"
    echo -e "\n  ${C_DIM}Для просмотра логов watchdog введите в консоли сервера: ${C_ACCENT}warp log${C_BASE}"
}

# ==========================================
# УДАЛЕНИЕ WARP
# ==========================================
step_warp_uninstall() {
    draw_sub_header "Удаление Cloudflare WARP"
    echo -e "  ${C_ERR}ВНИМАНИЕ: WARP, Watchdog и пакеты WireGuard будут удалены.${C_BASE}\n"
    read -p "  Вы уверены? (y/n): " confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then 
        echo -e "\n  ${C_DIM}Удаление отменено.${C_BASE}"
        return 0
    fi

    _do_warp_uninstall() {
        systemctl stop wg-quick@warp &>/dev/null || true
        systemctl disable wg-quick@warp &>/dev/null || true
        ip link delete warp &>/dev/null || true
        
        rm -rf /etc/wireguard/warp.conf /usr/local/bin/wgcf /root/wgcf-account.toml /root/wgcf-profile.conf
        rm -f /etc/cron.d/warp-native /usr/local/bin/warp
        rm -rf /opt/warp-native
        
        export DEBIAN_FRONTEND=noninteractive
        apt-get remove --purge -y wireguard &>/dev/null || true
        apt-get autoremove -y &>/dev/null || true
    }

    run_task "Очистка конфигураций и пакетов" "_do_warp_uninstall"
    echo -e "  ${C_OK}✓${C_BASE} ${C_WHITE}WARP полностью удален с сервера.${C_BASE}"
}

# ==========================================
# ИНФО О СКРИПТЕ
# ==========================================
step_info() {
    draw_sub_header "Информация и Благодарности"
    echo -e "  ${C_WHITE}Огромная благодарность авторам открытых скриптов и списков,${C_BASE}"
    echo -e "  ${C_WHITE}которые были использованы или адаптированы в этой утилите:${C_BASE}\n"
    
    echo -e "  ${C_ACCENT}● Zover1337${C_BASE} — ${C_DIM}https://github.com/Zover1337${C_BASE}"
    echo -e "  ${C_ACCENT}● jaywehosl${C_BASE} — ${C_DIM}https://github.com/jaywehosl${C_BASE}"
    echo -e "  ${C_ACCENT}● Loorrr293${C_BASE} — ${C_DIM}https://github.com/Loorrr293${C_BASE}"
    echo -e "  ${C_ACCENT}● eGamesAPI${C_BASE} — ${C_DIM}https://github.com/eGamesAPI${C_BASE}"
    echo -e "  ${C_ACCENT}● distillium${C_BASE} — ${C_DIM}https://github.com/distillium${C_BASE}\n"
    
    echo -e "  ${C_WHITE}Также спасибо всем мейнтейнерам Xray, Remnawave и других проектов.${C_BASE}"
}
