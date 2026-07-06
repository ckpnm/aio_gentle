#!/bin/bash

# Переменная с сырой ссылкой на папку src
SRC_RAW_URL="${REPO_RAW_URL}/src"

# ==========================================
# ПОЛУЧЕНИЕ ВЕРСИЙ С DOCKER HUB
# ==========================================
export SELECTED_NODE_VERSION="latest"

_choose_node_version() {
    cursor_off
    clear
    draw_header
    echo -e "\n  ${C_DIM}Связь с Docker Hub для получения версий...${C_BASE}\n"
    
    local fetched_versions
    # Получаем теги, вырезаем мусор (dev, alpha) и берем 3 самых свежих
    fetched_versions=$(curl -s --max-time 5 "https://hub.docker.com/v2/repositories/remnawave/node/tags/?page_size=20" | grep -Eo '"name": ?"[^"]+"' | cut -d'"' -f4 | grep -vE 'latest|dev|alpha|beta' | sort -rV | head -n 3)
    
    # Фолбек на случай, если Docker Hub недоступен
    if [[ -z "$fetched_versions" ]]; then
        fetched_versions="2.7.0"
    fi
    
    local v_opts=(
        "--- ВЫБЕРИТЕ ВЕРСИЮ НОДЫ ---"
        "latest (Рекомендуется)"
    )
    
    while IFS= read -r v; do
        [[ -n "$v" ]] && v_opts+=("$v")
    done <<< "$fetched_versions"
    
    v_opts+=("Назад")
    
    render_menu "${v_opts[@]}"
    local choice=$MENU_CHOICE
    local selected="${v_opts[$choice]}"
    
    if [[ "$selected" == "Назад" ]]; then
        return 1
    elif [[ "$selected" == "latest (Рекомендуется)" ]]; then
        SELECTED_NODE_VERSION="latest"
    else
        SELECTED_NODE_VERSION="$selected"
    fi
    return 0
}

# ==========================================
# DOCKER И БАЗА
# ==========================================
_do_docker() {
    export DEBIAN_FRONTEND=noninteractive
    if ! command -v docker &> /dev/null; then
        apt-get update -y > /dev/null 2>&1
        curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
        systemctl enable docker > /dev/null 2>&1
        systemctl start docker > /dev/null 2>&1
    fi
    if ! docker compose version &> /dev/null; then
        apt-get install -y docker-compose-plugin > /dev/null 2>&1
    fi
}

step_docker_setup() {
    draw_sub_header "Среда Docker"
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
        _do_docker
        printf "%s\n1\n9443\ny\n" "$DOMAIN" | bash <(curl -Ls https://github.com/DigneZzZ/remnawave-scripts/raw/main/selfsteal.sh) @ install
    }
    run_task "Генерация маскировки и запуск Caddy Selfsteal" "_do_selfsteal"
}

# ==========================================
# ПОДМЕНЮ УСТАНОВКИ НОДЫ
# ==========================================
step_install_remnanode_menu() {
    local sub_options=(
        "--- ВЫБЕРИТЕ ТИП УСТАНОВКИ НОДЫ ---"
        "Голая нода (Только Xray)"
        "SelfSteal нода (Nginx)"
        "SelfSteal нода (Caddy)"
        "Назад в главное меню"
    )
    
    while true; do
        render_menu "${sub_options[@]}"
        local sub_choice=$MENU_CHOICE
        local SUB_NEEDS_PAUSE=1
        
        clear
        case "${sub_options[$sub_choice]}" in
            "Голая нода (Только Xray)") step_remnanode_setup ;;
            "SelfSteal нода (Nginx)")   step_node_nginx ;;
            "SelfSteal нода (Caddy)")   step_node_caddy ;;
            "Назад в главное меню")     return 0 ;;
        esac
        
        if [ "$SUB_NEEDS_PAUSE" -eq 1 ]; then pause; fi
    done
}

