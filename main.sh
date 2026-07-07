#!/bin/bash

export SCRIPT_VERSION=" 1.06"
export GITHUB_URL="https://github.com/ckpnm/aio_gentle"
export REPO_RAW_URL="https://raw.githubusercontent.com/ckpnm/aio_gentle/main"

export AIO_DIR="/usr/local/aio_gentle"
export MODULES_DIR="$AIO_DIR/modules"
export LOG_FILE="/var/log/aio_setup.log"

if [[ $EUID -ne 0 ]]; then
   echo -e "\e[1;31mОшибка: Скрипт должен быть запущен от имени root.\e[0m"
   exit 1
fi

mkdir -p "$MODULES_DIR"
echo -e "\n========================================" >> "$LOG_FILE"
echo "Запуск A I O - GENTLE UTILITY: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
echo "========================================" >> "$LOG_FILE"

export C_BASE='\e[0m'
export C_ACCENT='\e[1;36m' 
export C_DIM='\e[90m'      
export C_OK='\e[32m'       
export C_ERR='\e[31m'      
export C_WHITE='\e[97m'    
export C_BOLD='\e[1m'

cursor_off() { printf "\e[?25l"; }
cursor_on()  { printf "\e[?25h"; }
trap "cursor_on; echo; exit" SIGINT

pause() {
    cursor_off
    echo -e "\n${C_OK}Нажми любую клавишу для возврата...${C_BASE}"
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
    local title_text="A I O - GENTLE "
    local ver_text="v${SCRIPT_VERSION}"
    local title_len=$(( ${#title_text} + ${#ver_text} ))
    local pad_left=$(( (total_width - title_len) / 2 ))
    local pad_right=$(( total_width - title_len - pad_left ))
    
    local p_l=$(printf "%${pad_left}s" "")
    local p_r=$(printf "%${pad_right}s" "")

    local sub_text="utility"
    local sub_len=${#sub_text}
    local sub_pad_left=$(( pad_left + title_len - sub_len ))
    local sub_pad_right=$(( total_width - sub_pad_left - sub_len ))
    local sp_l=$(printf "%${sub_pad_left}s" "")
    local sp_r=$(printf "%${sub_pad_right}s" "")

    echo -e "\n${c_light}╭─────────────────────────────────────╮${c_reset}"
    echo -e "${c_dark}│${c_reset}${p_l}${c_white}\e[1m${title_text}${c_white}${ver_text}${c_reset}${c_light}${p_r}│${c_reset}"
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
        local bar=" "
        for ((i=0; i<width; i++)); do
            # Заменили квадраты на кружки
            if [ $i -lt $p ]; then bar+="●"; else bar+="○"; fi
        done
        bar+=" "
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
        echo -e " ${C_DIM}GitHub: ${GITHUB_URL}${C_BASE}\e[K\n"

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
            if [[ "${options[$i+1]}" == ---* ]]; then echo -e "\e[K"; fi
        done
        printf "\e[J"

        if ! read -rsn3 key; then cursor_on; exit 1; fi

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

    { "$cmd_func"; } >> "$LOG_FILE" 2>&1 &
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

load_module() {
    local mod_name="$1"
    local local_file="$MODULES_DIR/$mod_name"
    local remote_url="$REPO_RAW_URL/modules/$mod_name"

    if [ ! -f "$local_file" ] || [ "$FORCE_UPDATE" = "1" ]; then
        # Добавили --retry 3 (3 попытки) и увеличили таймауты
        curl -sSL --retry 3 --retry-delay 2 --connect-timeout 10 --max-time 30 "$remote_url" -o "$local_file"
    fi
    
    # Проверяем, что файл существует и он не пустой (-s)
    if [ -f "$local_file" ] && [ -s "$local_file" ]; then
        source "$local_file"
    else
        echo -e "\n${C_ERR}Критическая ошибка: Не удалось загрузить модуль $mod_name. Проверьте связь с GitHub.${C_BASE}"
        exit 1
    fi
}

_sync_core_modules() {
    local core_modules=("base.sh" "remnanode.sh" "security.sh" "diagnostics.sh" "system.sh")
    for mod in "${core_modules[@]}"; do
        load_module "$mod"
    done
}

echo -e "${C_DIM}Синхронизация модулей ΛIO...${C_BASE}"
export FORCE_UPDATE="1"
_sync_core_modules
clear

if [ ! -f /usr/local/bin/aio_gentle ]; then
    ln -sf "$AIO_DIR/main.sh" /usr/local/bin/aio_gentle 2>/dev/null
fi

options=(
    "--- БАЗОВАЯ ПОДГОТОВКА ---"
    "Базовые утилиты и зависимости"
    "BBR & TCP (Отключение IPv6)"
    "Swap (Подкачка памяти)"
    "Изменение SSH порта"
    "Настройка брандмауэра UFW"
    "--- УСТАНОВКА REMNAWAVE ---"
    "Установка Docker & Compose"
    "Установка Remnanode"
    "Установка фейк-сайта (SelfSteal)"
    "Настройка ротации логов Xray"
    "--- ЗАЩИТА И ДОПОЛНЕНИЯ ---"
    "Установка Traffic Guard"
    "Блокировка Leaseweb & HE (Анти БОТНЕТ)"
    "Блокировка ГРЧЦ (Auto IPTables)"
    "Управление Cloudflare WARP"
    "--- ДИАГНОСТИКА ---"
    "Получить Reality ключи и инфо"
    "IP Region Check"
    "Спидтесты (Ookla & iPerf3)"
    "CensorCheck (ТСПУ / DPI)"
    "IP Репутация"
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
        "Swap (Подкачка памяти)")        step_swap ;;
        "Изменение SSH порта")           step_ssh_port ;;
        "Настройка брандмауэра UFW")     step_ufw_setup ;;
        
        "Установка Docker & Compose")    step_docker_setup ;;
        "Установка Remnanode")           step_install_remnanode_menu; NEEDS_PAUSE=0 ;;
        "Установка фейк-сайта (SelfSteal)") step_random_html ;;
        "Настройка ротации логов Xray")  step_logrotate_xray ;;
        
        "Установка Traffic Guard")       step_traffic_guard_setup ;;
        "Блокировка Leaseweb & HE (Анти БОТНЕТ)") step_block_asn ;;
        "Блокировка ГРЧЦ (Auto IPTables)")  step_block_custom_list ;;
        "Управление Cloudflare WARP")    step_warp_menu; NEEDS_PAUSE=0 ;;
        
        "Получить Reality ключи и инфо") step_show_reality ;;
        "IP Region Check")               step_ipregion ;;
        "Спидтесты (Ookla & iPerf3)")    step_speedtests_menu; NEEDS_PAUSE=0 ;;
        "CensorCheck (ТСПУ / DPI)")      step_censorcheck ;;
        "IP Репутация")  step_ipquality ;;
        
        "Информация")                    step_info ;;
        "Обновить утилиту")              step_update_script ;;
        "Удалить утилиту")               step_uninstall_script ;;
        "Выход") cursor_on; exit 0 ;;
    esac
    
    if [ "$NEEDS_PAUSE" -eq 1 ]; then pause; fi
done