# ==========================================
# УСТАНОВКА НОД
# ==========================================
step_remnanode_setup() {
    if ! _choose_node_version; then return 0; fi
    clear
    draw_sub_header "Голая нода ($SELECTED_NODE_VERSION)"

    read -p "Введите SecretKey из вашей панели Remnawave: " SECRET_KEY
    if [[ -z "$SECRET_KEY" ]]; then
        echo -e "${C_ERR}Ошибка: Ключ отсутствует!${C_BASE}"
        return 1
    fi

    _do_remnanode() {
        _do_docker
        mkdir -p /opt/remnanode /var/log/xray
        chmod 777 /var/log/xray

        # Скачиваем шаблон, подставляем SECRET_KEY и выбранную ВЕРСИЮ ноды
        curl -sL "${SRC_RAW_URL}/docker-compose-bare.yml" | sed -E "s|#SECRET_KEY#|$SECRET_KEY|g; s|image: remnawave/node:.*|image: remnawave/node:${SELECTED_NODE_VERSION}|g" > /opt/remnanode/docker-compose.yml

        cd /opt/remnanode
        docker compose down &>/dev/null || true
        docker compose up -d
    }
    run_task "Развертывание голой ноды" "_do_remnanode"
}

step_node_caddy() {
    if ! _choose_node_version; then return 0; fi
    clear
    draw_sub_header "Remnanode + Caddy ($SELECTED_NODE_VERSION)"
    
    read -p "Введите домен для маскировки (напр. node.site.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then echo -e "${C_ERR}Домен не может быть пустым!${C_BASE}"; return 1; fi

    while true; do
        read -p "Введите IP-адрес вашей ПАНЕЛИ Remnawave: " PANEL_IP
        if [[ "$PANEL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then break; else echo -e "${C_ERR}Неверный формат IP!${C_BASE}"; fi
    done

    read -p "Введите SecretKey из панели: " SECRET_KEY
    if [[ -z "$SECRET_KEY" ]]; then echo -e "${C_ERR}Ключ не может быть пустым!${C_BASE}"; return 1; fi

    _do_node_caddy() {
        _do_docker
        mkdir -p /opt/remnanode /var/www/html
        curl -sSL "https://raw.githubusercontent.com/legiz-ru/Orion/refs/heads/main/index.html" -o /var/www/html/index.html

        # Качаем шаблоны и подставляем переменные + версию
        curl -sL "${SRC_RAW_URL}/docker-compose-caddy.yml" | sed -E "s|#SECRET_KEY#|$SECRET_KEY|g; s|#DOMAIN#|$DOMAIN|g; s|image: remnawave/node:.*|image: remnawave/node:${SELECTED_NODE_VERSION}|g" > /opt/remnanode/docker-compose.yml
        curl -sL "${SRC_RAW_URL}/Caddyfile" > /opt/remnanode/Caddyfile

        ufw allow 80/tcp > /dev/null 2>&1
        ufw allow from $PANEL_IP to any port 2222 > /dev/null 2>&1
        ufw reload > /dev/null 2>&1

        cd /opt/remnanode
        docker compose down &>/dev/null || true
        docker compose up -d
    }

    run_task "Развертывание Ноды и Caddy" "_do_node_caddy"
    
    echo -e "\n  ${C_INV} ВАЖНО: НАСТРОЙКА В ПАНЕЛИ REMNAWAVE ${C_BASE}"
    echo -e "  ${C_WHITE}В настройках подключения (Inbound -> Reality) укажите:${C_BASE}"
    echo -e "  ${C_DIM}----------------------------------------${C_BASE}"
    echo -e "  ${C_ACCENT}\"dest\": \"/dev/shm/nginx.sock\",${C_BASE}"
    echo -e "  ${C_ACCENT}\"show\": false,${C_BASE}"
    echo -e "  ${C_ACCENT}\"xver\": 1${C_BASE}"
    echo -e "  ${C_DIM}----------------------------------------${C_BASE}"
    echo -e "  ${C_WHITE}SNI: ${C_ACCENT}${DOMAIN}${C_BASE}\n"
}

step_node_nginx() {
    if ! _choose_node_version; then return 0; fi
    clear
    draw_sub_header "Remnanode + Nginx ($SELECTED_NODE_VERSION)"
    
    read -p "Введите домен для маскировки (напр. node.site.com): " DOMAIN
    if [[ -z "$DOMAIN" ]]; then echo -e "${C_ERR}Домен не может быть пустым!${C_BASE}"; return 1; fi

    while true; do
        read -p "Введите IP-адрес вашей ПАНЕЛИ Remnawave: " PANEL_IP
        if [[ "$PANEL_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then break; else echo -e "${C_ERR}Неверный формат IP!${C_BASE}"; fi
    done

    read -p "Введите SecretKey из панели: " SECRET_KEY
    if [[ -z "$SECRET_KEY" ]]; then echo -e "${C_ERR}Ключ не может быть пустым!${C_BASE}"; return 1; fi
    
    read -p "Введите Email для SSL сертификата Let's Encrypt: " CERT_EMAIL

    _do_node_nginx() {
        _do_docker
        mkdir -p /opt/remnanode /var/www/html
        curl -sSL "https://raw.githubusercontent.com/legiz-ru/Orion/refs/heads/main/index.html" -o /var/www/html/index.html

        # Жестко освобождаем 80 порт
        docker stop caddy-remnawave remnawave-nginx &>/dev/null || true
        systemctl stop nginx &>/dev/null || true
        fuser -k 80/tcp &>/dev/null || true

        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y > /dev/null 2>&1
        apt-get install -y certbot > /dev/null 2>&1

        if ! command -v certbot &> /dev/null; then
            echo -e "\n[ОШИБКА] Не удалось установить certbot." >&2
            return 1
        fi

        ufw allow 80/tcp > /dev/null 2>&1
        
        if ! certbot certonly --standalone -d "$DOMAIN" --email "$CERT_EMAIL" --agree-tos --non-interactive; then
            echo -e "\n[ОШИБКА] Ошибка certbot при получении сертификата. Подробности выше в логе." >&2
            ufw delete allow 80/tcp > /dev/null 2>&1
            return 1
        fi
        
        ufw delete allow 80/tcp > /dev/null 2>&1

        if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
            echo "Сертификат не был сохранен в нужную директорию." >&2
            return 1
        fi

        # Качаем шаблоны и подставляем переменные + версию
        curl -sL "${SRC_RAW_URL}/docker-compose-nginx.yml" | sed -E "s|#SECRET_KEY#|$SECRET_KEY|g; s|#DOMAIN#|$DOMAIN|g; s|image: remnawave/node:.*|image: remnawave/node:${SELECTED_NODE_VERSION}|g" > /opt/remnanode/docker-compose.yml
        curl -sL "${SRC_RAW_URL}/nginx.conf" | sed "s|#DOMAIN#|$DOMAIN|g" > /opt/remnanode/nginx.conf

        ufw allow from $PANEL_IP to any port 2222 > /dev/null 2>&1
        ufw reload > /dev/null 2>&1

        cd /opt/remnanode
        docker compose down &>/dev/null || true
        docker compose up -d
    }

    run_task "Развертывание Ноды и Nginx" "_do_node_nginx"
    
    echo -e "\n  ${C_INV} ВАЖНО: НАСТРОЙКА В ПАНЕЛИ REMNAWAVE ${C_BASE}"
    echo -e "  ${C_WHITE}В настройках подключения (Inbound -> Reality) укажите:${C_BASE}"
    echo -e "  ${C_DIM}----------------------------------------${C_BASE}"
    echo -e "  ${C_ACCENT}\"dest\": \"/dev/shm/nginx.sock\",${C_BASE}"
    echo -e "  ${C_ACCENT}\"show\": false,${C_BASE}"
    echo -e "  ${C_ACCENT}\"xver\": 1${C_BASE}"
    echo -e "  ${C_DIM}----------------------------------------${C_BASE}"
    echo -e "  ${C_WHITE}SNI: ${C_ACCENT}${DOMAIN}${C_BASE}\n"
}

# ==========================================
# ФЕЙК-САЙТ И РОТАЦИЯ
# ==========================================
step_random_html() {
    draw_sub_header "Установка фейк-сайта (SelfSteal)"
    
    echo -e "  ${C_WHITE}Выберите источник (репозиторий) шаблонов:${C_BASE}"
    echo -e "  ${C_ACCENT}1.${C_BASE} Simple Web Templates (Полноценные сайты)"
    echo -e "  ${C_ACCENT}2.${C_BASE} SNI Templates (Популярные лендинги)"
    echo -e "  ${C_ACCENT}3.${C_BASE} Nothing Templates (Минималистичные заглушки)"
    echo -e "  ${C_DIM}0. Отмена${C_BASE}\n"
    
    read -p "  Ваш выбор: " TPL_CHOICE
    
    local REPO_URL=""
    local REPO_DIR=""
    case "$TPL_CHOICE" in
        1) REPO_URL="https://github.com/eGamesAPI/simple-web-templates/archive/refs/heads/main.zip"; REPO_DIR="simple-web-templates-main" ;;
        2) REPO_URL="https://github.com/distillium/sni-templates/archive/refs/heads/main.zip"; REPO_DIR="sni-templates-main" ;;
        3) REPO_URL="https://github.com/prettyleaf/nothing-sni/archive/refs/heads/main.zip"; REPO_DIR="nothing-sni-main" ;;
        0) return 0 ;;
        *) echo -e "${C_ERR}Неверный выбор.${C_BASE}"; return 1 ;;
    esac

    _do_random_html() {
        cd /tmp
        rm -f main.zip
        rm -rf "$REPO_DIR"

        wget -q --timeout=30 --tries=3 "$REPO_URL" -O main.zip || return 1
        unzip -o main.zip >/dev/null 2>&1 || return 1
        rm -f main.zip

        cd "$REPO_DIR" || return 1

        rm -rf assets .gitattributes README.md _config.yml .github index.html 2>/dev/null || true

        local SELECTED_ITEM=""
        if [[ "$TPL_CHOICE" == "3" ]]; then
            SELECTED_ITEM="$((RANDOM % 8 + 1)).html"
        else
            mapfile -t templates < <(find . -maxdepth 1 -type d -not -path . | sed 's|^\./||')
            SELECTED_ITEM="${templates[$RANDOM % ${#templates[@]}]}"

            if [[ "$TPL_CHOICE" == "2" && "$SELECTED_ITEM" == "503 error pages" ]]; then
                local versions=("v1" "v2")
                SELECTED_ITEM="$SELECTED_ITEM/${versions[$RANDOM % ${#versions[@]}]}"
            fi
        fi

        local r_meta_id=$(openssl rand -hex 16)
        local r_comment=$(openssl rand -hex 8)
        local r_class_suf=$(openssl rand -hex 4)
        local r_title_suf=$(openssl rand -hex 4)
        local r_id_suf=$(openssl rand -hex 4)
        local r_user="User$(openssl rand -hex 2)"
        
        local meta_names=("viewport-id" "session-id" "track-id" "render-id" "page-id")
        local r_meta_name=${meta_names[$RANDOM % ${#meta_names[@]}]}
        
        local class_prefs=("style" "data" "ui" "layout" "theme")
        local r_class="${class_prefs[$RANDOM % ${#class_prefs[@]}]}-$r_class_suf"

        find "./$SELECTED_ITEM" -type f -name "*.html" -exec sed -i \
            -e "s|||g" \
            -e "s|||g" \
            -e "s|id=\"Content\"|id=\"rnd_${r_id_suf}\"|g" \
            -e "s|<title>.*</title>|<title>Page_${r_title_suf}</title>|g" \
            -e "s/<\/head>/<meta name=\"$r_meta_name\" content=\"$r_meta_id\">\n\n<\/head>/g" \
            -e "s/<body/<body class=\"$r_class\"/g" \
            -e "s/CHANGEMEPLS/$r_user/g" {} +
            
        find "./$SELECTED_ITEM" -type f -name "*.css" -exec sed -i \
            -e "1i\/* $r_comment */" \
            -e "1i.$r_class { display: block; }" {} + 2>/dev/null || true

        mkdir -p /var/www/html
        rm -rf /var/www/html/*
        
        if [[ -d "./$SELECTED_ITEM" ]]; then
            cp -a "./$SELECTED_ITEM/." "/var/www/html/"
        else
            cp "./$SELECTED_ITEM" "/var/www/html/index.html"
        fi
        
        cd /tmp
        rm -rf "$REPO_DIR"
    }

    run_task "Загрузка и маскировка шаблона" "_do_random_html"
    echo -e "  ${C_OK}[ ИНФО ]${C_BASE} Шаблон успешно установлен и замаскирован."
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
