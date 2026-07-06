#!/bin/bash

# ==========================================
# ПОДМЕНЮ СПИДТЕСТОВ
# ==========================================
step_speedtests_menu() {
    local sub_options=(
        "--- ВЫБЕРИТЕ ТИП ТЕСТА ---"
        "Ookla Speedtest (Мировой)"
        "iPerf3 Speedtest (РФ сервера)"
        "Назад в главное меню"
    )
    
    while true; do
        render_menu "${sub_options[@]}"
        local sub_choice=$MENU_CHOICE
        local SUB_NEEDS_PAUSE=1
        
        clear
        case "${sub_options[$sub_choice]}" in
            "Ookla Speedtest (Мировой)") step_speedtest_ookla ;;
            "iPerf3 Speedtest (РФ сервера)") step_speedtest_iperf3 ;;
            "Назад в главное меню") return 0 ;;
        esac
        
        if [ "$SUB_NEEDS_PAUSE" -eq 1 ]; then pause; fi
    done
}

# ==========================================
# OOKLA (Глобальный)
# ==========================================
step_speedtest_ookla() {
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
    speedtest --accept-license --accept-gdpr
    echo
}

# ==========================================
# IPERF3 (РФ Сервера)
# ==========================================
step_speedtest_iperf3() {
    draw_sub_header "iPerf3 Speedtest (РФ сервера)"

    if ! command -v iperf3 &> /dev/null || ! command -v jq &> /dev/null; then
        echo -e "  ${C_DIM}Установка зависимостей (iperf3, jq)...${C_BASE}"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y iperf3 jq >/dev/null 2>&1
    fi

    local IPERF_TIMEOUT=15
    local IPERF_TEST_DURATION=10
    local PARALLEL_STREAMS=8
    local FALLBACK_STREAMS=8
    local INTER_TEST_DELAY=1
    local MAX_JSON_LENGTH=50
    local IPERF_PORT_RANGE=(5201 5202 5203 5204 5205 5206 5207 5208 5209)
    local RESULTS=()

    declare -A SERVERS=(
        ["Moscow"]="spd-rudp.hostkey.ru"
        ["Saint Petersburg"]="st.spb.ertelecom.ru"
        ["Nizhny Novgorod"]="st.nn.ertelecom.ru"
        ["Chelyabinsk"]="st.chel.ertelecom.ru"
        ["Tyumen"]="st.tmn.ertelecom.ru"
    )

    declare -A FALLBACK_SERVERS=(
        ["Moscow"]="st.tver.ertelecom.ru"
        ["Saint Petersburg"]="st.yar.ertelecom.ru"
        ["Nizhny Novgorod"]="speed-nn.vtt.net"
        ["Chelyabinsk"]="st.mgn.ertelecom.ru"
        ["Tyumen"]="st.krsk.ertelecom.ru"
    )

    declare -A FALLBACK_CITIES=(
        ["Moscow"]="Tver"
        ["Saint Petersburg"]="Yaroslavl"
        ["Nizhny Novgorod"]="Nizhny Novgorod"
        ["Chelyabinsk"]="Magnitogorsk"
        ["Tyumen"]="Krasnoyarsk"
    )

    local CITY_ORDER=("Moscow" "Saint Petersburg" "Nizhny Novgorod" "Chelyabinsk" "Tyumen")

    _find_available_port() {
        local host="$1"
        for port in "${IPERF_PORT_RANGE[@]}"; do
            local test_result
            test_result=$(timeout "$IPERF_TIMEOUT" iperf3 -c "$host" -p "$port" -t 1 2>&1 || echo "")
            if [[ "$test_result" == *"receiver"* && "$test_result" != *"error"* ]]; then
                echo "$port"
                return 0
            fi
        done
        return 1
    }

    _test_iperf_server() {
        local host="$1"
        local port="$2"
        local streams="$3"
        local result
        result=$(timeout "$IPERF_TIMEOUT" iperf3 -c "$host" -p "$port" -P "$streams" -t "$IPERF_TEST_DURATION" -J 2>/dev/null || echo "")
        
        if [[ -n "$result" && "$result" == *'"receiver"'* && "${#result}" -gt "$MAX_JSON_LENGTH" ]]; then
            echo "$result"
            return 0
        fi
        return 1
    }

    _parse_speed() {
        local json="$1"
        local direction="$2"
        if [[ "$direction" == "sender" ]]; then
            echo "$json" | jq -r ".end.sum_sent.bits_per_second // 0" | awk '{printf "%.1f", $1/1000000}'
        else
            echo "$json" | jq -r ".end.sum_received.bits_per_second // 0" | awk '{printf "%.1f", $1/1000000}'
        fi
    }

    _get_ping() {
        local host="$1"
        ping -c 5 -W 2 "$host" 2>/dev/null | grep -oP 'rtt min/avg/max/mdev = [0-9.]+/\K[0-9]+' || echo "N/A"
    }

    _process_test_result() {
        local result="$1"
        local city="$2"
        local host="$3"
        local port="$4"
        local is_fallback="${5:-false}"
        
        local download upload ping_result
        download=$(_parse_speed "$result" "receiver")
        upload=$(_parse_speed "$result" "sender")
        ping_result=$(_get_ping "$host")
        
        if [[ "$download" != "0.0" ]] || [[ "$upload" != "0.0" ]]; then
            local display_city="$city"
            [[ "$is_fallback" == "true" ]] && display_city="$city (F)"
            
            RESULTS+=("$(printf "  %-18s %-15s %-15s %-10s" "$display_city" "${download} Mbps" "${upload} Mbps" "${ping_result} ms")")
            return 0
        fi
        return 1
    }

    _start_iperf_spinner() {
        local msg="$1"
        (
            local chars=("⠇" "⠏" "⠋" "⠙" "⠹" "⠸" "⠼" "⠴" "⠦" "⠧")
            local i=0
            while true; do
                printf "\r  \e[1;36m%s\e[0m \e[97m%s\e[0m" "${chars[$i]}" "$msg"
                i=$(( (i + 1) % ${#chars[@]} ))
                sleep 0.15
            done
        ) &
        SPINNER_PID=$!
    }

    _stop_iperf_spinner() {
        [[ -n "${SPINNER_PID:-}" ]] && kill "$SPINNER_PID" 2>/dev/null
        printf "\r\033[K"
    }

    _test_server() {
        local city="$1"
        local host="$2"
        local fallback_host="$3"
        local fallback_city="${FALLBACK_CITIES[$city]}"
        
        _start_iperf_spinner "Тестирование: $city ($host)..."
        
        local port result
        if port=$(_find_available_port "$host"); then
            if result=$(_test_iperf_server "$host" "$port" "$PARALLEL_STREAMS"); then
                if _process_test_result "$result" "$city" "$host" "$port"; then
                    _stop_iperf_spinner
                    echo -e "  ${C_OK}✓${C_BASE} ${C_WHITE}$city ($host) - Успешно${C_BASE}"
                    return 0
                fi
            fi
            if result=$(_test_iperf_server "$host" "$port" "$FALLBACK_STREAMS"); then
                if _process_test_result "$result" "$city" "$host" "$port"; then
                    _stop_iperf_spinner
                    echo -e "  ${C_OK}✓${C_BASE} ${C_WHITE}$city ($host) - Успешно${C_BASE}"
                    return 0
                fi
            fi
        fi
        
        if fallback_port=$(_find_available_port "$fallback_host"); then
            if result=$(_test_iperf_server "$fallback_host" "$fallback_port" "$PARALLEL_STREAMS"); then
                if _process_test_result "$result" "$fallback_city" "$fallback_host" "$fallback_port" "true"; then
                    _stop_iperf_spinner
                    echo -e "  ${C_OK}✓${C_BASE} ${C_WHITE}$fallback_city ($fallback_host) [Резерв] - Успешно${C_BASE}"
                    return 0
                fi
            fi
            if result=$(_test_iperf_server "$fallback_host" "$fallback_port" "$FALLBACK_STREAMS"); then
                if _process_test_result "$result" "$fallback_city" "$fallback_host" "$fallback_port" "true"; then
                    _stop_iperf_spinner
                    echo -e "  ${C_OK}✓${C_BASE} ${C_WHITE}$fallback_city ($fallback_host) [Резерв] - Успешно${C_BASE}"
                    return 0
                fi
            fi
        fi
        
        _stop_iperf_spinner
        echo -e "  ${C_ERR}✗${C_BASE} ${C_DIM}$city ($host) - Недоступен${C_BASE}"
        RESULTS+=("$(printf "  %-18s %-15s %-15s %-10s" "$city" "---" "---" "N/A")")
        return 1
    }

    echo -e "  ${C_DIM}Запуск тестирования каналов... Это займет около минуты.${C_BASE}\n"
    
    for city in "${CITY_ORDER[@]}"; do
        _test_server "$city" "${SERVERS[$city]}" "${FALLBACK_SERVERS[$city]}"
        [[ ${#CITY_ORDER[@]} -gt 1 ]] && sleep "$INTER_TEST_DELAY"
    done
    
    echo -e "\n  ${C_ACCENT}${C_BOLD}РЕЗУЛЬТАТЫ IPERF3:${C_BASE}"
    echo -e "  ${C_DIM}Источник серверов: github.com/itdoginfo/russian-iperf3-servers${C_BASE}\n"
    printf "  ${C_WHITE}%-18s %-15s %-15s %-10s${C_BASE}\n" "Локация" "Скачивание" "Отдача" "Пинг"
    printf "  ${C_DIM}%-18s %-15s %-15s %-10s${C_BASE}\n" "-------" "----------" "------" "----"
    
    for res in "${RESULTS[@]}"; do
        echo -e "$res"
    done
    echo
}

# ==========================================
# ИНФО О НОДЕ И REALITY
# ==========================================
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
    
    local SNI_DOMAIN="<ВАШ_ДОМЕН>"
    if [ -f "/opt/remnanode/Caddyfile" ]; then
        SNI_DOMAIN=$(grep -oP 'SELF_STEAL_DOMAIN=\K.*' /opt/remnanode/docker-compose.yml 2>/dev/null)
    elif [ -f "/opt/remnanode/nginx.conf" ]; then
        SNI_DOMAIN=$(grep -oP 'server_name \K[^;]+' /opt/remnanode/nginx.conf | head -n 1 2>/dev/null | xargs)
    fi

    echo -e "\n${C_WHITE}Настройки Fallback (для SelfSteal):${C_BASE}"
    echo -e "  dest: ${C_ACCENT}/dev/shm/nginx.sock${C_BASE}"
    echo -e "  show: ${C_ACCENT}false${C_BASE}"
    echo -e "  xver: ${C_ACCENT}1${C_BASE}"
    if [ "$SNI_DOMAIN" != "<ВАШ_ДОМЕН>" ]; then
        echo -e "  SNI:  ${C_ACCENT}${SNI_DOMAIN}${C_BASE}"
    fi
    
    echo -e "\n${C_WHITE}Инфо по подключению ноды:${C_BASE}"
    echo -e "  NODE_PORT (в панели): ${C_ACCENT}2222${C_BASE}"
    echo -e "  Директория логов:     ${C_DIM}/var/log/xray${C_BASE}"
    echo -e "  Конфигурация:         ${C_DIM}/opt/remnanode/docker-compose.yml${C_BASE}"
}

# ==========================================
# IP REGION CHECK
# ==========================================
step_ipregion() {
    draw_sub_header "IP Region Check"
    echo -e "${C_DIM}Инициализация и запуск проверки IP Region...${C_BASE}\n"
    
    _do_ipregion_deps() {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y jq curl util-linux bsdmainutils >/dev/null 2>&1
    }
    run_task "Установка зависимостей (jq, curl, util-linux)" "_do_ipregion_deps"

cat << 'EOF_IPREGION' > /usr/local/bin/ipregion
#!/usr/bin/env bash

SCRIPT_URL="https://github.com/Davoyan/ipregion"
DEPENDENCIES=("jq" "curl" "util-linux")
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
SPINNER_SERVICE_FILE=$(mktemp "${TMPDIR:-/tmp}/ipregion_spinner_XXXXXX")

SPOTIFY_API_KEY="142b583129b2df829de3656f9eb484e6"
SPOTIFY_CLIENT_ID="9a8d2f0ce77a4e248bb71fefcb557637"

VERBOSE=false
JSON_OUTPUT=false
GROUPS_TO_SHOW="all"
CURL_TIMEOUT=6
CURL_RETRIES=1
IPV4_ONLY=false
IPV6_ONLY=false
PROXY_ADDR=""
INTERFACE_NAME=""

RESULT_JSON=""
ARR_PRIMARY=()
ARR_CUSTOM=()
ARR_CDN=()

COLOR_HEADER="1;36"
COLOR_SERVICE="0;92"
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

SELECTED_DOH_URL=""

declare -A DEPENDENCY_COMMANDS=(
  [jq]="jq"
  [curl]="curl"
  [util-linux]="column"
)

declare -A COUNTRY_NAMES=(
  [AF]="Afghanistan"
  [AX]="Åland Islands"
  [AL]="Albania"
  [DZ]="Algeria"
  [AS]="American Samoa"
  [AD]="Andorra"
  [AO]="Angola"
  [AI]="Anguilla"
  [AQ]="Antarctica"
  [AG]="Antigua and Barbuda"
  [AR]="Argentina"
  [AM]="Armenia"
  [AW]="Aruba"
  [AU]="Australia"
  [AT]="Austria"
  [AZ]="Azerbaijan"
  [BS]="Bahamas"
  [BH]="Bahrain"
  [BD]="Bangladesh"
  [BB]="Barbados"
  [BY]="Belarus"
  [BE]="Belgium"
  [BZ]="Belize"
  [BJ]="Benin"
  [BM]="Bermuda"
  [BT]="Bhutan"
  [BO]="Bolivia"
  [BQ]="Bonaire, Sint Eustatius and Saba"
  [BA]="Bosnia and Herzegovina"
  [BW]="Botswana"
  [BV]="Bouvet Island"
  [BR]="Brazil"
  [IO]="British Indian Ocean Territory"
  [BN]="Brunei Darussalam"
  [BG]="Bulgaria"
  [BF]="Burkina Faso"
  [BI]="Burundi"
  [CV]="Cabo Verde"
  [KH]="Cambodia"
  [CM]="Cameroon"
  [CA]="Canada"
  [KY]="Cayman Islands"
  [CF]="Central African Republic"
  [TD]="Chad"
  [CL]="Chile"
  [CN]="China"
  [CX]="Christmas Island"
  [CC]="Cocos (Keeling) Islands"
  [CO]="Colombia"
  [KM]="Comoros"
  [CG]="Congo"
  [CD]="Congo (Democratic Republic of the)"
  [CK]="Cook Islands"
  [CR]="Costa Rica"
  [CI]="Côte d'Ivoire"
  [HR]="Croatia"
  [CU]="Cuba"
  [CW]="Curaçao"
  [CY]="Cyprus"
  [CZ]="Czech Republic"
  [DK]="Denmark"
  [DJ]="Djibouti"
  [DM]="Dominica"
  [DO]="Dominican Republic"
  [EC]="Ecuador"
  [EG]="Egypt"
  [SV]="El Salvador"
  [GQ]="Equatorial Guinea"
  [ER]="Eritrea"
  [EE]="Estonia"
  [SZ]="Eswatini"
  [ET]="Ethiopia"
  [FK]="Falkland Islands (Malvinas)"
  [FO]="Faroe Islands"
  [FJ]="Fiji"
  [FI]="Finland"
  [FR]="France"
  [GF]="French Guiana"
  [PF]="French Polynesia"
  [TF]="French Southern Territories"
  [GA]="Gabon"
  [GM]="Gambia"
  [GE]="Georgia"
  [DE]="Germany"
  [GH]="Ghana"
  [GI]="Gibraltar"
  [GR]="Greece"
  [GL]="Greenland"
  [GD]="Grenada"
  [GP]="Guadeloupe"
  [GU]="Guam"
  [GT]="Guatemala"
  [GG]="Guernsey"
  [GN]="Guinea"
  [GW]="Guinea-Bissau"
  [GY]="Guyana"
  [HT]="Haiti"
  [HM]="Heard Island and McDonald Islands"
  [VA]="Holy See"
  [HN]="Honduras"
  [HK]="Hong Kong"
  [HU]="Hungary"
  [IS]="Iceland"
  [IN]="India"
  [ID]="Indonesia"
  [IR]="Iran"
  [IQ]="Iraq"
  [IE]="Ireland"
  [IM]="Isle of Man"
  [IL]="Israel"
  [IT]="Italy"
  [JM]="Jamaica"
  [JP]="Japan"
  [JE]="Jersey"
  [JO]="Jordan"
  [KZ]="Kazakhstan"
  [KE]="Kenya"
  [KI]="Kiribati"
  [KP]="Korea (Democratic People's Republic of)"
  [KR]="Korea (Republic of)"
  [KW]="Kuwait"
  [KG]="Kyrgyzstan"
  [LA]="Lao People's Democratic Republic"
  [LV]="Latvia"
  [LB]="Lebanon"
  [LS]="Lesotho"
  [LR]="Liberia"
  [LY]="Libya"
  [LI]="Liechtenstein"
  [LT]="Lithuania"
  [LU]="Luxembourg"
  [MO]="Macao"
  [MG]="Madagascar"
  [MW]="Malawi"
  [MY]="Malaysia"
  [MV]="Maldives"
  [ML]="Mali"
  [MT]="Malta"
  [MH]="Marshall Islands"
  [MQ]="Martinique"
  [MR]="Mauritania"
  [MU]="Mauritius"
  [YT]="Mayotte"
  [MX]="Mexico"
  [FM]="Micronesia (Federated States of)"
  [MD]="Moldova"
  [MC]="Monaco"
  [MN]="Mongolia"
  [ME]="Montenegro"
  [MS]="Montserrat"
  [MA]="Morocco"
  [MZ]="Mozambique"
  [MM]="Myanmar"
  [NA]="Namibia"
  [NR]="Nauru"
  [NP]="Nepal"
  [NL]="Netherlands"
  [NC]="New Caledonia"
  [NZ]="New Zealand"
  [NI]="Nicaragua"
  [NE]="Niger"
  [NG]="Nigeria"
  [NU]="Niue"
  [NF]="Norfolk Island"
  [MK]="North Macedonia"
  [MP]="Northern Mariana Islands"
  [NO]="Norway"
  [OM]="Oman"
  [PK]="Pakistan"
  [PW]="Palau"
  [PS]="Palestine"
  [PA]="Panama"
  [PG]="Papua New Guinea"
  [PY]="Paraguay"
  [PE]="Peru"
  [PH]="Philippines"
  [PN]="Pitcairn"
  [PL]="Poland"
  [PT]="Portugal"
  [PR]="Puerto Rico"
  [QA]="Qatar"
  [RE]="Réunion"
  [RO]="Romania"
  [RU]="Russia"
  [RW]="Rwanda"
  [BL]="Saint Barthélemy"
  [SH]="Saint Helena"
  [KN]="Saint Kitts and Nevis"
  [LC]="Saint Lucia"
  [MF]="Saint Martin (French part)"
  [PM]="Saint Pierre and Miquelon"
  [VC]="Saint Vincent and the Grenadines"
  [WS]="Samoa"
  [SM]="San Marino"
  [ST]="Sao Tome and Principe"
  [SA]="Saudi Arabia"
  [SN]="Senegal"
  [RS]="Serbia"
  [SC]="Seychelles"
  [SL]="Sierra Leone"
  [SG]="Singapore"
  [SX]="Sint Maarten (Dutch part)"
  [SK]="Slovakia"
  [SI]="Slovenia"
  [SB]="Solomon Islands"
  [SO]="Somalia"
  [ZA]="South Africa"
  [GS]="South Georgia and the South Sandwich Islands"
  [SS]="South Sudan"
  [ES]="Spain"
  [LK]="Sri Lanka"
  [SD]="Sudan"
  [SR]="Suriname"
  [SJ]="Svalbard and Jan Mayen"
  [SE]="Sweden"
  [CH]="Switzerland"
  [SY]="Syrian Arab Republic"
  [TW]="Taiwan"
  [TJ]="Tajikistan"
  [TZ]="Tanzania"
  [TH]="Thailand"
  [TL]="Timor-Leste"
  [TG]="Togo"
  [TK]="Tokelau"
  [TO]="Tonga"
  [TT]="Trinidad and Tobago"
  [TN]="Tunisia"
  [TR]="Turkey"
  [TM]="Turkmenistan"
  [TC]="Turks and Caicos Islands"
  [TV]="Tuvalu"
  [UG]="Uganda"
  [UA]="Ukraine"
  [AE]="United Arab Emirates"
  [GB]="United Kingdom"
  [US]="United States"
  [UM]="United States Minor Outlying Islands"
  [UY]="Uruguay"
  [UZ]="Uzbekistan"
  [VU]="Vanuatu"
  [VE]="Venezuela"
  [VN]="Vietnam"
  [VG]="Virgin Islands (British)"
  [VI]="Virgin Islands (U.S.)"
  [WF]="Wallis and Futuna"
  [EH]="Western Sahara"
  [YE]="Yemen"
  [ZM]="Zambia"
  [ZW]="Zimbabwe"
  [XK]="Kosovo"
  [EU]="European Union"
  [WW]="Worldwide"
)

declare -A PRIMARY_SERVICES=(
  [MAXMIND]="maxmind.com|geoip.maxmind.com|/geoip/v2.1/city/me"
  [RIPE]="rdap.db.ripe.net|rdap.db.ripe.net|/ip/{ip}"
  [IPINFO_IO]="ipinfo.io|ipinfo.io|/widget/demo/{ip}"
  [IPREGISTRY]="ipregistry.co|api.ipregistry.co|/{ip}?hostname=true&key=sb69ksjcajfs4c"
  [IPAPI_CO]="ipapi.co|ipapi.co|/{ip}/json"
  [CLOUDFLARE]="cloudflare.com|www.cloudflare.com|/cdn-cgi/trace"
  [IPLOCATION_COM]="iplocation.com|iplocation.com"
  [COUNTRY_IS]="country.is|api.country.is|/{ip}"
  [GEOAPIFY_COM]="geoapify.com|api.geoapify.com|/v1/ipinfo?&ip={ip}&apiKey=b8568cb9afc64fad861a69edbddb2658"
  [GEOJS_IO]="geojs.io|get.geojs.io|/v1/ip/country.json?ip={ip}"
  [IPAPI_IS]="ipapi.is|api.ipapi.is|/?q={ip}"
  [IPBASE_COM]="ipbase.com|api.ipbase.com|/v2/info?ip={ip}"
  [IPQUERY_IO]="ipquery.io|api.ipquery.io|/{ip}"
  [IPWHO_IS]="ipwho.is|ipwho.is|/{ip}"
  [IPAPI_COM]="ip-api.com|demo.ip-api.com|/json/{ip}?fields=countryCode"
  [2IP]="2ip.io|api.2ip.io"
)

PRIMARY_SERVICES_ORDER=(
  "MAXMIND"
  "RIPE"
  "IPINFO_IO"
  "CLOUDFLARE"
  "IPREGISTRY"
  "IPAPI_CO"
  "IPLOCATION_COM"
  "COUNTRY_IS"
  "GEOAPIFY_COM"
  "GEOJS_IO"
  "IPAPI_IS"
  "IPBASE_COM"
  "IPQUERY_IO"
  "IPWHO_IS"
  "IPAPI_COM"
  "2IP"
)

declare -A PRIMARY_SERVICES_CUSTOM_HANDLERS=(
  [CLOUDFLARE]="lookup_cloudflare"
  [IPLOCATION_COM]="lookup_iplocation_com"
  [2IP]="lookup_2ip"
)

declare -A SERVICE_HEADERS=(
  [IPREGISTRY]="Origin: https://ipregistry.co"
  [MAXMIND]="Referer: https://www.maxmind.com"
  [IPAPI_COM]="Origin: https://ip-api.com"
)

declare -A CUSTOM_SERVICES=(
  [GOOGLE]="Google"
  [GOOGLE_SEARCH_CAPTCHA]="Google Search Captcha"
  [YOUTUBE]="YouTube"
  [YOUTUBE_PREMIUM]="YouTube Premium"
  [YOUTUBE_MUSIC]="YouTube Music"
  [TWITCH]="Twitch"
  [CHATGPT]="ChatGPT"
  [NETFLIX]="Netflix"
  [SPOTIFY]="Spotify"
  [SPOTIFY_SIGNUP]="Spotify Signup"
  [DEEZER]="Deezer"
  [REDDIT]="Reddit"
  [REDDIT_GUEST_ACCESS]="Reddit (Guest Access)"
  [AMAZON_PRIME]="Amazon Prime"
  [APPLE]="Apple"
  [STEAM]="Steam"
  [PLAYSTATION]="PlayStation"
  [TIKTOK]="Tiktok"
  [YOUTUBE_CDN]="YouTube CDN"
  [OOKLA_SPEEDTEST]="Ookla Speedtest"
  [JETBRAINS]="JetBrains"
  [BING]="Microsoft (Bing)"
)

CUSTOM_SERVICES_ORDER=(
  "GOOGLE"
  "GOOGLE_SEARCH_CAPTCHA"
  "YOUTUBE"
  "YOUTUBE_PREMIUM"
  "YOUTUBE_MUSIC"
  "TWITCH"
  "CHATGPT"
  "NETFLIX"
  "SPOTIFY"
  "SPOTIFY_SIGNUP"
  "DEEZER"
  "REDDIT"
  "REDDIT_GUEST_ACCESS"
  "AMAZON_PRIME"
  "APPLE"
  "STEAM"
  "PLAYSTATION"
  "TIKTOK"
  "OOKLA_SPEEDTEST"
  "JETBRAINS"
  "BING"
)

declare -A CUSTOM_SERVICES_HANDLERS=(
  [GOOGLE]="lookup_google"  
  [GOOGLE_SEARCH_CAPTCHA]="lookup_google_search_captcha"
  [YOUTUBE]="lookup_youtube"
  [YOUTUBE_PREMIUM]="lookup_youtube_premium"
  [YOUTUBE_MUSIC]="lookup_youtube_music"
  [TWITCH]="lookup_twitch"
  [CHATGPT]="lookup_chatgpt"
  [NETFLIX]="lookup_netflix"
  [SPOTIFY]="lookup_spotify"
  [SPOTIFY_SIGNUP]="lookup_spotify_signup"
  [DEEZER]="lookup_deezer"
  [REDDIT]="lookup_reddit"
  [REDDIT_GUEST_ACCESS]="lookup_reddit_guest_access"
  [AMAZON_PRIME]="lookup_amazon_prime"
  [APPLE]="lookup_apple"
  [STEAM]="lookup_steam"
  [PLAYSTATION]="lookup_playstation"
  [TIKTOK]="lookup_tiktok"
  [CLOUDFLARE_CDN]="lookup_cloudflare_cdn"
  [YOUTUBE_CDN]="lookup_youtube_cdn"
  [NETFLIX_CDN]="lookup_netflix_cdn"
  [OOKLA_SPEEDTEST]="lookup_ookla_speedtest"
  [JETBRAINS]="lookup_jetbrains"
  [BING]="lookup_bing"
)

declare -A CDN_SERVICES=(
  [YOUTUBE_CDN]="YouTube CDN"
  [NETFLIX_CDN]="Netflix CDN"
)

CDN_SERVICES_ORDER=(
  "YOUTUBE_CDN"
  "NETFLIX_CDN"
)

declare -A SERVICE_GROUPS=(
  [primary]="${PRIMARY_SERVICES_ORDER[*]}"
  [custom]="${CUSTOM_SERVICES_ORDER[*]}"
  [cdn]="${CDN_SERVICES_ORDER[*]}"
)

EXCLUDED_SERVICES=(
  # "IPINFO_IO"
  # "IPREGISTRY"
  # "IPAPI_CO"
)

IDENTITY_SERVICES=(
  "ident.me"
  "ifconfig.me"
  "api64.ipify.org"
  "ifconfig.me"
)

IPV6_OVER_IPV4_SERVICES=(
  "IPINFO_IO"
)

get_tmpdir() {
  if [[ -n "$TMPDIR" ]]; then
    echo "$TMPDIR"
  elif [[ -d /data/data/com.termux/files/usr/tmp ]]; then
    echo "/data/data/com.termux/files/usr/tmp"
  else
    echo "/tmp"
  fi
}

color() {
  local color_name="$1"
  local text="$2"
  local code

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

bold() {
  local text="$1"
  printf "\033[1m%s\033[0m" "$text"
}

get_timestamp() {
  local format="$1"
  date +"$format"
}

log() {
  local log_level="$1"
  local message="${*:2}"
  local timestamp

  if [[ "$VERBOSE" == true ]]; then
    local color_code

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
  local message="$1"
  local exit_code="${2:-1}"
  printf "%s %s\n" "$(color ERROR '[ERROR]')" "$(color TABLE_HEADER "$message")" >&2
  display_help
  exit "$exit_code"
}

display_help() {
  cat <<EOF

Usage: $0 [OPTIONS]

IPRegion — determines your IP geolocation using various GeoIP services and popular websites

Options:
  -h, --help           Show this help message and exit
  -v, --verbose        Enable verbose logging
  -j, --json           Output results in JSON format
  -g, --group GROUP    Run only one group: 'primary', 'custom', 'cdn', or 'all' (default: all)
  -t, --timeout SEC    Set curl request timeout in seconds (default: $CURL_TIMEOUT)
  -4, --ipv4           Test only IPv4
  -6, --ipv6           Test only IPv6
  -p, --proxy ADDR     Use SOCKS5 proxy (format: host:port)
  -i, --interface IF   Use specified network interface (e.g. eth1)

Examples:
  $0                       # Check all services with default settings
  $0 -g primary            # Check only GeoIP services
  $0 -g custom             # Check only popular websites
  $0 -g cdn                # Check only CDN endpoints
  $0 -4                    # Test only IPv4
  $0 -6                    # Test only IPv6
  $0 -p 127.0.0.1:1080     # Use SOCKS5 proxy
  $0 -i eth1               # Use network interface eth1
  $0 -j                    # Output result as JSON
  $0 -v                    # Enable verbose logging

EOF
}

is_installed() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1
}

check_missing_dependencies() {
  local missing_pkgs=()
  local cmd

  for pkg in "${DEPENDENCIES[@]}"; do
    cmd="${DEPENDENCY_COMMANDS[$pkg]:-$pkg}"
    if ! is_installed "$cmd"; then
      missing_pkgs+=("$pkg")
    fi
  done

  echo "${missing_pkgs[@]}"
}

prompt_for_installation() {
  local missing_pkgs=("$@")

  echo "Missing dependencies: ${missing_pkgs[*]}"
  read -r -p "Do you want to install them? [y/N]: " answer
  answer=${answer,,}

  case "${answer,,}" in
    y | yes)
      return 0
      ;;
    *)
      exit 0
      ;;
  esac
}

get_package_manager() {
  # Check if the script is running in Termux
  if [[ -d /data/data/com.termux ]]; then
    echo "termux"
    return
  fi

  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "$ID" in
      debian | ubuntu)
        echo "apt"
        ;;
      arch)
        echo "pacman"
        ;;
      fedora)
        echo "dnf"
        ;;
      *)
        error_exit "Unknown distribution: $ID. Please install dependencies manually."
        ;;
    esac
  else
    error_exit "File /etc/os-release not found, unable to determine distribution. Please install dependencies manually."
  fi
}

install_with_package_manager() {
  local pkg_manager="$1"
  local packages=("${@:2}")
  local use_sudo=""

  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    use_sudo="sudo"
    log "$LOG_INFO" "Running as non-root user, using sudo"
  fi

  case "$pkg_manager" in
    *apt)
      $use_sudo "$pkg_manager" update
      if [[ " ${packages[*]} " == *" util-linux "* ]]; then
        $use_sudo env NEEDRESTART_MODE=a "$pkg_manager" install -y util-linux bsdmainutils
      fi
      $use_sudo env NEEDRESTART_MODE=a "$pkg_manager" install -y "${packages[@]}"
      ;;
    *pacman)
      $use_sudo "$pkg_manager" -Syy --noconfirm "${packages[@]}"
      ;;
    *dnf)
      $use_sudo "$pkg_manager" install -y "${packages[@]}"
      ;;
    termux)
      apt update
      apt install -y "${packages[@]}"
      ;;
    *)
      error_exit "Unknown package manager: $pkg_manager"
      ;;
  esac
}

install_dependencies() {
  local missing_packages
  local pkg_manager

  log "$LOG_INFO" "Checking for dependencies"
  read -r -a missing_packages <<<"$(check_missing_dependencies)"

  if [[ ${#missing_packages[@]} -eq 0 ]]; then
    log "$LOG_INFO" "All dependencies are installed"
    return 0
  fi

  prompt_for_installation "${missing_packages[@]}" </dev/tty

  pkg_manager=$(get_package_manager)
  log "$LOG_INFO" "Detected package manager: $pkg_manager"

  log "$LOG_INFO" "Installing missing dependencies"
  install_with_package_manager "$pkg_manager" "${missing_packages[@]}"
}

is_valid_json() {
  local json="$1"
  jq -e . >/dev/null 2>&1 <<<"$json"
}

process_json() {
  local json="$1"
  local jq_filter="$2"
  jq -r "$jq_filter" <<<"$json"
}

format_value() {
  local value="$1"
  local not_available="$2"

  if [[ "$value" == "$not_available" ]]; then
    color NULL "$value"
  else
    bold "$value"
  fi
}

print_value_or_colored() {
  local value="$1"
  local color_name="$2"

  if [[ "$JSON_OUTPUT" == true ]]; then
    echo "$value"
    return
  fi

  color "$color_name" "$value"
}

mask_ipv4() {
  local ip="$1"
  echo "${ip%.*.*}.*.*"
}

mask_ipv6() {
  local ip="$1"
  echo "$ip" | awk -F: '{
    for(i=1;i<=NF;i++) if($i=="") $i="0";
    while(NF<8) for(i=1;i<=8;i++) if($i=="0"){NF++; break;}
    printf "%s:%s:%s::\n", $1, $2, $3
  }'
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -h | --help)
        display_help
        exit 0
        ;;
      -v | --verbose)
        VERBOSE=true
        shift
        ;;
      -j | --json)
        JSON_OUTPUT=true
        shift
        ;;
      -g | --group)
        GROUPS_TO_SHOW="$2"
        shift 2
        ;;
      -t | --timeout)
        if [[ "$2" =~ ^[0-9]+$ ]]; then
          CURL_TIMEOUT="$2"
        else
          error_exit "Invalid timeout value: $2. Timeout must be a positive integer"
        fi
        shift 2
        ;;
      -4 | --ipv4)
        IPV4_ONLY=true
        shift
        ;;
      -6 | --ipv6)
        if ! check_ip_support 6; then
          error_exit "IPv6 is not supported on this system"
        fi

        IPV6_ONLY=true
        shift
        ;;
      -p | --proxy)
        PROXY_ADDR="$2"
        log "$LOG_INFO" "Using SOCKS5 proxy: $PROXY_ADDR"
        shift 2
        ;;
      -i | --interface)
        INTERFACE_NAME="$2"
        log "$LOG_INFO" "Using interface: $INTERFACE_NAME"
        shift 2
        ;;
      *)
        error_exit "Unknown option: $1"
        ;;
    esac
  done
}

check_ip_support() {
  local version="$1"
  log "$LOG_INFO" "Checking for IPv${version} support"

  if ip -${version} addr show scope global 2>/dev/null | grep -q "inet${version//4/ }"; then
    log "$LOG_INFO" "IPv${version} is supported"
    return 0
  fi

  log "$LOG_WARN" "IPv${version} is not supported on this system"
  return 1
}

IDENTITY_SERVICES=(
  "ident.me"
  "ifconfig.me"
  "api64.ipify.org"
  "ifconfig.me"
)

get_external_ip() {
  local results=()
  local ip
  local counts
  declare -A counts

  if [[ "$IPV4_ONLY" == true ]] || [[ "$IPV6_ONLY" != true ]]; then
    log "$LOG_INFO" "Checking external IPv4 addresses"
    for service in "${IDENTITY_SERVICES[@]}"; do
      ip="$(make_request GET "https://$service" --ip-version 4 2>/dev/null)"
      if [[ -n "$ip" ]]; then
        counts[$ip]=$(( ${counts[$ip]:-0} + 1 ))
        log "$LOG_INFO" "[$service] IPv4: $ip"
      fi
    done

    EXTERNAL_IPV4=""
    for ip in "${!counts[@]}"; do
      if [[ ${counts[$ip]} -ge 2 ]]; then
        EXTERNAL_IPV4="$ip"
        log "$LOG_INFO" "Confirmed external IPv4: $EXTERNAL_IPV4"
        break
      fi
    done

    # Fallback, если совпадений нет
    if [[ -z "$EXTERNAL_IPV4" ]]; then
      for ip in "${!counts[@]}"; do
        EXTERNAL_IPV4="$ip"
        log "$LOG_INFO" "Fallback external IPv4: $EXTERNAL_IPV4"
        break
      done
    fi
  fi

  unset counts
  declare -A counts
  if [[ "$IPV6_ONLY" == true ]] || { [[ "$IPV6_SUPPORTED" -eq 0 ]] && [[ "$IPV4_ONLY" != true ]]; }; then
    log "$LOG_INFO" "Checking external IPv6 addresses"
    for service in "${IDENTITY_SERVICES[@]}"; do
      ip="$(make_request GET "https://$service" --ip-version 6 2>/dev/null)"
      if [[ -n "$ip" ]]; then
        counts[$ip]=$(( ${counts[$ip]:-0} + 1 ))
        log "$LOG_INFO" "[$service] IPv6: $ip"
      fi
    done

    EXTERNAL_IPV6=""
    for ip in "${!counts[@]}"; do
      if [[ ${counts[$ip]} -ge 2 ]]; then
        EXTERNAL_IPV6="$ip"
        log "$LOG_INFO" "Confirmed external IPv6: $EXTERNAL_IPV6"
        break
      fi
    done

    if [[ -z "$EXTERNAL_IPV6" ]]; then
      for ip in "${!counts[@]}"; do
        EXTERNAL_IPV6="$ip"
        log "$LOG_INFO" "Fallback external IPv6: $EXTERNAL_IPV6"
        break
      done
    fi
  fi
}

get_asn() {
  local ip ip_version response

  if [[ -n "$EXTERNAL_IPV4" ]]; then
    ip="$EXTERNAL_IPV4"
    ip_version=4
  else
    ip="$EXTERNAL_IPV6"
    ip_version=6
  fi

  log "$LOG_INFO" "Getting ASN info for IP $ip"

  response=$(make_request GET "https://ipinfo.check.place/$ip" --ip-version "$ip_version" 2>/dev/null)
  asn=$(process_json "$response" ".ASN.AutonomousSystemNumber")
  asn_name=$(process_json "$response" ".ASN.AutonomousSystemOrganization")

  if [[ -z "$asn" || "$asn" == "null" || -z "$asn_name" || "$asn_name" == "null" ]]; then
    log "$LOG_INFO" "Primary source failed, trying backup source"
    response=$(make_request GET "https://geoip.oxl.app/api/ip/$ip" --ip-version "$ip_version")
    asn=$(process_json "$response" ".asn")
    asn_name=$(process_json "$response" ".organization.name")
    asn_name=${asn_name#null}
    log "$LOG_INFO" "ASN info (backup source): AS$asn $asn_name"
  else
    log "$LOG_INFO" "ASN info (primary source): AS$asn $asn_name"
  fi
}

get_iata_location() {
  local iata_code="$1"
  local url="https://www.air-port-codes.com/api/v1/single"
  local payload="iata=$iata_code"
  local apc_auth="96dc04b3fb"
  local referer="https://www.air-port-codes.com/"
  local response

  response=$(make_request POST "$url" \
    --header "APC-Auth: $apc_auth" \
    --header "Referer: $referer" \
    --data "$payload" \
    --ip-version 4)

  process_json "$response" ".airport.country.iso"
}

is_ipv6_over_ipv4_service() {
  local service="$1"
  for s in "${IPV6_OVER_IPV4_SERVICES[@]}"; do
    [[ "$s" == "$service" ]] && return 0
  done
  return 1
}

spinner_start() {
  local delay=0.1
  # shellcheck disable=SC1003
  local spinstr='|/-\\'
  local current_service

  spinner_running=true

  (
    while $spinner_running; do
      for ((i = 0; i < ${#spinstr}; i++)); do
        current_service=""

        if [[ -f "$SPINNER_SERVICE_FILE" ]]; then
          current_service="$(cat "$SPINNER_SERVICE_FILE")"
        fi

        printf "\r\033[K%s %s %s" \
          "$(color HEADER "${spinstr:$i:1}")" \
          "$(color HEADER "Checking:")" \
          "$(color SERVICE "$current_service")"

        sleep $delay
      done
    done
  ) &

  spinner_pid=$!
}

spinner_stop() {
  spinner_running=false

  if [[ -n "$spinner_pid" ]]; then
    kill "$spinner_pid" 2>/dev/null
    wait "$spinner_pid" 2>/dev/null
    spinner_pid=""
    printf "\\r%*s\\r" 40 " "
  fi

  if [[ -f "$SPINNER_SERVICE_FILE" ]]; then
    rm -f "$SPINNER_SERVICE_FILE"
    unset SPINNER_SERVICE_FILE
  fi
}

make_request() {
  local method="$1"
  local url="$2"
  shift 2
  local ip_version user_agent json data headers response_with_code response http_code
  local curl_args=(
    --silent --compressed
    --retry-connrefused --retry-all-errors
    --retry "$CURL_RETRIES"
    --connect-timeout "$CURL_TIMEOUT"
    --max-time "$CURL_TIMEOUT"
    --request "$method"
    -w '\n%{http_code}'
  )

  while (($#)); do
    case "$1" in
      --ip-version)
        ip_version="$2"
        shift 2
        ;;
      --user-agent)
        user_agent="$2"
        shift 2
        ;;
      --header)
        headers+=("$2")
        shift 2
        ;;
      --json)
        json="$2"
        shift 2
        ;;
      --data)
        data="$2"
        shift 2
        ;;
    esac
  done

  if [[ "$ip_version" == "4" ]]; then
    curl_args+=(-4)
  else
    curl_args+=(-6)
  fi

  for h in "${headers[@]}"; do
    curl_args+=(-H "$h")
  done

  if [[ -n "$user_agent" ]]; then
    curl_args+=(-A "$user_agent")
  fi

  if [[ -n "$json" ]]; then
    curl_args+=(--data "$json")
    curl_args+=(-H 'Content-Type: application/json')
  fi

  if [[ -n "$data" ]]; then
    curl_args+=(--data "$data")
    curl_args+=(-H 'Content-Type: application/x-www-form-urlencoded')
  fi

  if [[ -n "$PROXY_ADDR" ]]; then
    curl_args+=(--proxy "socks5://$PROXY_ADDR")
  fi

  if [[ -n "$INTERFACE_NAME" ]]; then
    curl_args+=(--interface "$INTERFACE_NAME")
  fi

  curl_args+=("$url")

  response_with_code=$(timeout "$CURL_TIMEOUT"s curl "${curl_args[@]}" $SELECTED_DOH_URL)
  local exit_status=$?

  if [[ $exit_status -eq 124 ]]; then
    echo ""
    return 0
  fi

  http_code=$(tail -n1 <<<"$response_with_code")
  response=$(sed '$d' <<<"$response_with_code")

  if [[ "$http_code" == "403" || "$http_code" == "429" ]]; then
    echo ""
    return 0
  fi

  echo "$response"
}

service_build_request() {
  local service="$1" ip="$2" ip_version="$3"
  local cfg="${PRIMARY_SERVICES[$service]}"
  local display_name domain url_template url headers_str response_format

  IFS='|' read -r display_name domain url_template response_format <<<"$cfg"

  if [[ -z "$display_name" ]]; then
    display_name="$service"
  fi

  url="https://$domain${url_template//\{ip\}/$ip}"

  if [[ -n "${SERVICE_HEADERS[$service]}" ]]; then
    headers_str="${SERVICE_HEADERS[$service]}"
  fi

  printf "%s\n%s\n%s\n%s" "$display_name" "$url" "${response_format:-json}" "$headers_str"
}

probe_service() {
  local service="$1"
  local ip_version="$2"
  local ip="$3"
  local built display_name url response_format headers_line request_params response

  mapfile -t built < <(service_build_request "$service" "$ip" "$ip_version")
  display_name="${built[0]}"
  url="${built[1]}"
  response_format="${built[2]}"
  headers_line="${built[3]}"

  if [[ -n "$headers_line" ]]; then
    IFS='||' read -ra hs <<<"$headers_line"
    for h in "${hs[@]}"; do
      if [[ -n "$h" ]]; then
        request_params+=(--header "$h")
      fi
    done
  fi

  if [[ "$ip_version" == "6" ]] && is_ipv6_over_ipv4_service "$service"; then
    ip_version="4"
  fi

  response=$(make_request GET "$url" "${request_params[@]}" --ip-version "$ip_version")

  process_response "$service" "$response" "$display_name" "$response_format"
}

process_response() {
  local service="$1"
  local response="$2"
  local display_name="$3"
  local response_format="${4:-json}"
  local jq_filter

  if [[ -z "$response" || "$response" == *"<html"* ]]; then
    echo "N/A"
    return
  fi

  if [[ "$response_format" == "plain" ]]; then
    echo "$response" | tr -d '\r\n '
    return
  fi

  if ! is_valid_json "$response"; then
    log "$LOG_ERROR" "Invalid JSON response from $display_name: $response"
    return 1
  fi

  case "$service" in
    MAXMIND)
      jq_filter='.country.iso_code'
      ;;
    RIPE)
      jq_filter='.country'
      ;;
    IPINFO_IO)
      jq_filter='.data.country'
      ;;
    IPREGISTRY)
      jq_filter='.location.country.code'
      ;;
    IPAPI_CO)
      jq_filter='.country'
      ;;
    COUNTRY_IS)
      jq_filter='.country'
      ;;
    GEOAPIFY_COM)
      jq_filter='.country.iso_code'
      ;;
    GEOJS_IO)
      jq_filter='.[0].country'
      ;;
    IPAPI_IS)
      jq_filter='.location.country_code'
      ;;
    IPBASE_COM)
      jq_filter='.data.location.country.alpha2'
      ;;
    IPQUERY_IO)
      jq_filter='.location.country_code'
      ;;
    IPWHO_IS)
      jq_filter='.country_code'
      ;;
    IPAPI_COM)
      jq_filter='.countryCode'
      ;;
    *)
      echo "$response"
      ;;
  esac

  process_json "$response" "$jq_filter"
}

process_service() {
  local service="$1"
  local custom="${2:-false}"
  local service_config="${PRIMARY_SERVICES[$service]}"
  local display_name domain url_template response_format ipv4_result ipv6_result handler_func

  IFS='|' read -r display_name domain url_template response_format <<<"$service_config"

  if [[ -z "$display_name" ]]; then
    display_name="$service"
  fi

  if [[ -n "$SPINNER_SERVICE_FILE" ]]; then
    echo "$display_name" >"$SPINNER_SERVICE_FILE"
  fi

  if [[ "$custom" == true ]]; then
    process_custom_service "$service"
    return
  fi

  if [[ -n "${PRIMARY_SERVICES_CUSTOM_HANDLERS[$service]}" ]]; then
    handler_func="${PRIMARY_SERVICES_CUSTOM_HANDLERS[$service]}"

    log "$LOG_INFO" "Checking $display_name via IPv4 (custom handler)"

    ipv4_result=$("$handler_func" 4)

    if [[ "$IPV6_ONLY" == true ]] || { [[ "$IPV6_SUPPORTED" -eq 0 && -n "$EXTERNAL_IPV6" ]] && [[ "$IPV4_ONLY" != true ]]; }; then
      log "$LOG_INFO" "Checking $display_name via IPv6 (custom handler)"
      ipv6_result=$("$handler_func" 6)
    else
      ipv6_result=""
    fi

    add_result "primary" "$display_name" "$ipv4_result" "$ipv6_result"
    return
  fi

  if [[ "$IPV6_ONLY" != true ]]; then
    if [[ -n "$EXTERNAL_IPV4" ]]; then
      log "$LOG_INFO" "Checking $display_name via IPv4"
      ipv4_result=$(probe_service "$service" 4 "$EXTERNAL_IPV4")
    fi
  fi

  if [[ "$IPV4_ONLY" != true ]]; then
    if [[ "$IPV6_SUPPORTED" -eq 0 && -n "$EXTERNAL_IPV6" ]]; then
      if is_ipv6_over_ipv4_service "$service"; then
        log "$LOG_INFO" "Checking $display_name (IPv6 address, IPv4 transport)"
      else
        log "$LOG_INFO" "Checking $display_name via IPv6"
      fi
      ipv6_result=$(probe_service "$service" 6 "$EXTERNAL_IPV6")
    fi
  fi
  
  ipv4_clean=${ipv4_result#null}
  ipv6_clean=${ipv6_result#null}

  add_result "primary" "$display_name" "$ipv4_clean" "$ipv6_clean"

}

process_custom_service() {
  local service="$1"
  local ipv4_result ipv6_result
  local display_name="${CUSTOM_SERVICES[$service]:-$service}"
  local handler_func="${CUSTOM_SERVICES_HANDLERS[$service]}"

  if [[ -z "$display_name" ]]; then
    display_name="$service"
  fi

  echo "$display_name" >"$SPINNER_SERVICE_FILE"

  if [[ -z "$handler_func" ]]; then
    log "$LOG_WARN" "Unknown custom service: $service"
    return
  fi

  if [[ "$IPV6_ONLY" != true ]]; then
    log "$LOG_INFO" "Checking $display_name via IPv4"
    ipv4_result=$("$handler_func" 4)
  else
    ipv4_result=""
  fi

  if [[ "$IPV4_ONLY" != true ]] && [[ "$IPV6_SUPPORTED" -eq 0 && -n "$EXTERNAL_IPV6" ]]; then
    log "$LOG_INFO" "Checking $display_name via IPv6"
    ipv6_result=$("$handler_func" 6)
  else
    ipv6_result=""
  fi

  add_result "custom" "$display_name" "$ipv4_result" "$ipv6_result"
}

run_service_group() {
  local group="$1"
  local services_string="${SERVICE_GROUPS[$group]}"
  local is_custom=false
  local is_cdn=false
  local services_array service_name handler_func display_name result

  read -ra services_array <<<"$services_string"

  log "$LOG_INFO" "Running $group group services"

  for service_name in "${services_array[@]}"; do
    if printf "%s\n" "${EXCLUDED_SERVICES[@]}" | grep -Fxq "$service_name"; then
      log "$LOG_INFO" "Skipping service: $service_name"
      continue
    fi

    if [[ "$group" == "custom" ]]; then
      is_custom=true
    else
      is_custom=false
    fi

    if [[ "$group" == "cdn" ]]; then
      is_cdn=true
    else
      is_cdn=false
    fi

    if [[ "$is_custom" == true ]]; then
      process_service "$service_name" true
    elif [[ "$is_cdn" == true ]]; then
      handler_func="${CUSTOM_SERVICES_HANDLERS[$service_name]}"
      display_name="${CDN_SERVICES[$service_name]}"

      if [[ -n "$handler_func" ]]; then
		  echo "$display_name" >"$SPINNER_SERVICE_FILE"

		  ipv4_result=""
		  ipv6_result=""

		  if [[ "$IPV6_ONLY" != true ]]; then
			ipv4_result=$("$handler_func" 4)
		  fi

		  if [[ "$IPV4_ONLY" != true ]] && [[ "$IPV6_SUPPORTED" -eq 0 && -n "$EXTERNAL_IPV6" ]]; then
			ipv6_result=$("$handler_func" 6)
		  fi

		  add_result "cdn" "$display_name" "$ipv4_result" "$ipv6_result"
		fi

    else
      process_service "$service_name"
    fi
  done
}

run_all_services() {
  local service_name

  for func in $(declare -F | awk '{print $3}' | grep '^lookup_'); do
    service_name=${func#lookup_}
    service_name_uppercase=${service_name^^}

    if printf "%s\n" "${EXCLUDED_SERVICES[@]}" | grep -Fxq "$service_name_uppercase"; then
      log "$LOG_INFO" "Skipping service: $service_name_uppercase"
      continue
    fi

    if [[ -n "${CUSTOM_SERVICES[$service_name_uppercase]}" ]]; then
      process_service "$service_name_uppercase" true
      continue
    fi

    "$func"
  done
}

finalize_json() {
  local t_primary t_custom t_cdn
  local IFS=$'\n'

  if ((${#ARR_PRIMARY[@]} > 0)); then
    t_primary=$(printf '%s\n' "${ARR_PRIMARY[@]//|||/$'\t'}")
  fi

  if ((${#ARR_CUSTOM[@]} > 0)); then
    t_custom=$(printf '%s\n' "${ARR_CUSTOM[@]//|||/$'\t'}")
  fi

  if ((${#ARR_CDN[@]} > 0)); then
    t_cdn=$(printf '%s\n' "${ARR_CDN[@]//|||/$'\t'}")
  fi

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
          ($raw | split("\n"))
          | map(select(length > 0))
          | map(
              (split("\t")) as $f
              | {
                  service: $f[0],
                  ipv4: ( ($f[1] // "") | if length>0 then . else null end ),
                  ipv6: ( ($f[2] // "") | if length>0 then . else null end )
                }
            )
          end;

        {
          version: ($version|tonumber),
          ipv4: ($ipv4 | select(length > 0) // null),
          ipv6: ($ipv6 | select(length > 0) // null),
          results: {
            primary: lines_to_array($p),
            custom:  lines_to_array($c),
            cdn:     lines_to_array($d)
          }
        }
      '
  )
}

add_result() {
  local group="$1"
  local service="$2"
  local ipv4="$3"
  local ipv6="$4"

  ipv4=${ipv4//$'\n'/}
  ipv4=${ipv4//$'\t'/ }
  ipv6=${ipv6//$'\n'/}
  ipv6=${ipv6//$'\t'/ }

  case "$group" in
    primary) ARR_PRIMARY+=("$service|||$ipv4|||$ipv6") ;;
    custom) ARR_CUSTOM+=("$service|||$ipv4|||$ipv6") ;;
    cdn) ARR_CDN+=("$service|||$ipv4|||$ipv6") ;;
  esac
}

print_table_group() {
    local group="$1"
    local group_title="$2"
    local na="N/A"
    local show_ipv4=0
    local show_ipv6=0
    local separator=$'\t'
    local col_width=32

    [[ "$IPV6_ONLY" != true && -n "$EXTERNAL_IPV4" ]] && show_ipv4=1
    [[ "$IPV4_ONLY" != true && -n "$EXTERNAL_IPV6" ]] && show_ipv6=1
	
	if [[ "$group_title" != "GeoIP services" ]]; then
		printf "%-${col_width}s" "$(color TABLE_HEADER 'Service')"
	fi

    if [[ "$group_title" != "GeoIP services" ]]; then
        [[ $show_ipv4 -eq 1 ]] && printf "%s%s" "$separator" "$(color TABLE_HEADER 'IPv4')"
        [[ $show_ipv6 -eq 1 ]] && printf "%s%s" "$separator" "$(color TABLE_HEADER 'IPv6')"
    fi
    printf "\n"

    jq -r --arg group "$group" '
        (.results // {}) as $r
        | ($r[$group] // [])
        | .[]
        | [ .service, (.ipv4 // "N/A"), (.ipv6 // "N/A") ]
        | @tsv
    ' <<<"$RESULT_JSON" | while IFS=$'\t' read -r s v4 v6; do

        printf "%-${col_width}s" "$(color SERVICE "$s")"

		if [[ $show_ipv4 -eq 1 ]]; then
			[[ "$v4" == "null" || -z "$v4" ]] && v4="$na"
			printf "%s%s" "$separator" "$(format_value "$v4" "$na")"
		fi

		if [[ $show_ipv6 -eq 1 ]]; then
			[[ "$v6" == "null" || -z "$v6" ]] && v6="$na"
			printf "%s%s" "$separator" "$(format_value "$v6" "$na")"
		fi

        printf "\n"
    done
}


print_header() {
  local ipv4 ipv6

  ipv4=$(process_json "$RESULT_JSON" ".ipv4")
  ipv6=$(process_json "$RESULT_JSON" ".ipv6")

  printf "%s\n%s\n\n" "$(color URL "Forked by Davoyan")" "$(color URL "$SCRIPT_URL")"

  if [[ -n "$EXTERNAL_IPV4" ]]; then
    printf "%s: %s\n" "$(color HEADER 'IPv4')" "$(bold "$(mask_ipv4 "$ipv4")")"
  fi

  if [[ -n "$EXTERNAL_IPV6" ]]; then
    printf "%s: %s\n" "$(color HEADER 'IPv6')" "$(bold "$(mask_ipv6 "$ipv6")")"
  fi

  printf "%s: %s\n\n" "$(color HEADER 'ASN')" "$(bold "AS$asn $asn_name")"
}

print_legend() {
  local separator="|||"
  echo
  printf "%s\n\n" "$(color HEADER 'Legend')"

  local stats
  stats=$(jq -r '
    def clean:
      tostring
      | gsub("\u001b\\[[0-9;]*m"; "")
      | select(test("^(No|Yes|N/A|null)$") | not);

    def counts(stream):
      [stream | select(. != null) | clean] as $arr
      | reduce ($arr[]) as $c ({}; .[$c] += 1)
      | {total: ($arr | length), counts: .};

    {
      ipv4: counts(
        (.results.primary[].ipv4?, .results.custom[].ipv4?)
      ),
      ipv6: counts(
        (.results.primary[].ipv6?, .results.custom[].ipv6?)
      )
    }
  ' <<<"$RESULT_JSON")

  local codes
  codes=$(jq -r '
    [
      (.ipv4.counts | keys[]?),
      (.ipv6.counts | keys[]?)
    ] | unique[]
  ' <<<"$stats")

  local show_ipv4=true show_ipv6=true
  if [[ "${IPV4_ONLY,,}" == "true" && "${IPV6_ONLY,,}" != "true" ]]; then
    show_ipv6=false
  fi
  if [[ "${IPV6_ONLY,,}" == "true" && "${IPV4_ONLY,,}" != "true" ]]; then
    show_ipv4=false
  fi
  
  if [[ -n "$EXTERNAL_IPV6" ]]; then
    show_ipv6=true
  else
    show_ipv6=false
  fi

  {
    local header_parts=()
    header_parts+=("$(color TABLE_HEADER 'Code')")
    header_parts+=("$(color TABLE_HEADER 'Country')")
    $show_ipv4 && header_parts+=("$(color TABLE_HEADER '% IPv4')")
    $show_ipv6 && header_parts+=("$(color TABLE_HEADER '% IPv6')")

    local header="${header_parts[0]}"
    for ((i=1; i<${#header_parts[@]}; i++)); do
      header+="$separator${header_parts[i]}"
    done
    echo "$header"

    while read -r code; do
      [[ -z "$code" ]] && continue
      local country ipv4_num ipv6_num ipv4_str ipv6_str
      country="${COUNTRY_NAMES[$code]:-Unknown}"

      ipv4_num=$(jq -r --arg c "$code" '
        if (.ipv4.total == 0) then 0
        else ((.ipv4.counts[$c] // 0) / .ipv4.total * 100 | round)
        end
      ' <<<"$stats")

      ipv6_num=$(jq -r --arg c "$code" '
        if (.ipv6.total == 0) then 0
        else ((.ipv6.counts[$c] // 0) / .ipv6.total * 100 | round)
        end
      ' <<<"$stats")

      ipv4_str=""
      ipv6_str=""
      [[ "$ipv4_num" -ne 0 ]] && ipv4_str="${ipv4_num}%"
      [[ "$ipv6_num" -ne 0 ]] && ipv6_str="${ipv6_num}%"

      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$ipv4_num" "$ipv6_num" "$(color SERVICE "$code")" "$(format_value "$country" "$country")" "$ipv4_str" "$ipv6_str"
    done <<< "$codes" \
      | sort -t$'\t' -k1,1nr -k2,2nr \
      | awk -F $'\t' -v OFS="$separator" \
        "$(
          if $show_ipv4 && $show_ipv6; then
            echo '{print $3,$4,$5,$6}'
          elif $show_ipv4; then
            echo '{print $3,$4,$5}'
          elif $show_ipv6; then
            echo '{print $3,$4,$6}'
          else
            echo '{print $3,$4,$5,$6}'
          fi
        )"

  } | column -t -s "$separator"
}

print_results() {
  finalize_json

  if [[ "$JSON_OUTPUT" == true ]]; then
    echo "$RESULT_JSON" | jq
    return
  fi

  print_header

  case "$GROUPS_TO_SHOW" in
    primary)
      print_table_group "primary" "GeoIP services"
      ;;
    custom)
      print_table_group "custom" "Popular services"
      ;;
    cdn)
      print_table_group "cdn" "CDN services"
      ;;
    *)
      print_table_group "custom" "Popular services"
      print_table_group "primary" "GeoIP services"
	  print_legend
      ;;
  esac
}

lookup_maxmind() {
  process_service "MAXMIND"
}

lookup_ripe() {
  process_service "RIPE"
}

lookup_ipinfo_io() {
  process_service "IPINFO_IO"
}

lookup_ipregistry() {
  process_service "IPREGISTRY"
}

lookup_ipapi_co() {
  process_service "IPAPI_CO"
}

lookup_cloudflare() {
  local ip_version="$1"
  local response

  response=$(make_request GET "https://www.cloudflare.com/cdn-cgi/trace" --ip-version "$ip_version")
  while IFS='=' read -r key value; do
    if [[ "$key" == "loc" ]]; then
      echo "$value"
      break
    fi
  done <<<"$response"
}

lookup_iplocation_com() {
  local ip_version="$1"
  local response ip

  if [[ -n "$EXTERNAL_IPV4" ]]; then
    ip="$EXTERNAL_IPV4"
  else
    ip="$EXTERNAL_IPV6"
  fi

  response=$(make_request POST "https://iplocation.com" --ip-version "$ip_version" --user-agent "$USER_AGENT" --data "ip=$ip")
  process_json "$response" ".country_code"
}

lookup_2ip() {
  local ip_version="$1"
  local response ip

  response=$(make_request GET "https://api.2ip.io" --ip-version "$ip_version" --data "ip=$ip")
  process_json "$response" ".code"
}

get_country_code() {
    local country="$1"
    local json

    json=$(curl $SELECTED_DOH_URL --max-time 5 -s "https://restcountries.com/v3.1/all?fields=name,cca2")
    if [[ -z "$json" ]] || ! grep -q '"name"' <<<"$json"; then
        echo ""
        return
    fi

    jq -r --arg COUNTRY "$country" '
        .[]
        | select(.name.common | ascii_downcase == ($COUNTRY | ascii_downcase))
        | .cca2
    ' <<<"$json"
}

lookup_google() {
  local ip_version="$1"
  local sed_filter='s/.*"[a-z]\{2\}_\([A-Z]\{2\}\)".*/\1/p'
  local sed_fallback_filter='s/.*"[a-z]\{2\}-\([A-Z]\{2\}\)".*/\1/p'
  local response result

  response=$(make_request GET "https://www.google.com" \
    --user-agent "$USER_AGENT" \
    --ip-version "$ip_version")

  result=$(sed -n "$sed_filter" <<<"$response")

  if [[ -z "$result" ]]; then
    result=$(sed -n "$sed_fallback_filter" <<<"$response" | tail -n 1)
  fi
  
  if [[ -z "$result" ]]; then
    local curl_ip_flag country
	if [[ "$ip_version" == "4" ]]; then
		curl_ip_flag="-4"
	elif [[ "$ip_version" == "6" ]]; then
		curl_ip_flag="-6"
	else
		curl_ip_flag="-4"
	fi
	
	curl_args=()
	
	if [[ -n "$PROXY_ADDR" ]]; then
	  curl_args+=(--proxy "socks5://$PROXY_ADDR")
	fi

	if [[ -n "$INTERFACE_NAME" ]]; then
	  curl_args+=(--interface "$INTERFACE_NAME")
	fi
	
    country=$(timeout "$CURL_TIMEOUT" curl $SELECTED_DOH_URL $curl_ip_flag -sL "${curl_args[@]}" 'https://play.google.com/'   -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7'   -H 'accept-language: en-US;q=0.9'   -H 'priority: u=0, i'   -H 'sec-ch-ua: "Chromium";v="131", "Not_A Brand";v="24", "Google Chrome";v="131"'   -H 'sec-ch-ua-mobile: ?0'   -H 'sec-ch-ua-platform: "Windows"'   -H 'sec-fetch-dest: document'   -H 'sec-fetch-mode: navigate'   -H 'sec-fetch-site: none'   -H 'sec-fetch-user: ?1'   -H 'upgrade-insecure-requests: 1' -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36' | grep -oP '<div class="yVZQTb">\K[^<(]+')

	country=$(echo "$country" | xargs)
	if [[ -n "$country" ]]; then
		result=$(get_country_code "$country")
	fi  
  fi

  echo "$result"
}

lookup_twitch() {
  local ip_version="$1"
  local response

  response=$(make_request POST "https://gql.twitch.tv/gql" \
    --header 'Client-Id: kimne78kx3ncx6brgo4mv6wki5h1ko' \
    --json '[{"operationName":"VerifyEmail_CurrentUser","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f9e7dcdf7e99c314c82d8f7f725fab5f99d1df3d7359b53c9ae122deec590198"}}}]' \
    --ip-version "$ip_version")
  process_json "$response" ".[0].data.requestInfo.countryCode"
}

lookup_chatgpt() {
  local ip_version="$1"
  local response

  response=$(make_request POST "https://ab.chatgpt.com/v1/initialize" --ip-version "$ip_version" \
    --header "Statsig-Api-Key: client-zUdXdSTygXJdzoE0sWTkP8GKTVsUMF2IRM7ShVO2JAG")
  process_json "$response" ".derived_fields.country"
}

lookup_netflix() {
  local ip_version="$1"
  local response

  response=$(make_request GET "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=1" --ip-version "$ip_version")

  if is_valid_json "$response"; then
    process_json "$response" ".client.location.country"
  else
    echo ""
  fi
}

lookup_spotify() {
  local ip_version="$1"
  local response

  response=$(make_request GET "https://accounts.spotify.com/status" --ip-version "$ip_version")

  sed -n 's/.*"geoLocationCountryCode":"\([^"]*\)".*/\1/p' <<<"$response"
}

lookup_deezer() {
  local ip_version="$1"
  local response

  response=$(make_request GET "https://www.deezer.com/en/offers" --ip-version "$ip_version")

  echo "$response" | sed -n "s/.*'country': '\(.*\)'.*/\1/p"
}


lookup_reddit() {
  local ip_version="$1"
  local basic_access_token="Basic b2hYcG9xclpZdWIxa2c6"
  local user_agent="Reddit/Version 2025.29.0/Build 2529021/Android 13"
  local response access_token

  response=$(make_request POST "https://www.reddit.com/auth/v2/oauth/access-token/loid" \
    --ip-version "$ip_version" \
    --user-agent "$user_agent" \
    --header "Authorization: $basic_access_token" \
    --json '{"scopes":["email"]}')

  access_token=$(process_json "$response" ".access_token")

  response=$(make_request POST "https://gql-fed.reddit.com" \
    --ip-version "$ip_version" \
    --user-agent "$user_agent" \
    --header "Authorization: Bearer $access_token" \
    --json '{"operationName":"UserLocation","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f07de258c54537e24d7856080f662c1b1268210251e5789c8c08f20d76cc8ab2"}}}')

  process_json "$response" ".data.userLocation.countryCode"
}

lookup_reddit_guest_access() {
  local ip_version="$1"
  local response is_available color_name

  response=$(make_request GET "https://www.reddit.com" --ip-version "$ip_version" --user-agent "$USER_AGENT")

  if [[ -n "$response" ]]; then
    is_available="Yes"
    color_name="SERVICE"
  else
    is_available="No"
    color_name="HEART"
  fi

  print_value_or_colored "$is_available" "$color_name"
}

lookup_youtube() {
    local ip_version="$1"
    local result curl_ip_flag service_name rest ipv4 ipv6

    if [[ "$ip_version" == "4" ]]; then
        curl_ip_flag="-4"
    elif [[ "$ip_version" == "6" ]]; then
        curl_ip_flag="-6"
    else
        curl_ip_flag="-4"
    fi
	
	result=$(make_request GET "https://www.youtube.com" --ip-version "$ip_version" --user-agent "$USER_AGENT" \
        | grep -oP '"countryCode":"\K\w+')
	
    if [[ -z "$result" || "$result" == "null" || "$result" == "n/a" || ${#result} -gt 7 ]]; then
        for entry in "${ARR_CUSTOM[@]}"; do
            service_name="${entry%%|||*}"
            if [[ "$service_name" == "Google" ]]; then
                rest="${entry#*|||}"
                ipv4="${rest%%|||*}"
                ipv6="${rest#*|||}"

                if [[ "$ip_version" == "4" ]]; then
                    result="$ipv4"
                else
                    result="$ipv6"
                fi

                break
            fi
        done
    fi

    echo "$result"
}


lookup_youtube_premium() {
  local ip_version="$1"
  local response is_available

  response=$(make_request GET "https://www.youtube.com/premium" \
    --ip-version "$ip_version" \
    --user-agent "$USER_AGENT" \
    --header "Cookie: SOCS=CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjUwNzMwLjA1X3AwGgJlbiACGgYIgPC_xAY" \
    --header "Accept-Language: en-US,en;q=0.9")

  if [[ -z "$response" ]]; then
    echo ""
    return
  fi

  is_available=$(grep -io "youtube premium is not available in your country" <<<"$response")

  if [[ -z "$is_available" ]]; then
    is_available="Yes"
    color_name="SERVICE"
  else
    is_available="No"
    color_name="HEART"
  fi

  print_value_or_colored "$is_available" "$color_name"
}

lookup_youtube_music() {
  local ip_version="$1"
  local response is_available

  response=$(make_request GET "https://music.youtube.com/" \
    --ip-version "$ip_version" \
    --user-agent "$USER_AGENT" \
    --header "Cookie: SOCS=CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjUwNzMwLjA1X3AwGgJlbiACGgYIgPC_xAY" \
    --header "Accept-Language: en-US,en;q=0.9")

  if [[ -z "$response" ]]; then
    echo ""
    return
  fi

  is_available=$(grep -io "YouTube Music is not available in your area" <<<"$response")

  if [[ -z "$is_available" ]]; then
    is_available="Yes"
    color_name="SERVICE"
  else
    is_available="No"
    color_name="HEART"
  fi

  print_value_or_colored "$is_available" "$color_name"
}

lookup_google_search_captcha() {
  local ip_version="$1"
  local response is_captcha color_name

  response=$(make_request GET "https://www.google.com/search?q=cats" --ip-version "$ip_version" \
    --user-agent "$USER_AGENT" \
    --header "Accept-Language: en-US,en;q=0.9")

  if [[ -z "$response" ]]; then
    echo ""
    return
  fi

  is_captcha=$(grep -iE "unusual traffic from|is blocked|unaddressed abuse" <<<"$response")

  if [[ -z "$is_captcha" ]]; then
    is_captcha="No"
    color_name="SERVICE"
  else
    is_captcha="Yes"
    color_name="HEART"
  fi

  print_value_or_colored "$is_captcha" "$color_name"
}

lookup_bing() {
  local ip_version="$1"
  local curl_ip_flag country
  if [[ "$ip_version" == "4" ]]; then
	  curl_ip_flag="-4"
  elif [[ "$ip_version" == "6" ]]; then
	  curl_ip_flag="-6"
  else
	  curl_ip_flag="-4"
  fi

  curl_args=()

  if [[ -n "$PROXY_ADDR" ]]; then
    curl_args+=(--proxy "socks5://$PROXY_ADDR")
  fi

  if [[ -n "$INTERFACE_NAME" ]]; then
    curl_args+=(--interface "$INTERFACE_NAME")
  fi
	  
  local tmpresult=$(timeout "$CURL_TIMEOUT" curl $SELECTED_DOH_URL -sL $curl_ip_flag "${curl_args[@]}" "https://www.bing.com/search?q=cats" --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36")
  
  local isCN=$(echo "$tmpresult" | grep 'cn.bing.com')
  local region=$(echo "$tmpresult" | grep -woP 'Region\s{0,}:\s{0,}"\K[^"]+')
  
  if [ -n "$isCN" ]; then
    region='CN'
  fi
  
  region="${region:0:2}"
  
  if [[ "$region" == "WW" ]]; then
	tmpresult=$(timeout "$CURL_TIMEOUT" curl $SELECTED_DOH_URL -s "https://login.live.com" $curl_ip_flag "${curl_args[@]}" --user-agent "$USER_AGENT")
	region=$(echo "$tmpresult" | grep -oP '"sRequestCountry":"\K[^"]*' | head -n1)
  fi

  echo "$region"
}

lookup_spotify_signup() {

  local ip_version="$1"
  local response status is_country_launched available color_name

  response=$(timeout "$CURL_TIMEOUT" curl $SELECTED_DOH_URL -s "https://spclient.wg.spotify.com/signup/public/v1/account/?validate=1&key=$SPOTIFY_API_KEY" $curl_ip_flag "${curl_args[@]}" \
    --header "X-Client-Id: $SPOTIFY_CLIENT_ID" \
	--user-agent "$USER_AGENT")

  status=$(process_json "$response" ".status")
  is_country_launched=$(process_json "$response" ".is_country_launched")

  if [[ "$status" == "120" || "$status" == "320" || "$is_country_launched" == "false" ]]; then
    available="No"
    color_name="HEART"
  else
    available="Yes"
    color_name="SERVICE"
  fi

  print_value_or_colored "$available" "$color_name"
}

lookup_amazon_prime() {
  local ip_version="$1"
  local curl_ip_flag
  if [[ "$ip_version" == "4" ]]; then
	  curl_ip_flag="-4"
  elif [[ "$ip_version" == "6" ]]; then
	  curl_ip_flag="-6"
  else
	  curl_ip_flag="-4"
  fi

  curl_args=()

  if [[ -n "$PROXY_ADDR" ]]; then
    curl_args+=(--proxy "socks5://$PROXY_ADDR")
  fi

  if [[ -n "$INTERFACE_NAME" ]]; then
    curl_args+=(--interface "$INTERFACE_NAME")
  fi
	  
  local tmpresult=$(timeout "$CURL_TIMEOUT" curl $SELECTED_DOH_URL -sL $curl_ip_flag "${curl_args[@]}" "https://www.primevideo.com" --user-agent "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36")
  
  local isBlocked=$(echo "$tmpresult" | grep -i 'isServiceRestricted')
  local region=$(echo "$tmpresult" | grep -woP '"currentTerritory":"\K[^"]+' | head -n 1)
  
  if [[ -z "$is_available" ]]; then
    region="${region:0:2}"
    echo "$region"
  else
    is_available="No"
    color_name="HEART"
	print_value_or_colored "$is_available" "$color_name"
  fi
}

lookup_apple() {
  local ip_version="$1"
  make_request GET "https://gspe1-ssl.ls.apple.com/pep/gcc" --ip-version "$ip_version"
}

lookup_steam() {
  local ip_version="$1"
  local curl_ip_flag
  if [[ "$ip_version" == "6" ]]; then
    curl_ip_flag="-6"
  else
    curl_ip_flag="-4"
  fi

  local curl_args=()
  [[ -n "$PROXY_ADDR" ]] && curl_args+=(--proxy "socks5://$PROXY_ADDR")
  [[ -n "$INTERFACE_NAME" ]] && curl_args+=(--interface "$INTERFACE_NAME")

  local tmpresult
  tmpresult=$(timeout "$CURL_TIMEOUT" curl $SELECTED_DOH_URL -sI "https://store.steampowered.com" $curl_ip_flag "${curl_args[@]}" \
    --user-agent "$USER_AGENT")

  echo "$tmpresult" | grep -oP 'steamCountry=\K[^%;]*'
}

lookup_tiktok() {
  local ip_version="$1"
  local response

  response=$(make_request GET "https://www.tiktok.com/api/v1/web-cookie-privacy/config?appId=1988" --ip-version "$ip_version")
  process_json "$response" ".body.appProps.region"
}

lookup_youtube_cdn() {
  local ip_version="$1"
  local response iata location

  response=$(make_request GET "https://redirector.googlevideo.com/report_mapping?di=no" --ip-version "$ip_version")
  iata=$(echo "$response" | awk '{print $3}' | cut -f2 -d'-' | cut -c1-3)
  iata=${iata^^}

  if [[ -z "$iata" ]]; then
    echo ""
    return
  fi

  location=$(get_iata_location "$iata")
  echo "$location"
}

lookup_netflix_cdn() {
  local ip_version="$1"
  local response

  response=$(make_request GET "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=1" --ip-version "$ip_version")

  if is_valid_json "$response"; then
    process_json "$response" ".targets[0].location.country"
  else
    echo ""
  fi
}

lookup_ookla_speedtest() {
  local ip_version="$1"
  local response

  response=$(make_request GET "https://www.speedtest.net/api/js/config-sdk" --ip-version "$ip_version")
  process_json "$response" ".location.countryCode"
}

lookup_jetbrains() {
  local ip_version="$1"
  local response

  response=$(make_request GET "https://data.services.jetbrains.com/geo" --ip-version "$ip_version")
  process_json "$response" ".code"
}

lookup_playstation() {
  local ip_version="$1"
  local curl_ip_flag
  if [[ "$ip_version" == "6" ]]; then
    curl_ip_flag="-6"
  else
    curl_ip_flag="-4"
  fi

  local curl_args=()
  [[ -n "$PROXY_ADDR" ]] && curl_args+=(--proxy "socks5://$PROXY_ADDR")
  [[ -n "$INTERFACE_NAME" ]] && curl_args+=(--interface "$INTERFACE_NAME")

  local tmpresult
  tmpresult=$(timeout "$CURL_TIMEOUT" curl $SELECTED_DOH_URL -sI "https://www.playstation.com" $curl_ip_flag "${curl_args[@]}" \
    --user-agent "$USER_AGENT")

  echo "$tmpresult" | grep -i 'Set-Cookie: country=' | head -n1 | sed 's/.*country=\([A-Z]*\).*/\1/'
}

check_doh() {
    local test_domain="${1:-www.google.com}"

    local resolvers=(
        "Cloudflare|https://1.1.1.1/dns-query|https://1.1.1.1/dns-query"
        "Quad9|https://9.9.9.9/dns-query|https://9.9.9.9/dns-query"
        "OpenDNS|https://208.67.222.222/dns-query|https://208.67.222.222/dns-query"
        "AdGuard|https://94.140.14.140/dns-query|https://94.140.14.140/dns-query"
    )

    local curl_opts=(-s --max-time 5 --connect-timeout 2 -o /dev/null)

    local entry name doh_url test_url

    for entry in "${resolvers[@]}"; do
        IFS="|" read -r name doh_url test_url <<<"$entry"

        if curl "${curl_opts[@]}" --doh-url "$doh_url" "https://$test_domain/" 2>/dev/null; then
            SELECTED_DOH_URL="--doh-url ${doh_url}"
            return 0
        fi
    done

    SELECTED_DOH_URL=""
    return 1
}

main() {
  parse_arguments "$@"

  install_dependencies
  check_doh
  
  check_ip_support 4
  IPV4_SUPPORTED=$?

  check_ip_support 6
  IPV6_SUPPORTED=$?

  get_external_ip
  get_asn

  if [[ "$JSON_OUTPUT" != true && "$VERBOSE" != true ]]; then
    trap 'spinner_stop; exit' INT TERM
    spinner_start
  fi

  case "$GROUPS_TO_SHOW" in
    custom) run_service_group "custom" ;;
    primary) run_service_group "primary" ;;
    cdn) run_service_group "cdn" ;;
    *)
      run_service_group "custom"
      run_service_group "primary"
      run_service_group "cdn"
      ;;
  esac

  if [[ "$JSON_OUTPUT" != true && "$VERBOSE" != true ]]; then
    spinner_stop
    trap - INT TERM
  fi

  print_results
}

main "$@"
EOF_IPREGION

    chmod +x /usr/local/bin/ipregion
    /usr/local/bin/ipregion
    echo
}

# ==========================================
# CENSORCHECK (ТСПУ)
# ==========================================
step_censorcheck() {
    draw_sub_header "CensorCheck (Блокировки ТСПУ / DPI)"
    
    _do_cc_deps() {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y curl dnsutils jq bsdmainutils util-linux >/dev/null 2>&1
    }
    run_task "Установка зависимостей (jq, dig, column)" "_do_cc_deps"

    read -p "  Введите домен для проверки (Enter - проверить весь список ТСПУ): " CC_DOMAIN

cat << 'EOF_CENSORCHECK' > /usr/local/bin/censorcheck
#!/usr/bin/env bash

readonly SCRIPT_NAME=$(basename "$0")
readonly COLOR_WHITE="\e[97m"
readonly COLOR_RED="\e[31m"
readonly COLOR_GREEN="\e[32m"
readonly COLOR_BLUE="\e[1;36m"
readonly COLOR_ORANGE="\e[33m"
readonly COLOR_RESET="\e[0m"
readonly CURL_SEPARATOR="--UNIQUE-SEPARATOR--"

readonly DNS_SERVERS=("1.1.1.1" "1.0.0.1" "8.8.8.8" "8.8.4.4" "9.9.9.9" "9.9.9.10" "77.88.8.8" "77.88.8.1")
readonly ENCRYPTED_DNS_SERVERS=(
  "Cloudflare|1.1.1.1"
  "Cloudflare|1.0.0.1"
  "Google|8.8.8.8"
  "Google|8.8.4.4"
  "Quad9|9.9.9.9"
  "Quad9|9.9.9.10"
  "Yandex|77.88.8.8"
  "Yandex|77.88.8.1"
)

AVAILABLE_DOH=()
AVAILABLE_DOT=()

TIMEOUT=5
RETRIES=2
MODE="both"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:129.0) Gecko/20100101 Firefox/129.0"
DOMAINS_FILE=""
IP_VERSION="4"
PROXY=""
SINGLE_DOMAIN=""
PROTOCOL="both"
JSON_OUTPUT=false

readonly DPI_BLOCKED_SITES=(
  "youtube.com"
  "discord.com"
  "instagram.com"
  "facebook.com"
  "x.com"
  "linkedin.com"
  "rutracker.org"
  "digitalocean.com"
  "amnezia.org"
  "getoutline.org"
  "mailfence.com"
  "flibusta.is"
  "rezka.ag"
  "api.telegram.org"
  "play.google.com"
)

readonly GEO_BLOCKED_SITES=(
  "spotify.com"
  "netflix.com"
  "patreon.com"
  "swagger.io"
  "snyk.io"
  "mongodb.com"
  "autodesk.com"
  "graylog.org"
  "redis.io"
  "copilot.microsoft.com"
)

readonly MSG_AVAILABLE="Available"
readonly MSG_BLOCKED="Blocked"
readonly MSG_BLOCKED_TEMPLATE="$MSG_BLOCKED or site didn't respond after %ss timeout"
readonly MSG_BLOCKED_BY_IP="$MSG_BLOCKED by IP"
readonly MSG_BLOCKED_BY_PORT="$MSG_BLOCKED by port"
readonly MSG_REDIRECT="Redirected"
readonly MSG_ACCESS_DENIED="Denied"
readonly MSG_OTHER="Responded with status code"

declare -a TEXT_RESULTS=()

error_exit() {
  local message="$1"
  local exit_code="${2:-1}"
  printf "[%b%s%b] %b%s%b\n" "$COLOR_RED" "ERROR" "$COLOR_RESET" "$COLOR_WHITE" "$message" "$COLOR_RESET" >&2
  exit "$exit_code"
}

show_progress() {
  local current=$1
  local total=$2
  local domain=$3
  if ! $JSON_OUTPUT; then
    printf "\r\033[K  %b[%d/%d] Проверка:%b %b%s%b" \
      "$COLOR_BLUE" "$current" "$total" "$COLOR_RESET" \
      "$COLOR_WHITE" "$domain" "$COLOR_RESET" >&2
  fi
}

clear_progress() {
  if ! $JSON_OUTPUT; then printf "\r%80s\r" " " >&2; fi
}

cleanup() { clear_progress; exit 130; }

check_ipv6_support() {
  if [[ -n $(ip -6 addr show scope global 2>/dev/null) ]]; then return 0; fi
  return 1
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -d | --domain) SINGLE_DOMAIN="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
}

print_header() {
  printf "\n  Таймаут: %b%ss%b\n" "$COLOR_WHITE" "$TIMEOUT" "$COLOR_RESET"
  if [[ -n "$SINGLE_DOMAIN" ]]; then
    printf "  Проверка домена: %b%s%b\n" "$COLOR_WHITE" "$SINGLE_DOMAIN" "$COLOR_RESET"
  else
    printf "  Проверка по: %bбазовому списку блокировок%b\n" "$COLOR_WHITE" "$COLOR_RESET"
  fi
  check_encrypted_dns_servers
  check_dns_hijacking
}

execute_curl() {
  local url=$1 protocol=$2 follow_redirects=$3 ip_version_to_use=${4:-$IP_VERSION}
  local curl_output
  local curl_opts=(
    -s --compressed -o /dev/null -w "%{http_code}${CURL_SEPARATOR}%{redirect_url}"
    --retry-connrefused --retry-all-errors --retry "$RETRIES"
    --connect-timeout "$TIMEOUT" --max-time "$((TIMEOUT * (RETRIES + 1)))"
    -"$ip_version_to_use" -A "$USER_AGENT"
    -H "Sec-Fetch-Site: none" -H "Accept-Language: en-US,en;q=0.5"
  )
  if [ "$follow_redirects" = true ]; then curl_opts+=(-L); fi
  if curl_output=$(curl "${curl_opts[@]}" "${protocol}://${url}"); then
    echo "$curl_output"
  else
    echo "000${CURL_SEPARATOR}"
  fi
}

get_domains_to_check() {
  if [[ -n "$SINGLE_DOMAIN" ]]; then echo "$SINGLE_DOMAIN"; else echo "${DPI_BLOCKED_SITES[@]}" "${GEO_BLOCKED_SITES[@]}"; fi
}

get_single_check_result() {
  local domain=$1 protocol=$2 follow_redirects=$3 ip_version=$4
  local response status_code redirect_url
  local port
  [[ "${protocol,,}" == "https" ]] && port=443 || port=80

  if [[ -z "$PROXY" ]]; then
    local ip
    ip=$(get_domain_ip "$domain" "$ip_version")
    if [[ -n "$ip" ]] && ! is_port_open "$ip" "$port"; then
      jq -n '{"status": -1, "redirect_url": null}'
      return
    fi
  fi
  response=$(execute_curl "$domain" "$protocol" "$follow_redirects" "$ip_version")
  status_code="${response%%$CURL_SEPARATOR*}"
  redirect_url="${response#*$CURL_SEPARATOR}"
  jq -n --argjson status "${status_code:-0}" --arg redirect_url "${redirect_url:-}" '
    { "status": ($status|tonumber), "redirect_url": (if $redirect_url == "" then null else $redirect_url end) }'
}

gather_single_domain_result() {
  local domain=$1
  local ipv6_supported
  local http_ipv4=null http_ipv6=null https_ipv4=null https_ipv6=null
  check_ipv6_support && ipv6_supported=true || ipv6_supported=false
  http_ipv4=$(get_single_check_result "$domain" "HTTP" false 4)
  https_ipv4=$(get_single_check_result "$domain" "HTTPS" true 4)
  jq -n --arg service "$domain" --argjson http_ipv4 "$http_ipv4" --argjson https_ipv4 "$https_ipv4" '
    { "service": $service, "http": { "ipv4": $http_ipv4 }, "https": { "ipv4": $https_ipv4 } }'
}

get_record_type() { local ip_version=${1:-$IP_VERSION}; [[ "$ip_version" == "6" ]] && echo "AAAA" || echo "A"; }

get_domain_ip() {
  local domain=$1 ip_version=${2:-$IP_VERSION}
  dig +short "$domain" "$(get_record_type "$ip_version")" 2>/dev/null | awk '/^[0-9a-fA-F.:]+$/ {print; exit}' || true
}

domain_exists() {
  local domain=$1 rcode
  rcode=$(dig +noall +comments "$domain" A 2>/dev/null | awk -F'status: ' '/status:/ {split($2, parts, ","); print parts[1]; exit}')
  [[ "$rcode" != "NXDOMAIN" ]]
}

get_domain_ips_via_dns() {
  local domain=$1 server=$2
  dig +short @"$server" "$domain" "$(get_record_type)" +timeout="$TIMEOUT" +tries=1 2>/dev/null | awk '/^[0-9a-fA-F.:]+$/' || true
}

resolve_via_dig() {
  local domain=$1 server_ip=$2 transport=$3
  dig +short +"$transport" @"$server_ip" "$domain" "$(get_record_type)" +timeout="$TIMEOUT" +tries=1 2>/dev/null | awk '/^[0-9a-fA-F.:]+$/'
}

have_ip_intersection() {
  local -n first_ips=$1 second_ips=$2
  declare -A ip_set=()
  local ip
  for ip in "${first_ips[@]}"; do ip_set["$ip"]=1; done
  for ip in "${second_ips[@]}"; do [[ -n ${ip_set["$ip"]+1} ]] && return 0; done
  return 1
}

probe_resolver_transport() {
  if [[ -n "$(resolve_via_dig "$1" "$2" "$3")" ]]; then echo "available"; else echo "blocked"; fi
}

check_encrypted_dns_servers() {
  local test_domain="rutracker.org" entry name ip doh_status dot_status
  local table_rows=() i tmp_dir
  AVAILABLE_DOH=()
  AVAILABLE_DOT=()
  tmp_dir=$(mktemp -d)

  for i in "${!ENCRYPTED_DNS_SERVERS[@]}"; do
    ip="${ENCRYPTED_DNS_SERVERS[$i]##*|}"
    probe_resolver_transport "$test_domain" "$ip" "https" >"$tmp_dir/${i}_https" &
    probe_resolver_transport "$test_domain" "$ip" "tls" >"$tmp_dir/${i}_tls" &
  done
  wait

  for i in "${!ENCRYPTED_DNS_SERVERS[@]}"; do
    entry="${ENCRYPTED_DNS_SERVERS[$i]}"
    name="${entry%%|*}"
    ip="${entry##*|}"

    if [[ "$(<"$tmp_dir/${i}_https")" == "available" ]]; then
      AVAILABLE_DOH+=("$entry")
      doh_status="$MSG_AVAILABLE"
    else
      doh_status="$MSG_BLOCKED"
    fi

    if [[ "$(<"$tmp_dir/${i}_tls")" == "available" ]]; then
      AVAILABLE_DOT+=("$entry")
      dot_status="$MSG_AVAILABLE"
    else
      dot_status="$MSG_BLOCKED"
    fi

    table_rows+=("  $(printf "%s%b\t%s\t%s\t%s" "$name" "$COLOR_RESET" "$ip" "$(colorize_summary "$doh_status")" "$(colorize_summary "$dot_status")")")
  done
  rm -rf "$tmp_dir"

  printf "\n  %bДоступность Encrypted DNS (DoH/DoT):%b\n\n" "$COLOR_WHITE" "$COLOR_RESET"
  {
    printf "  \033[1m%b%s\t%s\t%s\t%s%b\033[0m\n" "$COLOR_WHITE" "Resolver" "IP" "DoH" "DoT" "$COLOR_RESET"
    printf "%s\n" "${table_rows[@]}"
  } | column -t -s $'\t'
}

get_reference_resolver() {
  if [[ ${#AVAILABLE_DOH[@]} -gt 0 ]]; then
    printf "%s\thttps" "${AVAILABLE_DOH[0]}"
  elif [[ ${#AVAILABLE_DOT[@]} -gt 0 ]]; then
    printf "%s\ttls" "${AVAILABLE_DOT[0]}"
  fi
}

check_dns_hijacking() {
  local test_domains=("rutracker.org" "linkedin.com" "flibusta.is")
  local regular_dns_ips=() encrypted_ips=() hijacked_domain="" hijacked_ip=""
  local reference reference_entry reference_transport reference_name reference_ip
  reference=$(get_reference_resolver)

  if [[ -z "$reference" ]]; then
    printf "\n  %b%s%b\n" "$COLOR_ORANGE" "Нет доступных серверов DoH/DoT, пропускаем проверку DNS подмены" "$COLOR_RESET"
    return 0
  fi

  reference_entry="${reference%%$'\t'*}"
  reference_transport="${reference##*$'\t'}"
  reference_name="${reference_entry%%|*}"
  reference_ip="${reference_entry##*|}"

  for test_domain in "${test_domains[@]}"; do
    regular_dns_ips=()
    encrypted_ips=()
    for dns_server in "${DNS_SERVERS[@]}"; do
      mapfile -t regular_dns_ips < <(get_domain_ips_via_dns "$test_domain" "$dns_server")
      [[ ${#regular_dns_ips[@]} -gt 0 ]] && break
    done
    mapfile -t encrypted_ips < <(resolve_via_dig "$test_domain" "$reference_ip" "$reference_transport")
    [[ ${#regular_dns_ips[@]} -eq 0 ]] || [[ ${#encrypted_ips[@]} -eq 0 ]] && continue

    if ! have_ip_intersection regular_dns_ips encrypted_ips; then
      hijacked_domain="$test_domain"
      hijacked_ip="${regular_dns_ips[0]}"
      break
    fi
  done

  if [[ -n "$hijacked_domain" ]]; then
    printf "\n  %b%s%b %s %b%s%b %s %b%s%b\n" "$COLOR_RED" "Обнаружен перехват DNS!" "$COLOR_RESET" "Провайдер подменяет" "$COLOR_WHITE" "$hijacked_domain" "$COLOR_RESET" "на" "$COLOR_RED" "$hijacked_ip" "$COLOR_RESET"
    printf "  %bReference resolver: %s (%s) over %s%b\n\n" "$COLOR_WHITE" "$reference_name" "$reference_ip" "${reference_transport^^}" "$COLOR_RESET"
  else
    printf "\n  %b%s%b %b(Провайдер не подменяет DNS)%b\n" "$COLOR_GREEN" "Хорошие новости, перехвата DNS не обнаружено!" "$COLOR_RESET" "$COLOR_WHITE" "$COLOR_RESET"
  fi
}

is_port_open() {
  local ip="$1" port="$2"
  timeout "$TIMEOUT" bash -c "(echo >/dev/tcp/$ip/$port)" 2>/dev/null
}

is_ip_reachable() {
  local ip="$1"
  is_port_open "$ip" 80 || is_port_open "$ip" 443
}

summarize_status_description() {
  local status_code=$1 redirect_url=$2 msg
  if [[ "$status_code" -eq -1 ]]; then msg="$MSG_BLOCKED_BY_PORT"
  elif [[ -z "$status_code" || "$status_code" = "000" || "$status_code" -eq 0 ]]; then msg=$(printf "$MSG_BLOCKED_TEMPLATE" "$TIMEOUT")
  elif [[ "$status_code" -ge 300 && "$status_code" -lt 400 ]]; then
    [[ -z "$redirect_url" ]] && redirect_url="<empty>"
    msg=$(printf "%s (%s) -> %s" "$MSG_REDIRECT" "$status_code" "$redirect_url")
  elif [[ "$status_code" -eq 200 ]]; then msg="$MSG_AVAILABLE ($status_code)"
  elif [[ "$status_code" -eq 403 ]]; then msg="$MSG_ACCESS_DENIED ($status_code)"
  else msg="$MSG_OTHER $status_code"
  fi
  echo "$msg"
}

colorize_summary() {
  local message="$1" first_word rest first_word_color
  first_word="${message%% *}"
  if [[ "$first_word" == "$message" ]]; then rest=""; else rest="${message#* }"; fi
  case "$first_word" in
    Blocked | Denied) first_word_color=$COLOR_RED ;;
    Available) first_word_color=$COLOR_GREEN ;;
    Redirected) first_word_color=$COLOR_BLUE ;;
    *) first_word_color=$COLOR_ORANGE ;;
  esac
  if [[ -z "$rest" ]]; then printf "%b%s%b" "$first_word_color" "$first_word" "$COLOR_RESET"
  else printf "%b%s%b %s" "$first_word_color" "$first_word" "$COLOR_RESET" "$rest"
  fi
}

summarize_protocol_result() {
  local result_json=$1 protocol=$2 data
  data=$(jq -c --arg protocol "$protocol" '.[$protocol].ipv4' <<<"$result_json")
  if [[ "$data" == "null" || -z "$data" ]]; then echo "N/A"; return; fi
  local status redirect
  status=$(jq -r '.status' <<<"$data")
  redirect=$(jq -r '.redirect_url // ""' <<<"$data")
  summarize_status_description "$status" "$redirect"
}

add_text_result_row() {
  local service=$1 ip=$2 http_cell=$3 https_cell=$4
  TEXT_RESULTS+=("$(jq -n --arg service "$service" --arg ip "$ip" --arg http "$http_cell" --arg https "$https_cell" '{service: $service, ip: $ip, http: $http, https: $https}')")
}

add_text_result_from_json() {
  local result_json=$1 ip=$2 service http_cell https_cell
  service=$(echo "$result_json" | jq -r '.service')
  http_cell=$(summarize_protocol_result "$result_json" "http")
  https_cell=$(summarize_protocol_result "$result_json" "https")
  add_text_result_row "$service" "$ip" "$http_cell" "$https_cell"
}

print_table_results() {
  printf "\n"
  {
    printf "  \033[1m%b%s\t%s\t%s\t%s%b\033[0m\n" "$COLOR_WHITE" "Service" "IP" "HTTP" "HTTPS" "$COLOR_RESET"
    for row_json in "${TEXT_RESULTS[@]}"; do
      local service http https
      service=$(jq -r '.service' <<<"$row_json")
      ip=$(jq -r '.ip' <<<"$row_json")
      http=$(jq -r '.http' <<<"$row_json")
      https=$(jq -r '.https' <<<"$row_json")
      printf "  %s%b\t%s\t%s\t%s\n" "$service" "$COLOR_RESET" "$ip" "$(colorize_summary "$http")" "$(colorize_summary "$https")"
    done
  } | column -t -s $'\t'
}

run_checks_and_print() {
  local domains all_results_json="[]"
  read -r -a domains <<<"$(get_domains_to_check)"
  local total_domains=${#domains[@]} current_index=0
  TEXT_RESULTS=()

  print_header
  printf "\n"

  for domain in "${domains[@]}"; do
    ((++current_index))
    show_progress "$current_index" "$total_domains" "$domain"
    local ip_address
    ip_address=$(get_domain_ip "$domain")

    if [[ -z "$ip_address" ]]; then
      local error_code error_message
      if domain_exists "$domain"; then error_code="no_dns_record"; error_message="No $(get_record_type) record"
      else error_code="nxdomain"; error_message="Domain does not exist"; fi
      add_text_result_row "$domain" "N/A" "$error_message" "$error_message"
      continue
    fi

    if [[ -z "$PROXY" ]] && ! is_ip_reachable "$ip_address"; then
      add_text_result_row "$domain" "$ip_address" "$MSG_BLOCKED_BY_IP" "$MSG_BLOCKED_BY_IP"
      continue
    fi

    local domain_result_json
    domain_result_json=$(gather_single_domain_result "$domain")
    add_text_result_from_json "$domain_result_json" "$ip_address"
  done
  clear_progress
  print_table_results
}

main() {
  set -euo pipefail
  trap cleanup INT TERM
  parse_arguments "$@"
  run_checks_and_print
  trap - INT TERM
}

main "$@"
EOF_CENSORCHECK

    chmod +x /usr/local/bin/censorcheck
    echo -e "\n  ${C_DIM}Инициализация проверок (может занять некоторое время)...${C_BASE}"
    
    if [[ -n "$CC_DOMAIN" ]]; then
        /usr/local/bin/censorcheck -d "$CC_DOMAIN"
    else
        /usr/local/bin/censorcheck
    fi
    echo
}

# ==========================================
# IP QUALITY CHECK (Репутация IP)
# ==========================================
step_ipquality() {
    draw_sub_header "IP Репутация"
    
    _do_ipq_deps() {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y >/dev/null 2>&1
        apt-get install -y jq curl bc netcat-openbsd dnsutils iproute2 >/dev/null 2>&1
    }
    run_task "Установка зависимостей (jq, bc, nc)" "_do_ipq_deps"

cat << 'EOF_IPQUALITY' > /usr/local/bin/ipquality
#!/bin/bash
script_version="v2026-03-29"

Font_B="\033[1m"
Font_D="\033[2m"
Font_I="\033[3m"
Font_U="\033[4m"
Font_Black="\033[30m"
Font_Red="\033[31m"
Font_Green="\033[32m"
Font_Yellow="\033[33m"
Font_Blue="\033[34m"
Font_Purple="\033[35m"
Font_Cyan="\033[1;36m"
Font_White="\033[97m"
Back_Black="\033[40m"
Back_Red="\033[41m"
Back_Green="\033[42m"
Back_Yellow="\033[43m"
Back_Blue="\033[44m"
Back_Purple="\033[45m"
Back_Cyan="\033[46m"
Back_White="\033[47m"
Font_Suffix="\033[0m"
Font_LineClear="\033[2K"
Font_LineUp="\033[1A"

declare ADLines=0
declare -A aad
declare IP=""
declare IPhide
declare fullIP=0
declare YY="en"
declare -A maxmind ipinfo scamalytics ipregistry ipapi abuseipdb ip2location dbip ipdata ipqs tiktok disney netflix youtube amazon reddit chatgpt
declare IPV4 IPV6
declare IPV4check=1 IPV6check=1 IPV4work=0 IPV6work=0 ERRORcode=0
declare shelp
declare -A swarn sinfo shead sbasic stype sscore sfactor smedia smail smailstatus stail
declare mode_no=0 mode_yes=0 mode_lite=0 mode_json=0 mode_menu=0 mode_output=0 mode_privacy=0
declare ipjson ibar=0 bar_pid ibar_step=0 main_pid=$$ PADDING="" useNIC="" usePROXY="" CurlARG="" UA_Browser rawgithub Media_Cookie IATA_Database

set_language(){
swarn[1]="ERROR: Unsupported parameters!"
swarn[2]="ERROR: IP address format error!"
swarn[3]="ERROR: Dependent programs are missing."
swarn[4]="ERROR: Parameter -4 conflicts with -i or -6!"
swarn[6]="ERROR: Parameter -6 conflicts with -i or -4!"
swarn[7]="ERROR: Network interface invalid!"
swarn[8]="ERROR: Proxy parameter invalid!"
swarn[10]="ERROR: Output file already exist!"
swarn[11]="ERROR: Output file is not writable!"
swarn[40]="ERROR: IPv4 is not available!"
swarn[60]="ERROR: IPv6 is not available!"
sinfo[database]="Checking IP database "
sinfo[media]="Checking stream media "
sinfo[ai]="Checking AI provider "
sinfo[mail]="Connecting Email server "
sinfo[dnsbl]="Checking Blacklist database "
sinfo[ldatabase]=21
sinfo[lmedia]=22
sinfo[lai]=21
sinfo[lmail]=24
sinfo[ldnsbl]=28
shead[title]="IP QUALITY CHECK REPORT: "
shead[title_lite]="IP QUALITY CHECK REPORT(LITE): "
shead[ver]="Version: $script_version"
shead[bash]="bash <(curl -sL https://Check.Place) -EI"
shead[git]="https://github.com/xykt/IPQuality"
shead[time_raw]=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
shead[time]="Report Time: ${shead[time_raw]}"
shead[ltitle]=25
shead[ltitle_lite]=31
shead[ptime]=$(printf '%7s' '')
sbasic[title]="  1. Basic Information (${Font_I}Maxmind Database$Font_Suffix)"
sbasic[title_lite]="  1. Basic Information (${Font_I}IPinfo Database$Font_Suffix)"
sbasic[asn]="  ASN:                    "
sbasic[noasn]="Not Assigned"
sbasic[org]="  Organization:           "
sbasic[location]="  Location:               "
sbasic[map]="  Map:                    "
sbasic[city]="  City:                   "
sbasic[country]="  Actual Region:          "
sbasic[regcountry]="  Registered Region:      "
sbasic[continent]="  Continent:              "
sbasic[timezone]="  Time Zone:              "
sbasic[type]="  IP Type:                "
sbasic[type0]=" Geo-consistent "
sbasic[type1]=" Geo-discrepant "
stype[business]=" $Back_Yellow$Font_White$Font_B Business $Font_Suffix "
stype[isp]="   $Back_Green$Font_White$Font_B ISP $Font_Suffix    "
stype[hosting]=" $Back_Red$Font_White$Font_B Hosting $Font_Suffix  "
stype[education]="$Back_Yellow$Font_White$Font_B Education $Font_Suffix "
stype[government]="$Back_Yellow$Font_White$Font_B Government $Font_Suffix"
stype[banking]=" $Back_Yellow$Font_White$Font_B Banking $Font_Suffix  "
stype[organization]="$Back_Yellow$Font_White${Font_B}Organization$Font_Suffix"
stype[military]=" $Back_Yellow$Font_White$Font_B Military $Font_Suffix "
stype[library]=" $Back_Yellow$Font_White$Font_B Library $Font_Suffix  "
stype[cdn]="   $Back_Red$Font_White$Font_B CDN $Font_Suffix    "
stype[lineisp]=" $Back_Green$Font_White$Font_B Line ISP $Font_Suffix "
stype[mobile]="$Back_Green$Font_White$Font_B Mobile ISP $Font_Suffix"
stype[spider]="$Back_Red$Font_White$Font_B Web Spider $Font_Suffix"
stype[reserved]=" $Back_Yellow$Font_White$Font_B Reserved $Font_Suffix "
stype[other]="  $Back_Yellow$Font_White$Font_B Other $Font_Suffix   "
stype[title]="  2. IP Type"
stype[db]="  Database:  "
stype[usetype]="  Usage:     "
stype[comtype]="  Company:   "
sscore[verylow]="$Font_Green${Font_B}VeryLow$Font_Suffix"
sscore[low]="$Font_Green${Font_B}Low$Font_Suffix"
sscore[medium]="$Font_Yellow${Font_B}Medium$Font_Suffix"
sscore[high]="$Font_Red${Font_B}High$Font_Suffix"
sscore[veryhigh]="$Font_Red${Font_B}VeryHigh$Font_Suffix"
sscore[elevated]="$Font_Yellow${Font_B}Elevated$Font_Suffix"
sscore[suspicious]="$Font_Yellow${Font_B}Suspicious$Font_Suffix"
sscore[risky]="$Font_Red${Font_B}Risky$Font_Suffix"
sscore[highrisk]="$Font_Red${Font_B}HighRisk$Font_Suffix"
sscore[dos]="$Font_Red${Font_B}DoS$Font_Suffix"
sscore[colon]=": "
sscore[title]="  3. Risk Score"
sscore[range]="  ${Font_Cyan}Levels:         $Font_I$Font_White${Back_Green}VeryLow     Low $Back_Yellow     Medium     $Back_Red High   VeryHigh$Font_Suffix"
sfactor[title]="  4. Risk Factors"
sfactor[factor]="  DB:  "
sfactor[countrycode]="  Region: "
sfactor[proxy]="  Proxy:  "
sfactor[tor]="  Tor:    "
sfactor[vpn]="  VPN:    "
sfactor[server]="  Server: "
sfactor[abuser]="  Abuser: "
sfactor[robot]="  Robot:  "
sfactor[yes]="$Font_Red$Font_B Yes$Font_Suffix"
sfactor[no]="$Font_Green$Font_B No $Font_Suffix"
sfactor[na]="$Font_Green$Font_B N/A$Font_Suffix"
smedia[yes]="  $Back_Green$Font_White Yes $Font_Suffix  "
smedia[no]=" $Back_Red$Font_White Block $Font_Suffix "
smedia[bad]="$Back_Red$Font_White Failed $Font_Suffix "
smedia[pending]="$Back_Yellow$Font_White Pending $Font_Suffix"
smedia[cn]=" $Back_Red$Font_White China $Font_Suffix "
smedia[noprem]="$Back_Red$Font_White NoPrem. $Font_Suffix"
smedia[org]="$Back_Yellow$Font_White NF.Only $Font_Suffix"
smedia[web]="$Back_Yellow$Font_White WebOnly $Font_Suffix"
smedia[app]="$Back_Yellow$Font_White APPOnly $Font_Suffix"
smedia[idc]="  $Back_Yellow$Font_White IDC $Font_Suffix  "
smedia[native]="$Back_Green$Font_White Native $Font_Suffix "
smedia[dns]="$Back_Yellow$Font_White ViaDNS $Font_Suffix "
smedia[nodata]="         "
smedia[title]="  5. Accessibility check for media and AI services"
smedia[meida]="  Service: "
smedia[status]="  Status:  "
smedia[region]="  Region:  "
smedia[type]="  Type:    "
smail[title]="  6. Email service availability and blacklist detection"
smail[port]="  Local Port 25 Outbound: "
smail[yes]="${Font_Green}Available$Font_Suffix"
smail[no]="${Font_Red}Blocked$Font_Suffix"
smail[occupied]="${Font_Yellow}Occupied$Font_Suffix"
smail[blocked]="${Font_Red}Remote Port 25 unreachable​$Font_Suffix"
smail[provider]="  Conn: "
smail[dnsbl]="  DNSBL database: "
smail[available]="$Font_Suffix${Font_Cyan}Active $Font_B"
smail[clean]="$Font_Suffix${Font_Green}Clean $Font_B"
smail[marked]="$Font_Suffix${Font_Yellow}Marked $Font_B"
smail[blacklisted]="$Font_Suffix${Font_Red}Blacklisted $Font_B"
stail[stoday]="IP Checks Today: "
stail[stotal]="; Total: "
stail[thanks]=". Thanks for running xy scripts!"
stail[link]="  ${Font_I}Report Link: $Font_U"
}

show_progress_bar(){
  show_progress_bar_ "$@" 1>&2
}
show_progress_bar_(){
  local bar="\u280B\u2819\u2839\u2838\u283C\u2834\u2826\u2827\u2807\u280F"
  local n=${#bar}
  while sleep 0.1;do
    if ! kill -0 $main_pid 2>/dev/null;then exit; fi
    echo -ne "\r  $Font_Cyan$Font_B[$IP]# $1$Font_Cyan$Font_B$(printf '%*s' "$2" ''|tr ' ' '.') ${bar:ibar++*6%n:6} $(printf '%02d%%' $ibar_step) $Font_Suffix"
  done
}
kill_progress_bar(){
  kill "$bar_pid" 2>/dev/null&&echo -ne "\r  \033[K"
}

declare -A browsers=(
[Chrome]="145.0.0.0 144.0.0.0 143.0.0.0 142.0.0.0 141.0.0.0 140.0.0.0"
[Firefox]="147.0 146.0 145.0 144.0 143.0 142.0 141.0 140.0")

generate_random_user_agent(){
  local browsers_keys=(${!browsers[@]})
  local random_browser_index=$((RANDOM%${#browsers_keys[@]}))
  local browser=${browsers_keys[random_browser_index]}
  case $browser in
    Chrome)local versions=(${browsers[Chrome]}); local version=${versions[RANDOM%${#versions[@]}]}; UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/$version Safari/537.36" ;;
    Firefox)local versions=(${browsers[Firefox]}); local version=${versions[RANDOM%${#versions[@]}]}; UA_Browser="Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:$version) Gecko/20100101 Firefox/$version" ;;
  esac
}

adapt_locale(){ export LC_CTYPE=en_US.UTF-8 2>/dev/null; }

is_valid_ipv4(){
  local ip=$1
  if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]];then
    IFS='.' read -r -a octets <<<"$ip"
    for octet in "${octets[@]}";do
      if ((octet<0||octet>255));then IPV4work=0; return 1; fi
    done
    IPV4work=1; return 0
  else
    IPV4work=0; return 1
  fi
}

get_ipv4(){
  local response
  IPV4=""
  local API_NET=("ipinfo.io/ip" "myip.check.place" "ip.sb" "ping0.cc" "icanhazip.com" "api64.ipify.org" "ifconfig.co" "ident.me")
  for p in "${API_NET[@]}";do
    response=$(curl $CurlARG -s4 --max-time 2 "$p")
    if [[ $? -eq 0 && $response =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]];then
      IPV4="$response"; break
    fi
  done
}

hide_ipv4(){
  if [[ -n $1 ]];then
    IFS='.' read -r -a ip_parts <<<"$1"
    IPhide="${ip_parts[0]}.${ip_parts[1]}.*.*"
  else
    IPhide=""
  fi
}

is_valid_ipv6(){
  local ip=$1
  if [[ $ip =~ ^([0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}$ || $ip =~ ^([0-9a-fA-F]{1,4}:){1,7}:$ || $ip =~ ^:([0-9a-fA-F]{1,4}:){1,7}$ || $ip =~ ^([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}$ || $ip =~ ^([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}$ || $ip =~ ^([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}$ || $ip =~ ^([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}$ || $ip =~ ^([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}$ || $ip =~ ^[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})$ || $ip =~ ^:((:[0-9a-fA-F]{1,4}){1,7}|:)$ || $ip =~ ^fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}$ || $ip =~ ^::(ffff(:0{1,4}){0,1}:){0,1}(([0-9]{1,3}\.){3}[0-9]{1,3})$ || $ip =~ ^([0-9a-fA-F]{1,4}:){1,4}:(([0-9]{1,3}\.){3}[0-9]{1,3})$ ]];then
    IPV6work=1; return 0
  else
    IPV6work=0; return 1
  fi
}

get_ipv6(){
  local response
  IPV6=""
  local API_NET=("myip.check.place" "ip.sb" "ping0.cc" "icanhazip.com" "api64.ipify.org" "ifconfig.co" "ident.me")
  for p in "${API_NET[@]}";do
    response=$(curl $CurlARG -s6k --max-time 2 "$p")
    response="${response%$'\n'}"
    if [[ $? -eq 0 && $response =~ ^[0-9a-fA-F:]+$ && $response == *:* ]];then
      IPV6="$response"; break
    fi
  done
}

hide_ipv6(){
  if [[ -n $1 ]];then
    local expanded_ip=$(echo "$1"|sed 's/::/:0000:0000:0000:0000:0000:0000:0000:0000:/g'|cut -d ':' -f1-8)
    IFS=':' read -r -a ip_parts <<<"$expanded_ip"
    while [ ${#ip_parts[@]} -lt 8 ];do ip_parts+=(0000); done
    IPhide="${ip_parts[0]:-0}:${ip_parts[1]:-0}:${ip_parts[2]:-0}:*:*:*:*:*"
    IPhide=$(echo "$IPhide"|sed 's/:0\{1,\}/:/g'|sed 's/::\+/:/g')
  else
    IPhide=""
  fi
}

calculate_display_width(){
  local string="$1"
  local length=0
  local char
  for ((i=0; i<${#string}; i++));do
    char=$(echo "$string"|od -An -N1 -tx1 -j $((i))|tr -d ' ')
    if [ "$(printf '%d\n' 0x$char)" -gt 127 ];then length=$((length+2)); i=$((i+1))
    else length=$((length+1)); fi
  done
  echo "$length"
}

calc_padding(){
  local input_text="$1"
  local total_width=$2
  local title_length=$(calculate_display_width "$input_text")
  local left_padding=$(((total_width-title_length)/2))
  if [[ $left_padding -gt 0 ]];then PADDING=$(printf '%*s' $left_padding)
  else PADDING=""; fi
}

generate_dms(){
  local lat=$1 lon=$2
  if [[ -z $lat || $lat == "null" || -z $lon || $lon == "null" ]];then echo ""; return; fi
  convert_single(){
    local coord=$1 direction=$2
    local fixed_coord=$(echo "$coord"|sed 's/\.$/.0/')
    local degrees=$(echo "$fixed_coord"|cut -d'.' -f1)
    local fractional="0.$(echo "$fixed_coord"|cut -d'.' -f2)"
    local minutes=$(echo "$fractional * 60"|bc -l|cut -d'.' -f1)
    local seconds_fractional="0.$(echo "$fractional * 60"|bc -l|cut -d'.' -f2)"
    local seconds=$(echo "$seconds_fractional * 60"|bc -l|awk '{printf "%.0f", $1}')
    echo "$degrees°$minutes′$seconds″$direction"
  }
  local lat_dir='N'
  if [[ $(echo "$lat < 0"|bc -l) -eq 1 ]];then lat_dir='S'; lat=$(echo "$lat * -1"|bc -l); fi
  local lon_dir='E'
  if [[ $(echo "$lon < 0"|bc -l) -eq 1 ]];then lon_dir='W'; lon=$(echo "$lon * -1"|bc -l); fi
  local lat_dms=$(convert_single $lat $lat_dir)
  local lon_dms=$(convert_single $lon $lon_dir)
  echo "$lon_dms, $lat_dms"
}

generate_googlemap_url(){
  local lat=$1 lon=$2 radius=$3
  if [[ -z $lat || $lat == "null" || -z $lon || $lon == "null" || -z $radius || $radius == "null" ]];then echo ""; return; fi
  local zoom_level=15
  if [[ $radius -gt 1000 ]];then zoom_level=12
  elif [[ $radius -gt 500 ]];then zoom_level=13
  elif [[ $radius -gt 250 ]];then zoom_level=14; fi
  echo "https://check.place/$lat,$lon,$zoom_level,$YY"
}

db_maxmind(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}Maxmind $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-8-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  maxmind=()
  local RESPONSE=$(curl $CurlARG -Ls -$1 -m 10 "https://ipinfo.check.place/$IP?lang=$YY")
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  if [[ -z $RESPONSE ]];then mode_lite=1; else mode_lite=0; fi
  maxmind[asn]=$(echo "$RESPONSE"|jq -r '.ASN.AutonomousSystemNumber')
  maxmind[org]=$(echo "$RESPONSE"|jq -r '.ASN.AutonomousSystemOrganization')
  maxmind[city]=$(echo "$RESPONSE"|jq -r '.City.Name')
  maxmind[post]=$(echo "$RESPONSE"|jq -r '.City.PostalCode')
  maxmind[lat]=$(echo "$RESPONSE"|jq -r '.City.Latitude')
  maxmind[lon]=$(echo "$RESPONSE"|jq -r '.City.Longitude')
  maxmind[rad]=$(echo "$RESPONSE"|jq -r '.City.AccuracyRadius')
  maxmind[continentcode]=$(echo "$RESPONSE"|jq -r '.City.Continent.Code')
  maxmind[continent]=$(echo "$RESPONSE"|jq -r '.City.Continent.Name')
  maxmind[citycountrycode]=$(echo "$RESPONSE"|jq -r '.City.Country.IsoCode')
  maxmind[citycountry]=$(echo "$RESPONSE"|jq -r '.City.Country.Name')
  maxmind[timezone]=$(echo "$RESPONSE"|jq -r '.City.Location.TimeZone')
  maxmind[subcode]=$(echo "$RESPONSE"|jq -r 'if .City.Subdivisions | length > 0 then .City.Subdivisions[0].IsoCode else "N/A" end')
  maxmind[sub]=$(echo "$RESPONSE"|jq -r 'if .City.Subdivisions | length > 0 then .City.Subdivisions[0].Name else "N/A" end')
  maxmind[countrycode]=$(echo "$RESPONSE"|jq -r '.Country.IsoCode')
  maxmind[country]=$(echo "$RESPONSE"|jq -r '.Country.Name')
  maxmind[regcountrycode]=$(echo "$RESPONSE"|jq -r '.Country.RegisteredCountry.IsoCode')
  maxmind[regcountry]=$(echo "$RESPONSE"|jq -r '.Country.RegisteredCountry.Name')
  
  if [[ ${maxmind[lat]} != "null" && ${maxmind[lon]} != "null" ]];then
    maxmind[dms]=$(generate_dms "${maxmind[lat]}" "${maxmind[lon]}")
    maxmind[map]=$(generate_googlemap_url "${maxmind[lat]}" "${maxmind[lon]}" "${maxmind[rad]}")
  else
    maxmind[dms]="null"
    maxmind[map]="null"
  fi
}

db_ipinfo(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}IPinfo $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-7-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  ipinfo=()
  if [[ $IP == *:* ]];then local RESPONSE=$(curl -Ls -m 10 "https://ipinfo.io/widget/demo/$IP")
  else local RESPONSE=$(curl $CurlARG -Ls -m 10 "https://ipinfo.io/widget/demo/$IP"); fi
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  ipinfo[usetype]=$(echo "$RESPONSE"|jq -r '.data.asn.type')
  ipinfo[comtype]=$(echo "$RESPONSE"|jq -r '.data.company.type')
  shopt -s nocasematch
  case ${ipinfo[usetype]} in
    "business")ipinfo[susetype]="${stype[business]}" ;;
    "isp")ipinfo[susetype]="${stype[isp]}" ;;
    "hosting")ipinfo[susetype]="${stype[hosting]}" ;;
    "education")ipinfo[susetype]="${stype[education]}" ;;
    *)ipinfo[susetype]="${stype[other]}" ;;
  esac
  case ${ipinfo[comtype]} in
    "business")ipinfo[scomtype]="${stype[business]}" ;;
    "isp")ipinfo[scomtype]="${stype[isp]}" ;;
    "hosting")ipinfo[scomtype]="${stype[hosting]}" ;;
    "education")ipinfo[scomtype]="${stype[education]}" ;;
    *)ipinfo[scomtype]="${stype[other]}" ;;
  esac
  shopt -u nocasematch
  ipinfo[countrycode]=$(echo "$RESPONSE"|jq -r '.data.country')
  ipinfo[proxy]=$(echo "$RESPONSE"|jq -r '.data.privacy.proxy')
  ipinfo[tor]=$(echo "$RESPONSE"|jq -r '.data.privacy.tor')
  ipinfo[vpn]=$(echo "$RESPONSE"|jq -r '.data.privacy.vpn')
  ipinfo[server]=$(echo "$RESPONSE"|jq -r '.data.privacy.hosting')
  local ISO3166=$(curl -sL -m 10 "${rawgithub}main/ref/iso3166.json")
  ipinfo[asn]=$(echo "$RESPONSE"|jq -r '.data.asn.asn'|sed 's/^AS//')
  ipinfo[org]=$(echo "$RESPONSE"|jq -r '.data.asn.name')
  ipinfo[city]=$(echo "$RESPONSE"|jq -r '.data.city')
  ipinfo[post]=$(echo "$RESPONSE"|jq -r '.data.postal')
  ipinfo[timezone]=$(echo "$RESPONSE"|jq -r '.data.timezone')
  local tmp_str=$(echo "$RESPONSE"|jq -r '.data.loc')
  ipinfo[lat]=$(echo "$tmp_str"|cut -d',' -f1)
  ipinfo[lon]=$(echo "$tmp_str"|cut -d',' -f2)
  ipinfo[countrycode]=$(echo "$RESPONSE"|jq -r '.data.country')
  ipinfo[country]=$(echo "$ISO3166"|jq --arg code "${ipinfo[countrycode]}" -r '.[] | select(.["alpha-2"] == $code) | .name')
  ipinfo[continent]=$(echo "$ISO3166"|jq --arg code "${ipinfo[countrycode]}" -r '.[] | select(.["alpha-2"] == $code) | .region')
  ipinfo[regcountrycode]=$(echo "$RESPONSE"|jq -r '.data.abuse.country')
  ipinfo[regcountry]=$(echo "$ISO3166"|jq --arg code "${ipinfo[regcountrycode]}" -r '.[] | select(.["alpha-2"] == $code) | .name')
  if [[ ${ipinfo[lat]} != "null" && ${ipinfo[lon]} != "null" ]];then
    ipinfo[dms]=$(generate_dms "${ipinfo[lat]}" "${ipinfo[lon]}")
    ipinfo[map]=$(generate_googlemap_url "${ipinfo[lat]}" "${ipinfo[lon]}" "1001")
  else
    ipinfo[dms]="null"
    ipinfo[map]="null"
  fi
}

db_scamalytics(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}Scamalytics $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-12-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  scamalytics=()
  local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=scamalytics")
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  scamalytics[countrycode]=$(echo "$RESPONSE"|jq -r '.external_datasources.maxmind_geolite2.ip_country_code')
  scamalytics[proxy]=$(echo "$RESPONSE"|jq -r '.external_datasources.firehol.is_proxy')
  scamalytics[tor]=$(echo "$RESPONSE"|jq -r '.external_datasources.x4bnet.is_tor')
  scamalytics[vpn]=$(echo "$RESPONSE"|jq -r '.scamalytics.scamalytics_proxy.is_vpn')
  scamalytics[server]=$(echo "$RESPONSE"|jq -r '.scamalytics.scamalytics_proxy.is_datacenter')
  scamalytics[abuser]=$(echo "$RESPONSE"|jq -r '.scamalytics.is_blacklisted_external')
  scamalytics[robot1]=$(echo "$RESPONSE"|jq -r '.external_datasources.x4bnet.is_blacklisted_spambot')
  scamalytics[robot2]=$(echo "$RESPONSE"|jq -r '.external_datasources.x4bnet.is_bot_operamini')
  scamalytics[robot3]=$(echo "$RESPONSE"|jq -r '.external_datasources.x4bnet.is_bot_semrush')
  [[ ${scamalytics[robot1]} == "true" || ${scamalytics[robot2]} == "true" || ${scamalytics[robot3]} == "true" ]]&&scamalytics[robot]="true"
  [[ ${scamalytics[robot1]} == "false" && ${scamalytics[robot2]} == "false" && ${scamalytics[robot3]} == "false" ]]&&scamalytics[robot]="false"
  scamalytics[score]=$(echo "$RESPONSE"|jq -r '.scamalytics.scamalytics_score')
  if [[ ${scamalytics[score]} -lt 20 ]];then scamalytics[risk]="${sscore[low]}"
  elif [[ ${scamalytics[score]} -lt 60 ]];then scamalytics[risk]="${sscore[medium]}"
  elif [[ ${scamalytics[score]} -lt 90 ]];then scamalytics[risk]="${sscore[high]}"
  elif [[ ${scamalytics[score]} -ge 90 ]];then scamalytics[risk]="${sscore[veryhigh]}"
  fi
}

db_ipregistry(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}ipregistry $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-11-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  ipregistry=()
  local tmpgo="sb69ksjcajfs4c"
  local REGISTRY_HTML
  REGISTRY_HTML=$(curl $CurlARG -sL -$1 -m 10 -H "User-Agent: $UA_Browser" "https://ipregistry.co")
  if [[ -n $REGISTRY_HTML ]];then
    if [[ $REGISTRY_HTML =~ apiKey=\"([a-zA-Z0-9]+)\" ]];then tmpgo="${BASH_REMATCH[1]}"; fi
  fi
  local RESPONSE
  RESPONSE=$(curl $CurlARG -sS -$1 --compressed -m 10 -H "authority: api.ipregistry.co" -H "origin: https://ipregistry.co" -H "referer: https://ipregistry.co/" -H "User-Agent: $UA_Browser" "https://api.ipregistry.co/$IP?hostname=true&key=$tmpgo")
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  ipregistry[usetype]=$(echo "$RESPONSE"|jq -r '.connection.type')
  ipregistry[comtype]=$(echo "$RESPONSE"|jq -r '.company.type')
  shopt -s nocasematch
  case ${ipregistry[usetype]} in
    "business")ipregistry[susetype]="${stype[business]}" ;;
    "isp")ipregistry[susetype]="${stype[isp]}" ;;
    "hosting")ipregistry[susetype]="${stype[hosting]}" ;;
    "education")ipregistry[susetype]="${stype[education]}" ;;
    "government")ipregistry[susetype]="${stype[government]}" ;;
    *)ipregistry[susetype]="${stype[other]}" ;;
  esac
  case ${ipregistry[comtype]} in
    "business")ipregistry[scomtype]="${stype[business]}" ;;
    "isp")ipregistry[scomtype]="${stype[isp]}" ;;
    "hosting")ipregistry[scomtype]="${stype[hosting]}" ;;
    "education")ipregistry[scomtype]="${stype[education]}" ;;
    "government")ipregistry[scomtype]="${stype[government]}" ;;
    *)ipregistry[scomtype]="${stype[other]}" ;;
  esac
  shopt -u nocasematch
  ipregistry[countrycode]=$(echo "$RESPONSE"|jq -r '.location.country.code')
  ipregistry[proxy]=$(echo "$RESPONSE"|jq -r '.security.is_proxy')
  ipregistry[tor1]=$(echo "$RESPONSE"|jq -r '.security.is_tor')
  ipregistry[tor2]=$(echo "$RESPONSE"|jq -r '.security.is_tor_exit')
  [[ ${ipregistry[tor1]} == "true" || ${ipregistry[tor2]} == "true" ]]&&ipregistry[tor]="true"
  [[ ${ipregistry[tor1]} == "false" && ${ipregistry[tor2]} == "false" ]]&&ipregistry[tor]="false"
  ipregistry[vpn]=$(echo "$RESPONSE"|jq -r '.security.is_vpn')
  ipregistry[server]=$(echo "$RESPONSE"|jq -r '.security.is_cloud_provider')
  ipregistry[abuser]=$(echo "$RESPONSE"|jq -r '.security.is_abuser')
}

db_ipapi(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}ipapi $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-6-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  ipapi=()
  if [[ $IP == *:* ]];then local RESPONSE=$(curl -Ls -m 10 "https://api.ipapi.is/?q=$IP")
  else local RESPONSE=$(curl $CurlARG -sL -m 10 "https://api.ipapi.is/?q=$IP"); fi
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  ipapi[usetype]=$(echo "$RESPONSE"|jq -r '.asn.type')
  ipapi[comtype]=$(echo "$RESPONSE"|jq -r '.company.type')
  shopt -s nocasematch
  case ${ipapi[usetype]} in
    "business")ipapi[susetype]="${stype[business]}" ;;
    "isp")ipapi[susetype]="${stype[isp]}" ;;
    "hosting")ipapi[susetype]="${stype[hosting]}" ;;
    "education")ipapi[susetype]="${stype[education]}" ;;
    "government")ipapi[susetype]="${stype[government]}" ;;
    "banking")ipapi[susetype]="${stype[banking]}" ;;
    *)ipapi[susetype]="${stype[other]}" ;;
  esac
  case ${ipapi[comtype]} in
    "business")ipapi[scomtype]="${stype[business]}" ;;
    "isp")ipapi[scomtype]="${stype[isp]}" ;;
    "hosting")ipapi[scomtype]="${stype[hosting]}" ;;
    "education")ipapi[scomtype]="${stype[education]}" ;;
    "government")ipapi[scomtype]="${stype[government]}" ;;
    "banking")ipapi[scomtype]="${stype[banking]}" ;;
    *)ipapi[scomtype]="${stype[other]}" ;;
  esac
  [[ -z $RESPONSE ]]&&return 1
  ipapi[scoretext]=$(echo "$RESPONSE"|jq -r '.company.abuser_score')
  ipapi[scorenum]=$(echo "${ipapi[scoretext]}"|awk '{print $1}')
  ipapi[risktext]=$(echo "${ipapi[scoretext]}"|awk -F'[()]' '{print $2}')
  ipapi[score]=$(awk "BEGIN {printf \"%.2f%%\", ${ipapi[scorenum]} * 100}")
  case ${ipapi[risktext]} in
    "Very Low")ipapi[risk]="${sscore[verylow]}" ;;
    "Low")ipapi[risk]="${sscore[low]}" ;;
    "Elevated")ipapi[risk]="${sscore[elevated]}" ;;
    "High")ipapi[risk]="${sscore[high]}" ;;
    "Very High")ipapi[risk]="${sscore[veryhigh]}" ;;
  esac
  shopt -u nocasematch
  ipapi[countrycode]=$(echo "$RESPONSE"|jq -r '.location.country_code')
  ipapi[proxy]=$(echo "$RESPONSE"|jq -r '.is_proxy')
  ipapi[tor]=$(echo "$RESPONSE"|jq -r '.is_tor')
  ipapi[vpn]=$(echo "$RESPONSE"|jq -r '.is_vpn')
  ipapi[server]=$(echo "$RESPONSE"|jq -r '.is_datacenter')
  ipapi[abuser]=$(echo "$RESPONSE"|jq -r '.is_abuser')
  ipapi[robot]=$(echo "$RESPONSE"|jq -r '.is_crawler')
}

db_abuseipdb(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}AbuseIPDB $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-10-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  abuseipdb=()
  local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=abuseipdb")
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  abuseipdb[usetype]=$(echo "$RESPONSE"|jq -r '.data.usageType')
  shopt -s nocasematch
  case ${abuseipdb[usetype]} in
    "Commercial")abuseipdb[susetype]="${stype[business]}" ;;
    "Data Center/Web Hosting/Transit")abuseipdb[susetype]="${stype[hosting]}" ;;
    "University/College/School")abuseipdb[susetype]="${stype[education]}" ;;
    "Government")abuseipdb[susetype]="${stype[government]}" ;;
    "banking")abuseipdb[susetype]="${stype[banking]}" ;;
    "Organization")abuseipdb[susetype]="${stype[organization]}" ;;
    "Military")abuseipdb[susetype]="${stype[military]}" ;;
    "Library")abuseipdb[susetype]="${stype[library]}" ;;
    "Content Delivery Network")abuseipdb[susetype]="${stype[cdn]}" ;;
    "Fixed Line ISP")abuseipdb[susetype]="${stype[lineisp]}" ;;
    "Mobile ISP")abuseipdb[susetype]="${stype[mobile]}" ;;
    "Search Engine Spider")abuseipdb[susetype]="${stype[spider]}" ;;
    "Reserved")abuseipdb[susetype]="${stype[reserved]}" ;;
    *)abuseipdb[susetype]="${stype[other]}" ;;
  esac
  shopt -u nocasematch
  abuseipdb[score]=$(echo "$RESPONSE"|jq -r '.data.abuseConfidenceScore')
  if [[ ${abuseipdb[score]} -lt 25 ]];then abuseipdb[risk]="${sscore[low]}"
  elif [[ ${abuseipdb[score]} -lt 75 ]];then abuseipdb[risk]="${sscore[high]}"
  elif [[ ${abuseipdb[score]} -ge 75 ]];then abuseipdb[risk]="${sscore[dos]}"
  fi
}

db_ip2location(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}IP2LOCATION $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-12-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  ip2location=()
  local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=ip2location")
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  ip2location[usetype]=$(echo "$RESPONSE"|jq -r '.usage_type')
  ip2location[comtype]=$(echo "$RESPONSE"|jq -r '.as_info.as_usage_type')
  shopt -s nocasematch
  local first_use="${ip2location[usetype]%%/*}"
  case $first_use in
    "COM")ip2location[susetype]="${stype[business]}" ;;
    "DCH")ip2location[susetype]="${stype[hosting]}" ;;
    "EDU")ip2location[susetype]="${stype[education]}" ;;
    "GOV")ip2location[susetype]="${stype[government]}" ;;
    "ORG")ip2location[susetype]="${stype[organization]}" ;;
    "MIL")ip2location[susetype]="${stype[military]}" ;;
    "LIB")ip2location[susetype]="${stype[library]}" ;;
    "CDN")ip2location[susetype]="${stype[cdn]}" ;;
    "ISP")ip2location[susetype]="${stype[lineisp]}" ;;
    "MOB")ip2location[susetype]="${stype[mobile]}" ;;
    "SES")ip2location[susetype]="${stype[spider]}" ;;
    "RSV")ip2location[susetype]="${stype[reserved]}" ;;
    *)ip2location[susetype]="${stype[other]}" ;;
  esac
  first_use="${ip2location[comtype]%%/*}"
  case $first_use in
    "COM")ip2location[scomtype]="${stype[business]}" ;;
    "DCH")ip2location[scomtype]="${stype[hosting]}" ;;
    "EDU")ip2location[scomtype]="${stype[education]}" ;;
    "GOV")ip2location[scomtype]="${stype[government]}" ;;
    "ORG")ip2location[scomtype]="${stype[organization]}" ;;
    "MIL")ip2location[scomtype]="${stype[military]}" ;;
    "LIB")ip2location[scomtype]="${stype[library]}" ;;
    "CDN")ip2location[scomtype]="${stype[cdn]}" ;;
    "ISP")ip2location[scomtype]="${stype[lineisp]}" ;;
    "MOB")ip2location[scomtype]="${stype[mobile]}" ;;
    "SES")ip2location[scomtype]="${stype[spider]}" ;;
    "RSV")ip2location[scomtype]="${stype[reserved]}" ;;
    *)ip2location[scomtype]="${stype[other]}" ;;
  esac
  shopt -u nocasematch
  ip2location[countrycode]=$(echo "$RESPONSE"|jq -r '.country_code')
  ip2location[proxy0]=$(echo "$RESPONSE"|jq -r '.is_proxy')
  ip2location[proxy1]=$(echo "$RESPONSE"|jq -r '.proxy.is_public_proxy')
  ip2location[proxy2]=$(echo "$RESPONSE"|jq -r '.proxy.is_web_proxy')
  [[ ${ip2location[proxy0]} == "true" || ${ip2location[proxy1]} == "true" || ${ip2location[proxy2]} == "true" ]]&&ip2location[proxy]="true"
  [[ ${ip2location[proxy0]} == "false" && ${ip2location[proxy1]} == "false" && ${ip2location[proxy2]} == "false" ]]&&ip2location[proxy]="false"
  ip2location[tor]=$(echo "$RESPONSE"|jq -r '.proxy.is_tor')
  ip2location[vpn]=$(echo "$RESPONSE"|jq -r '.proxy.is_vpn')
  ip2location[server]=$(echo "$RESPONSE"|jq -r '.proxy.is_data_center')
  ip2location[abuser]=$(echo "$RESPONSE"|jq -r '.proxy.is_spammer')
  ip2location[robot1]=$(echo "$RESPONSE"|jq -r '.proxy.is_web_crawler')
  ip2location[robot2]=$(echo "$RESPONSE"|jq -r '.proxy.is_scanner')
  ip2location[robot3]=$(echo "$RESPONSE"|jq -r '.proxy.is_botnet')
  [[ ${ip2location[robot1]} == "true" || ${ip2location[robot2]} == "true" || ${ip2location[robot3]} == "true" ]]&&ip2location[robot]="true"
  [[ ${ip2location[robot1]} == "false" && ${ip2location[robot2]} == "false" && ${ip2location[robot3]} == "false" ]]&&ip2location[robot]="false"
  ip2location[score]=$(echo "$RESPONSE"|jq -r '.fraud_score')
  if [[ ${ip2location[score]} -lt 33 ]];then ip2location[risk]="${sscore[low]}"
  elif [[ ${ip2location[score]} -lt 66 ]];then ip2location[risk]="${sscore[medium]}"
  elif [[ ${ip2location[score]} -ge 66 ]];then ip2location[risk]="${sscore[high]}"
  fi
}

db_dbip(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}DB-IP $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-6-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  dbip=()
  if [[ $IP == *:* ]];then local RESPONSE=$(curl -sL -m 10 "https://db-ip.com/$IP")
  else local RESPONSE=$(curl $CurlARG -sL -m 10 "https://db-ip.com/$IP"); fi
  mapfile -t results < <(echo "$RESPONSE"|awk '/<th class='\''text-center'\''>Crawler/ {flag=1; next}
               flag && /<span class="sr-only">/ {
                   if ($0 ~ /Yes/) print "true";
                   else if ($0 ~ /No/) print "false";
               }
               /<\/tr>/ && flag {flag=0}')
  dbip[robot]="${results[0]}"
  dbip[proxy]="${results[1]}"
  dbip[abuser]="${results[2]}"
  dbip[risktext]=$(echo "$RESPONSE"|sed -n 's/.*Estimated threat level for this IP address is[[:space:]]*<span[^>]*>\([^<]*\)<.*/\1/p')
  dbip[countrycode]=$(echo "$RESPONSE"|sed -n '/<code class="language-json">/,/<\/code>/p'|sed -n 's/.*"countryCode"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  shopt -s nocasematch
  case ${dbip[risktext]} in
    "low")dbip[risk]="${sscore[low]}"; dbip[score]=0 ;;
    "medium")dbip[risk]="${sscore[medium]}"; dbip[score]=50 ;;
    "high")dbip[risk]="${sscore[high]}"; dbip[score]=100 ;;
  esac
  shopt -u nocasematch
}

db_ipdata(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}ipdata $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-7-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  ipdata=()
  local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=ipdata")
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  ipdata[countrycode]=$(echo "$RESPONSE"|jq -r '.country_code')
  ipdata[proxy]=$(echo "$RESPONSE"|jq -r '.threat.is_proxy')
  ipdata[tor]=$(echo "$RESPONSE"|jq -r '.threat.is_tor')
  ipdata[server]=$(echo "$RESPONSE"|jq -r '.threat.is_datacenter')
  ipdata[abuser1]=$(echo "$RESPONSE"|jq -r '.threat.is_threat')
  ipdata[abuser2]=$(echo "$RESPONSE"|jq -r '.threat.is_known_abuser')
  ipdata[abuser3]=$(echo "$RESPONSE"|jq -r '.threat.is_known_attacker')
  [[ ${ipdata[abuser1]} == "true" || ${ipdata[abuser2]} == "true" || ${ipdata[abuser3]} == "true" ]]&&ipdata[abuser]="true"
  [[ ${ipdata[abuser1]} == "false" && ${ipdata[abuser2]} == "false" && ${ipdata[abuser3]} == "false" ]]&&ipdata[abuser]="false"
}

db_ipqs(){
  local temp_info="$Font_Cyan$Font_B${sinfo[database]}${Font_I}IPQS $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-5-${sinfo[ldatabase]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  ipqs=()
  local RESPONSE=$(curl $CurlARG -sL -$1 -m 10 "https://ipinfo.check.place/$IP?db=ipqualityscore")
  echo "$RESPONSE"|jq . >/dev/null 2>&1||RESPONSE=""
  ipqs[score]=$(echo "$RESPONSE"|jq -r '.fraud_score')
  if [[ ${ipqs[score]} -lt 75 ]];then ipqs[risk]="${sscore[low]}"
  elif [[ ${ipqs[score]} -lt 85 ]];then ipqs[risk]="${sscore[suspicious]}"
  elif [[ ${ipqs[score]} -lt 90 ]];then ipqs[risk]="${sscore[risky]}"
  elif [[ ${ipqs[score]} -ge 90 ]];then ipqs[risk]="${sscore[highrisk]}"
  fi
  ipqs[countrycode]=$(echo "$RESPONSE"|jq -r '.country_code')
  ipqs[proxy]=$(echo "$RESPONSE"|jq -r '.proxy')
  ipqs[tor]=$(echo "$RESPONSE"|jq -r '.tor')
  ipqs[vpn]=$(echo "$RESPONSE"|jq -r '.vpn')
  ipqs[abuser]=$(echo "$RESPONSE"|jq -r '.recent_abuse')
  ipqs[robot]=$(echo "$RESPONSE"|jq -r '.bot_status')
}

check_ip_valide(){
  local IPPattern='^(\<([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\>\.){3}\<([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])\>$'
  IP="$1"
  if [[ $IP =~ $IPPattern ]];then return 0; else return 1; fi
}

calc_ip_net(){
  sip="$1"
  snetmask="$2"
  check_ip_valide "$sip"
  if [ $? -ne 0 ];then echo ""; return 1; fi
  local ipFIELD1=$(echo "$sip"|cut -d. -f1)
  local ipFIELD2=$(echo "$sip"|cut -d. -f2)
  local ipFIELD3=$(echo "$sip"|cut -d. -f3)
  local ipFIELD4=$(echo "$sip"|cut -d. -f4)
  local netmaskFIELD1=$(echo "$snetmask"|cut -d. -f1)
  local netmaskFIELD2=$(echo "$snetmask"|cut -d. -f2)
  local netmaskFIELD3=$(echo "$snetmask"|cut -d. -f3)
  local netmaskFIELD4=$(echo "$snetmask"|cut -d. -f4)
  local tmpret1=$((ipFIELD1&netmaskFIELD1))
  local tmpret2=$((ipFIELD2&netmaskFIELD2))
  local tmpret3=$((ipFIELD3&netmaskFIELD3))
  local tmpret4=$((ipFIELD4&netmaskFIELD4))
  echo "$tmpret1.$tmpret2.$tmpret3.$tmpret4"
}

Check_DNS_IP(){
  if [ "$1" != "${1#*[0-9].[0-9]}" ];then
    if [ "$(calc_ip_net "$1" 255.0.0.0)" == "10.0.0.0" ];then echo 0
    elif [ "$(calc_ip_net "$1" 255.240.0.0)" == "172.16.0.0" ];then echo 0
    elif [ "$(calc_ip_net "$1" 255.255.0.0)" == "169.254.0.0" ];then echo 0
    elif [ "$(calc_ip_net "$1" 255.255.0.0)" == "192.168.0.0" ];then echo 0
    elif [ "$(calc_ip_net "$1" 255.255.255.0)" == "$(calc_ip_net "$2" 255.255.255.0)" ];then echo 0
    else echo 1
    fi
  elif [ "$1" != "${1#*[0-9a-fA-F]:*}" ];then
    if [ "${1:0:3}" == "fe8" ] || [ "${1:0:3}" == "FE8" ] || [ "${1:0:2}" == "fc" ] || [ "${1:0:2}" == "FC" ] || [ "${1:0:2}" == "fd" ] || [ "${1:0:2}" == "FD" ] || [ "${1:0:2}" == "ff" ] || [ "${1:0:2}" == "FF" ];then echo 0
    else echo 1
    fi
  else echo 0
  fi
}

Check_DNS_1(){
  local resultdns=$(nslookup $1)
  local resultinlines=(${resultdns//$'\n'/ })
  for i in ${resultinlines[*]};do
    if [[ $i == "Name:" ]];then local resultdnsindex=$((resultindex+3)); break; fi
    local resultindex=$((resultindex+1))
  done
  echo $(Check_DNS_IP ${resultinlines[$resultdnsindex]} ${resultinlines[1]})
}

Check_DNS_2(){
  local resultdnstext=$(dig $1|grep "ANSWER:")
  local resultdnstext=${resultdnstext#*"ANSWER: "}
  local resultdnstext=${resultdnstext%", AUTHORITY:"*}
  if [ "$resultdnstext" == "0" ]||[ "$resultdnstext" == "1" ]||[ "$resultdnstext" == "2" ];then echo 0
  else echo 1
  fi
}

Check_DNS_3(){
  local resultdnstext=$(dig "test$RANDOM$RANDOM.$1"|grep "ANSWER:")
  local resultdnstext=${resultdnstext#*"ANSWER: "}
  local resultdnstext=${resultdnstext%", AUTHORITY:"*}
  if [ "$resultdnstext" == "0" ];then echo 1
  else echo 0
  fi
}

Get_Unlock_Type(){
  while [ $# -ne 0 ];do
    if [ "$1" = "0" ];then echo "${smedia[dns]}"; return; fi
    shift
  done
  echo "${smedia[native]}"
}

MediaUnlockTest_TikTok(){
  local temp_info="$Font_Cyan$Font_B${sinfo[media]}${Font_I}TikTok $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-7-${sinfo[lmedia]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  tiktok=()
  local checkunlockurl="tiktok.com"
  local result1=$(Check_DNS_1 $checkunlockurl)
  local result3=$(Check_DNS_3 $checkunlockurl)
  local resultunlocktype=$(Get_Unlock_Type $result1 $result3)
  local Ftmpresult=$(curl $CurlARG -$1 --user-agent "$UA_Browser" -sL -m 10 "https://www.tiktok.com/")
  [[ $Ftmpresult == *"Please wait..."* ]]&&Ftmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "$UA_Browser" -sL -m 10 "https://www.tiktok.com/explore")
  if [[ $Ftmpresult == "curl"* ]];then
    tiktok[ustatus]="${smedia[no]}"
    tiktok[uregion]="${smedia[nodata]}"
    tiktok[utype]="${smedia[nodata]}"
    return
  fi
  local FRegion=$(echo $Ftmpresult|grep '"region":'|sed 's/.*"region"//'|cut -f2 -d'"')
  if [ -n "$FRegion" ];then
    tiktok[ustatus]="${smedia[yes]}"
    local ttpadding=$((7-${#FRegion}))
    local ttleft=$((ttpadding/2))
    local ttright=$((ttpadding-ttleft))
    tiktok[uregion]="$(printf "%*s%s%*s" "$ttleft" "" "[$FRegion]" "$ttright" "")"
    tiktok[utype]="$resultunlocktype"
    return
  fi
  local STmpresult=$(curl $CurlARG -$1 --user-agent "$UA_Browser" -sL -m 10 -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9" -H "Accept-Encoding: gzip" -H "Accept-Language: en" "https://www.tiktok.com"|gunzip 2>/dev/null)
  [[ $Ftmpresult == *"Please wait..."* ]]&&STmpresult=$(curl $useNIC $usePROXY $xForward --user-agent "$UA_Browser" -sL -m 10 -H "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9" -H "Accept-Encoding: gzip" -H "Accept-Language: en" "https://www.tiktok.com/explore"|gunzip 2>/dev/null)
  local SRegion=$(echo $STmpresult|grep '"region":'|sed 's/.*"region"//'|cut -f2 -d'"')
  if [ -n "$SRegion" ];then
    tiktok[ustatus]="${smedia[idc]}"
    local ttWidth=7
    local ttpadding=$((7-${#SRegion}))
    local ttleft=$((ttpadding/2))
    local ttright=$((ttpadding-ttleft))
    tiktok[uregion]="$(printf "%*s%s%*s" "$ttleft" "" "[$SRegion]" "$ttright" "")"
    tiktok[utype]="$resultunlocktype"
    return
  else
    tiktok[ustatus]="${smedia[bad]}"
    tiktok[uregion]="${smedia[nodata]}"
    tiktok[utype]="${smedia[nodata]}"
    return
  fi
}

MediaUnlockTest_DisneyPlus(){
  local temp_info="$Font_Cyan$Font_B${sinfo[media]}${Font_I}Disney+ $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-8-${sinfo[lmedia]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  disney=()
  local checkunlockurl="disneyplus.com"
  local result1=$(Check_DNS_1 $checkunlockurl)
  local result3=$(Check_DNS_3 $checkunlockurl)
  local resultunlocktype=$(Get_Unlock_Type $result1 $result3)
  local PreAssertion=$(curl $CurlARG -$1 --user-agent "$UA_Browser" -s --max-time 10 -X POST "https://disney.api.edge.bamgrid.com/devices" -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -H "content-type: application/json; charset=UTF-8" -d '{"deviceFamily":"browser","applicationRuntime":"chrome","deviceProfile":"windows","attributes":{}}' 2>&1)
  if [[ $PreAssertion == "curl"* ]];then
    disney[ustatus]="${smedia[bad]}"
    disney[uregion]="${smedia[nodata]}"
    disney[utype]="${smedia[nodata]}"
    return
  fi
  if ! (echo "$PreAssertion"|jq . >/dev/null 2>&1&&echo "$TokenContent"|jq . >/dev/null 2>&1);then
    disney[ustatus]="${smedia[bad]}"
    disney[uregion]="${smedia[nodata]}"
    disney[utype]="${smedia[nodata]}"
    return
  fi
  local assertion=$(echo $PreAssertion|jq -r '.assertion')
  local PreDisneyCookie=$(echo "$Media_Cookie"|sed -n '1p')
  local disneycookie=$(echo $PreDisneyCookie|sed "s/DISNEYASSERTION/$assertion/g")
  local TokenContent=$(curl $CurlARG -$1 --user-agent "$UA_Browser" -s --max-time 10 -X POST "https://disney.api.edge.bamgrid.com/token" -H "authorization: Bearer ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -d "$disneycookie" 2>&1)
  local isBanned=$(echo $TokenContent|jq -r 'select(.error_description == "forbidden-location") | .error_description')
  local is403=$(echo $TokenContent|grep '403 ERROR')
  if [ -n "$isBanned" ]||[ -n "$is403" ];then
    disney[ustatus]="${smedia[no]}"
    disney[uregion]="${smedia[nodata]}"
    disney[utype]="${smedia[nodata]}"
    return
  fi
  local fakecontent=$(echo "$Media_Cookie"|sed -n '8p')
  local refreshToken=$(echo $TokenContent|jq -r '.refresh_token')
  local disneycontent=$(echo $fakecontent|sed "s/ILOVEDISNEY/$refreshToken/g")
  local tmpresult=$(curl $CurlARG -$1 --user-agent "$UA_Browser" -X POST -sSL --max-time 10 "https://disney.api.edge.bamgrid.com/graph/v1/device/graphql" -H "authorization: ZGlzbmV5JmJyb3dzZXImMS4wLjA.Cu56AgSfBTDag5NiRA81oLHkDZfu5L3CKadnefEAY84" -d "$disneycontent" 2>&1)
  if ! (echo "$tmpresult"|jq . >/dev/null 2>&1);then
    disney[ustatus]="${smedia[bad]}"
    disney[uregion]="${smedia[nodata]}"
    disney[utype]="${smedia[nodata]}"
    return
  fi
  local previewcheck=$(curl $CurlARG -$1 -s -o /dev/null -L --max-time 10 -w '%{url_effective}\n' "https://disneyplus.com"|grep preview)
  local isUnavailable=$(echo $previewcheck|grep 'unavailable')
  local region=$(echo $tmpresult|jq -r '.extensions.sdk.session.location.countryCode')
  local inSupportedLocation=$(echo $tmpresult|jq -r '.extensions.sdk.session.inSupportedLocation')
  if [[ $region == "JP" ]];then
    disney[ustatus]="${smedia[yes]}"
    disney[uregion]="  [JP]   "
    disney[utype]="$resultunlocktype"
    return
  elif [ -n "$region" ]&&[[ $inSupportedLocation == "false" ]]&&[ -z "$isUnavailable" ];then
    disney[ustatus]="${smedia[pending]}"
    disney[uregion]="  [$region]   "
    disney[utype]="$resultunlocktype"
    return
  elif [ -n "$region" ]&&[ -n "$isUnavailable" ];then
    disney[ustatus]="${smedia[no]}"
    disney[uregion]="${smedia[nodata]}"
    disney[utype]="${smedia[nodata]}"
    return
  elif [ -n "$region" ]&&[[ $inSupportedLocation == "true" ]];then
    disney[ustatus]="${smedia[yes]}"
    disney[uregion]="  [$region]   "
    disney[utype]="$resultunlocktype"
    return
  elif [ -z "$region" ];then
    disney[ustatus]="${smedia[no]}"
    disney[uregion]="${smedia[nodata]}"
    disney[utype]="${smedia[nodata]}"
    return
  else
    disney[ustatus]="${smedia[bad]}"
    disney[uregion]="${smedia[nodata]}"
    disney[utype]="${smedia[nodata]}"
    return
  fi
}

MediaUnlockTest_Netflix(){
  local temp_info="$Font_Cyan$Font_B${sinfo[media]}${Font_I}Netflix $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-8-${sinfo[lmedia]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  netflix=()
  local checkunlockurl="netflix.com"
  local result1=$(Check_DNS_1 $checkunlockurl)
  local result2=$(Check_DNS_2 $checkunlockurl)
  local result3=$(Check_DNS_3 $checkunlockurl)
  local resultunlocktype=$(Get_Unlock_Type $result1 $result2 $result3)
  local result1=$(curl $CurlARG -$1 --user-agent "$UA_Browser" -fsL -X GET --max-time 10 --tlsv1.3 "https://www.netflix.com/title/81280792" 2>&1)
  local result2=$(curl $CurlARG -$1 --user-agent "$UA_Browser" -fsL -X GET --max-time 10 --tlsv1.3 "https://www.netflix.com/title/70143836" 2>&1)
  if [ -z "$result1" ]||[ -z "$result2" ];then
    netflix[ustatus]="${smedia[bad]}"
    netflix[uregion]="${smedia[nodata]}"
    netflix[utype]="${smedia[nodata]}"
    return
  fi
  region=$(echo "$result1"|sed -n 's/.*"id":"\([^"]*\)".*"countryName":"[^"]*".*/\1/p'|head -n1)
  [[ -n $region ]]&&region=$(echo "$result2"|sed -n 's/.*"id":"\([^"]*\)".*"countryName":"[^"]*".*/\1/p'|head -n1)
  result1=$(echo $result1|grep 'Oh no!')
  result2=$(echo $result2|grep 'Oh no!')
  if [ -n "$result1" ]&&[ -n "$result2" ];then
    netflix[ustatus]="${smedia[org]}"
    netflix[uregion]="  [$region]   "
    netflix[utype]="$resultunlocktype"
    return
  fi
  if [ -z "$result1" ]||[ -z "$result2" ];then
    netflix[ustatus]="${smedia[yes]}"
    netflix[uregion]="  [$region]   "
    netflix[utype]="$resultunlocktype"
    return
  fi
  netflix[ustatus]="${smedia[no]}"
  netflix[uregion]="${smedia[nodata]}"
  netflix[utype]="${smedia[nodata]}"
}

MediaUnlockTest_YouTube_Premium(){
  local temp_info="$Font_Cyan$Font_B${sinfo[media]}${Font_I}Youtube $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-8-${sinfo[lmedia]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  youtube=()
  local checkunlockurl="www.youtube.com"
  local result1=$(Check_DNS_1 $checkunlockurl)
  local result3=$(Check_DNS_3 $checkunlockurl)
  local resultunlocktype=$(Get_Unlock_Type $result1 $result3)
  local tmpresult=$(curl $CurlARG -$1 --max-time 10 -sSL -H "Accept-Language: en" -b "YSC=BiCUU3-5Gdk; CONSENT=YES+cb.20220301-11-p0.en+FX+700; GPS=1; VISITOR_INFO1_LIVE=4VwPMkB7W5A; PREF=tz=Asia.Shanghai; _gcl_au=1.1.1809531354.1646633279" "https://www.youtube.com/premium" 2>&1)
  if [[ $tmpresult == "curl"* ]];then
    youtube[ustatus]="${smedia[bad]}"
    youtube[uregion]="${smedia[nodata]}"
    youtube[utype]="${smedia[nodata]}"
    return
  fi
  local isCN=$(echo $tmpresult|grep 'www.google.cn')
  if [ -n "$isCN" ];then
    youtube[ustatus]="${smedia[cn]}"
    youtube[uregion]="  $Font_Red[CN]$Font_Green   "
    youtube[utype]="${smedia[nodata]}"
    return
  fi
  local isNotAvailable=$(echo $tmpresult|grep 'Premium is not available in your country')
  local region=$(echo $tmpresult|sed -n 's/.*"contentRegion":"\([^"]*\)".*/\1/p')
  local isAvailable=$(echo $tmpresult|grep 'ad-free')
  if [ -n "$isNotAvailable" ];then
    youtube[ustatus]="${smedia[noprem]}"
    youtube[uregion]="${smedia[nodata]}"
    youtube[utype]="${smedia[nodata]}"
    return
  elif [ -n "$isAvailable" ]&&[ -n "$region" ];then
    youtube[ustatus]="${smedia[yes]}"
    youtube[uregion]="  [$region]   "
    youtube[utype]="$resultunlocktype"
    return
  elif [ -z "$region" ]&&[ -n "$isAvailable" ];then
    youtube[ustatus]="${smedia[yes]}"
    youtube[uregion]="${smedia[nodata]}"
    youtube[utype]="$resultunlocktype"
    return
  else
    youtube[ustatus]="${smedia[bad]}"
    youtube[uregion]="${smedia[nodata]}"
    youtube[utype]="${smedia[nodata]}"
  fi
}

MediaUnlockTest_PrimeVideo_Region(){
  local temp_info="$Font_Cyan$Font_B${sinfo[media]}${Font_I}Amazon $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-7-${sinfo[lmedia]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  amazon=()
  local checkunlockurl="www.primevideo.com"
  local result1=$(Check_DNS_1 $checkunlockurl)
  local result3=$(Check_DNS_3 $checkunlockurl)
  local resultunlocktype=$(Get_Unlock_Type $result1 $result3)
  local tmpresult=$(curl $CurlARG -$1 --user-agent "$UA_Browser" -sL --max-time 10 "https://www.primevideo.com" 2>&1)
  if [[ $tmpresult == "curl"* ]];then
    amazon[ustatus]="${smedia[bad]}"
    amazon[uregion]="${smedia[nodata]}"
    amazon[utype]="${smedia[nodata]}"
    return
  fi
  local result=$(echo $tmpresult|grep '"currentTerritory":'|sed 's/.*currentTerritory//'|cut -f3 -d'"'|head -n 1)
  if [ -n "$result" ];then
    amazon[ustatus]="${smedia[yes]}"
    amazon[uregion]="  [$result]   "
    amazon[utype]="$resultunlocktype"
    return
  else
    amazon[ustatus]="${smedia[no]}"
    amazon[uregion]="${smedia[nodata]}"
    amazon[utype]="${smedia[nodata]}"
    return
  fi
}

MediaUnlockTest_Reddit(){
  local temp_info="$Font_Cyan$Font_B${sinfo[media]}${Font_I}Reddit $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-7-${sinfo[lmedia]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  reddit=()
  local checkunlockurl="reddit.com"
  local result1=$(Check_DNS_1 $checkunlockurl)
  local result2=$(Check_DNS_2 $checkunlockurl)
  local resultunlocktype=$(Get_Unlock_Type $result1 $result2)
  local resp http_code html region
  local resolve_opt=""
  if [ "$1" = "6" ];then
    local dual_ipv6
    dual_ipv6=$(dig AAAA reddit.com +short|head -n 1)
    [[ -z $dual_ipv6 ]]&&dual_ipv6=$(dig AAAA dualstack.reddit.map.fastly.net +short|head -n 1)
    if [ -n "$dual_ipv6" ];then resolve_opt="--resolve www.reddit.com:443:[$dual_ipv6]"
    else
      reddit[ustatus]="${smedia[bad]}"
      reddit[uregion]="${smedia[nodata]}"
      reddit[utype]="${smedia[nodata]}"
      return
    fi
  fi
  resp=$(curl $useNIC $usePROXY $xForward -$1 $ssll -fsL --user-agent "$UA_Browser" --max-time 10 $resolve_opt --write-out '\n%{http_code}' "https://www.reddit.com/")
  http_code=$(printf '%s' "$resp"|tail -n 1|tr -d '\r')
  html=$(printf '%s' "$resp"|sed '$d')
  if [ "$http_code" = "200" ];then
    region=$(printf '%s' "$html"|tr '\n' ' '|sed -n 's/.*country="\([^"]*\)".*/\1/p'|head -n 1)
  fi
  case "$http_code" in
    000)reddit[ustatus]="${smedia[bad]}"; reddit[uregion]="${smedia[nodata]}"; reddit[utype]="${smedia[nodata]}" ;;
    403)reddit[ustatus]="${smedia[no]}"; reddit[uregion]="${smedia[nodata]}"; reddit[utype]="${smedia[nodata]}" ;;
    200)reddit[ustatus]="${smedia[yes]}"; reddit[uregion]="  [$region]   "; reddit[utype]="$resultunlocktype" ;;
    *)reddit[ustatus]="${smedia[bad]}"; reddit[uregion]="${smedia[nodata]}"; reddit[utype]="${smedia[nodata]}" ;;
  esac
}

OpenAITest(){
  local temp_info="$Font_Cyan$Font_B${sinfo[ai]}${Font_I}ChatGPT $Font_Suffix"
  ((ibar_step+=3))
  show_progress_bar "$temp_info" $((40-8-${sinfo[lai]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  chatgpt=()
  local checkunlockurl="chat.openai.com"
  local result1=$(Check_DNS_1 $checkunlockurl)
  local result2=$(Check_DNS_2 $checkunlockurl)
  local result3=$(Check_DNS_3 $checkunlockurl)
  local checkunlockurl="ios.chat.openai.com"
  local result4=$(Check_DNS_1 $checkunlockurl)
  local result5=$(Check_DNS_2 $checkunlockurl)
  local result6=$(Check_DNS_3 $checkunlockurl)
  local checkunlockurl="api.openai.com"
  local result7=$(Check_DNS_1 $checkunlockurl)
  local result8=$(Check_DNS_3 $checkunlockurl)
  local resultunlocktype=$(Get_Unlock_Type $result1 $result2 $result3 $result4 $result5 $result6 $result7 $result8)
  local tmpresult1=$(curl $CurlARG -$1 -sS --max-time 10 'https://api.openai.com/compliance/cookie_requirements' -H 'authority: api.openai.com' -H 'accept: */*' -H 'accept-language: zh-CN,zh;q=0.9' -H 'authorization: Bearer null' -H 'content-type: application/json' -H 'origin: https://platform.openai.com' -H 'referer: https://platform.openai.com/' -H 'sec-ch-ua: "Microsoft Edge";v="119", "Chromium";v="119", "Not?A_Brand";v="24"' -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' -H 'sec-fetch-dest: empty' -H 'sec-fetch-mode: cors' -H 'sec-fetch-site: same-site' -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 Edg/119.0.0.0' 2>&1)
  local tmpresult2=$(curl $CurlARG -$1 -sS --max-time 10 'https://ios.chat.openai.com/' -H 'authority: ios.chat.openai.com' -H 'accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7' -H 'accept-language: zh-CN,zh;q=0.9' -H 'sec-ch-ua: "Microsoft Edge";v="119", "Chromium";v="119", "Not?A_Brand";v="24"' -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' -H 'sec-fetch-dest: document' -H 'sec-fetch-mode: navigate' -H 'sec-fetch-site: none' -H 'sec-fetch-user: ?1' -H 'upgrade-insecure-requests: 1' -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 Edg/119.0.0.0' 2>&1)
  local result1=$(echo $tmpresult1|grep unsupported_country)
  local result2=$(echo $tmpresult2|grep VPN)
  if [ -n "$result1" ];then
    code=$(curl $CurlARG -$1 -o /dev/null -sS --max-time 10 'https://chatgpt.com/favicon.ico' -H 'accept: image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8' -H 'authority: chatgpt.com' -H 'accept: */*' -H 'accept-language: zh-CN,zh;q=0.9' -H 'authorization: Bearer null' -H 'content-type: application/json' -H 'origin: https://chatgpt.com' -H 'referer: https://chatgpt.com/' -H 'sec-ch-ua: "Microsoft Edge";v="119", "Chromium";v="119", "Not?A_Brand";v="24"' -H 'sec-ch-ua-mobile: ?0' -H 'sec-ch-ua-platform: "Windows"' -H 'sec-fetch-dest: empty' -H 'sec-fetch-mode: cors' -H 'sec-fetch-site: same-site' -H 'user-agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36 Edg/119.0.0.0' -w "%{http_code}" 2>&1)
    [[ $code != "403" ]]&&result1=""
  fi
  local countryCode="$(curl $CurlARG --max-time 10 -sS https://chat.openai.com/cdn-cgi/trace 2>&1|grep "loc="|awk -F= '{print $2}')"
  if [ -z "$result2" ]&&[ -z "$result1" ]&&[[ $tmpresult1 != "curl"* ]]&&[[ $tmpresult2 != "curl"* ]];then
    chatgpt[ustatus]="${smedia[yes]}"
    chatgpt[uregion]="  [$countryCode]   "
    chatgpt[utype]="$resultunlocktype"
  elif [ -n "$result2" ]&&[ -n "$result1" ];then
    chatgpt[ustatus]="${smedia[no]}"
    chatgpt[uregion]="${smedia[nodata]}"
    chatgpt[utype]="${smedia[nodata]}"
  elif [ -z "$result1" ]&&[ -n "$result2" ]&&[[ $tmpresult1 != "curl"* ]];then
    chatgpt[ustatus]="${smedia[web]}"
    chatgpt[uregion]="  [$countryCode]   "
    chatgpt[utype]="$resultunlocktype"
  elif [ -n "$result1" ]&&[ -z "$result2" ];then
    chatgpt[ustatus]="${smedia[app]}"
    chatgpt[uregion]="  [$countryCode]   "
    chatgpt[utype]="$resultunlocktype"
  elif [[ $tmpresult1 == "curl"* ]]&&[ -n "$result2" ];then
    chatgpt[ustatus]="${smedia[no]}"
    chatgpt[uregion]="${smedia[nodata]}"
    chatgpt[utype]="${smedia[nodata]}"
  elif [[ $1 -eq 6 ]]&&[ -z "$result2" ]&&[[ $tmpresult2 != "curl"* ]];then
    chatgpt[ustatus]="${smedia[yes]}"
    chatgpt[uregion]="  [$countryCode]   "
    chatgpt[utype]="$resultunlocktype"
  else
    chatgpt[ustatus]="${smedia[bad]}"
    chatgpt[uregion]="${smedia[nodata]}"
    chatgpt[utype]="${smedia[nodata]}"
  fi
}

get_sorted_mx_records(){
  local domain=$1
  dig +short MX $domain|sort -n|head -1|awk '{print $2}'
}

check_email_service(){
  local service=$1 port=25 expected_response="220" domain="" host="" response="" success="false"
  case $service in
    "Gmail")domain="gmail.com";;
    "Outlook")domain="outlook.com";;
    "Yahoo")domain="yahoo.com";;
    "Apple")domain="me.com";;
    "MailRU")domain="mail.ru";;
    "AOL")domain="aol.com";;
    "GMX")domain="gmx.com";;
    "MailCOM")domain="mail.com";;
    "163")domain="163.com";;
    "Sohu")domain="sohu.com";;
    "Sina")domain="sina.com";;
    "QQ")domain="qq.com";;
    *)return
  esac
  if [[ -z $host ]];then
    local mx_hosts=($(get_sorted_mx_records $domain))
    for host in "${mx_hosts[@]}";do
      response=$(timeout 5 bash -c "echo -e 'QUIT\r\n' | nc -s $IP -w4 $host $port 2>&1")
      if [[ $response == *"$expected_response"* ]];then
        success="true"
        smail[$service]="$Font_Black+$Font_Suffix$Back_Green$Font_White$Font_B$service$Font_Suffix"
        smailstatus[$service]="true"
        smail[remote]=1
        break
      fi
    done
  else
    response=$(timeout 5 bash -c "echo -e 'QUIT\r\n' | nc -s $IP -w4 $host $port 2>&1")
    if [[ $response == *"$expected_response"* ]];then
      success="true"
      smail[$service]="$Font_Black+$Font_Suffix$Back_Green$Font_White$Font_B$service$Font_Suffix"
      smailstatus[$service]="true"
      smail[remote]=1
    fi
  fi
  if [[ $success == "false" ]];then
    smail[$service]="$Font_Black-$Font_Suffix$Back_Red$Font_White$Font_B$service$Font_Suffix"
    smailstatus[$service]="false"
  fi
}

check_mail(){
  ss -tano|grep -q ":25\b"&&smail[local]=2||smail[local]=0
  if [[ smail[local] -ne 2 && -z $usePROXY ]];then
    local response=$(timeout 10 bash -c "echo -e 'QUIT\r\n' | nc -s $IP -p25 -w9 smtp.mailgun.org 25 2>&1")
    [[ $response == *"220"* ]]&&smail[local]=1
  fi
  [[ -n $usePROXY ]]&&smail[local]=0
  smail[remote]=0
  services=("Gmail" "Outlook" "Yahoo" "Apple" "QQ" "MailRU" "AOL" "GMX" "MailCOM" "163" "Sohu" "Sina")
  for service in "${services[@]}";do
    local temp_info="$Font_Cyan$Font_B${sinfo[mail]}$Font_I$service$Font_Suffix "
    ((ibar_step+=3))
    show_progress_bar "$temp_info" $((40-1-${#service}-${sinfo[lmail]}))&
    bar_pid="$!"&&disown "$bar_pid"
    check_email_service $service
    kill_progress_bar
  done
}

check_dnsbl_parallel(){
  ip_to_check=$1
  parallel_jobs=$2
  smail[t]=0; smail[c]=0; smail[m]=0; smail[b]=0
  reversed_ip=$(echo "$ip_to_check"|awk -F. '{print $4"."$3"."$2"."$1}')
  local total=0 clean=0 blacklisted=0 other=0
  curl $CurlARG -sL "https://github.com/xykt/IPQuality/raw/main/ref/dnsbl.list"|sort -u|xargs -P "$parallel_jobs" -I {} bash -c "result=\$(dig +short \"$reversed_ip.{}\" A); if [[ -z \"\$result\" ]]; then echo 'Clean'; elif [[ \"\$result\" == '127.0.0.2' ]]; then echo 'Blacklisted'; else echo 'Other'; fi"|{
  while IFS= read -r line;do
    ((total++))
    case "$line" in
      "Clean")((clean++));;
      "Blacklisted")((blacklisted++));;
      *)((other++))
    esac
  done
  smail[t]="$total"; smail[c]="$clean"; smail[m]="$other"; smail[b]="$blacklisted"
  echo "${smail[t]} ${smail[c]} ${smail[m]} ${smail[b]}"
  }
}

check_dnsbl(){
  local temp_info="$Font_Cyan$Font_B${sinfo[dnsbl]} $Font_Suffix"
  ((ibar_step=95))
  show_progress_bar "$temp_info" $((40-1-${sinfo[ldnsbl]}))&
  bar_pid="$!"&&disown "$bar_pid"
  trap "kill_progress_bar" RETURN
  local num_array=($(check_dnsbl_parallel "$IP" 50))
  smail[t]=${num_array[0]:-0}
  smail[c]=${num_array[1]:-0}
  smail[m]=${num_array[2]:-0}
  smail[b]=${num_array[3]:-0}
  smail[sdnsbl]="$Font_Cyan${smail[dnsbl]}  ${smail[available]}${smail[t]}   ${smail[clean]}${smail[c]}   ${smail[marked]}${smail[m]}   ${smail[blacklisted]}${smail[b]}$Font_Suffix"
}

show_head(){
  echo -ne "\r  $(printf '%72s'|tr ' ' '#')\n"
  if [[ $mode_lite -eq 0 ]];then
    if [ $fullIP -eq 1 ];then
      calc_padding "$(printf '%*s' "${shead[ltitle]}" '')$IP" 72
      echo -ne "\r  $PADDING$Font_B${shead[title]}$Font_Cyan$IP$Font_Suffix\n"
    else
      calc_padding "$(printf '%*s' "${shead[ltitle]}" '')$IPhide" 72
      echo -ne "\r  $PADDING$Font_B${shead[title]}$Font_Cyan$IPhide$Font_Suffix\n"
    fi
  else
    if [ $fullIP -eq 1 ];then
      calc_padding "$(printf '%*s' "${shead[ltitle_lite]}" '')$IP" 72
      echo -ne "\r  $PADDING$Font_B${shead[title_lite]}$Font_Cyan$IP$Font_Suffix\n"
    else
      calc_padding "$(printf '%*s' "${shead[ltitle_lite]}" '')$IPhide" 72
      echo -ne "\r  $PADDING$Font_B${shead[title_lite]}$Font_Cyan$IPhide$Font_Suffix\n"
    fi
  fi
  calc_padding "${shead[git]}" 72
  echo -ne "\r  $PADDING$Font_U${shead[git]}$Font_Suffix\n"
  echo -ne "\r  ${shead[ptime]}${shead[time]}  ${shead[ver]}\n"
  echo -ne "\r  $(printf '%72s'|tr ' ' '#')\n"
}

show_basic(){
  echo -ne "\r${sbasic[title]}\n"
  if [[ -n ${maxmind[asn]} && ${maxmind[asn]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[asn]}${Font_Green}AS${maxmind[asn]}$Font_Suffix\n"
    echo -ne "\r$Font_Cyan${sbasic[org]}$Font_Green${maxmind[org]}$Font_Suffix\n"
  else
    echo -ne "\r$Font_Cyan${sbasic[asn]}${sbasic[noasn]}$Font_Suffix\n"
  fi
  if [[ ${maxmind[dms]} != "null" && ${maxmind[map]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[location]}$Font_Green${maxmind[dms]}$Font_Suffix\n"
    echo -ne "\r$Font_Cyan${sbasic[map]}$Font_U$Font_Green${maxmind[map]}$Font_Suffix\n"
  fi
  local city_info=""
  [[ -n ${maxmind[sub]} && ${maxmind[sub]} != "null" ]]&&city_info+="${maxmind[sub]}"
  [[ -n ${maxmind[city]} && ${maxmind[city]} != "null" ]]&&{ [[ -n $city_info ]]&&city_info+=", "; city_info+="${maxmind[city]}"; }
  [[ -n ${maxmind[post]} && ${maxmind[post]} != "null" ]]&&{ [[ -n $city_info ]]&&city_info+=", "; city_info+="${maxmind[post]}"; }
  [[ -n $city_info ]]&&echo -ne "\r$Font_Cyan${sbasic[city]}$Font_Green$city_info$Font_Suffix\n"
  if [[ -n ${maxmind[countrycode]} && ${maxmind[countrycode]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[country]}$Font_Green[${maxmind[countrycode]}]${maxmind[country]}$Font_Suffix"
    if [[ -n ${maxmind[continentcode]} && ${maxmind[continentcode]} != "null" ]];then
      echo -ne "$Font_Green, [${maxmind[continentcode]}]${maxmind[continent]}$Font_Suffix\n"
    else
      echo -ne "\n"
    fi
  elif [[ -n ${maxmind[continentcode]} && ${maxmind[continentcode]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[continent]}$Font_Green[${maxmind[continentcode]}]${maxmind[continent]}$Font_Suffix\n"
  fi
  if [[ -n ${maxmind[regcountrycode]} && ${maxmind[regcountrycode]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[regcountry]}$Font_Green[${maxmind[regcountrycode]}]${maxmind[regcountry]}$Font_Suffix\n"
  fi
  if [[ -n ${maxmind[timezone]} && ${maxmind[timezone]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[timezone]}$Font_Green${maxmind[timezone]}$Font_Suffix\n"
  fi
  if [[ -n ${maxmind[countrycode]} && ${maxmind[countrycode]} != "null" ]];then
    if [ "${maxmind[countrycode]}" == "${maxmind[regcountrycode]}" ];then
      echo -ne "\r$Font_Cyan${sbasic[type]}$Back_Green$Font_B$Font_White${sbasic[type0]}$Font_Suffix\n"
    else
      echo -ne "\r$Font_Cyan${sbasic[type]}$Back_Red$Font_B$Font_White${sbasic[type1]}$Font_Suffix\n"
    fi
  fi
}

show_basic_lite(){
  echo -ne "\r${sbasic[title_lite]}\n"
  if [[ -n ${ipinfo[asn]} && ${ipinfo[asn]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[asn]}${Font_Green}AS${ipinfo[asn]}$Font_Suffix\n"
    echo -ne "\r$Font_Cyan${sbasic[org]}$Font_Green${ipinfo[org]}$Font_Suffix\n"
  else
    echo -ne "\r$Font_Cyan${sbasic[asn]}${sbasic[noasn]}$Font_Suffix\n"
  fi
  if [[ ${ipinfo[dms]} != "null" && ${ipinfo[map]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[location]}$Font_Green${ipinfo[dms]}$Font_Suffix\n"
    echo -ne "\r$Font_Cyan${sbasic[map]}$Font_U$Font_Green${ipinfo[map]}$Font_Suffix\n"
  fi
  local city_info=""
  [[ -n ${ipinfo[sub]} && ${ipinfo[sub]} != "null" ]]&&city_info+="${ipinfo[sub]}"
  [[ -n ${ipinfo[city]} && ${ipinfo[city]} != "null" ]]&&{ [[ -n $city_info ]]&&city_info+=", "; city_info+="${ipinfo[city]}"; }
  [[ -n ${ipinfo[post]} && ${ipinfo[post]} != "null" ]]&&{ [[ -n $city_info ]]&&city_info+=", "; city_info+="${ipinfo[post]}"; }
  [[ -n $city_info ]]&&echo -ne "\r$Font_Cyan${sbasic[city]}$Font_Green$city_info$Font_Suffix\n"
  if [[ -n ${ipinfo[countrycode]} && ${ipinfo[countrycode]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[country]}$Font_Green[${ipinfo[countrycode]}]${ipinfo[country]}$Font_Suffix"
    if [[ -n ${ipinfo[continent]} && ${ipinfo[continent]} != "null" ]];then
      echo -ne "$Font_Green, ${ipinfo[continent]}$Font_Suffix\n"
    else
      echo -ne "\n"
    fi
  elif [[ -n ${ipinfo[continent]} && ${ipinfo[continent]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[continent]}$Font_Green${ipinfo[continent]}$Font_Suffix\n"
  fi
  if [[ -n ${ipinfo[regcountrycode]} && ${ipinfo[regcountrycode]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[regcountry]}$Font_Green[${ipinfo[regcountrycode]}]${ipinfo[regcountry]}$Font_Suffix\n"
  fi
  if [[ -n ${ipinfo[timezone]} && ${ipinfo[timezone]} != "null" ]];then
    echo -ne "\r$Font_Cyan${sbasic[timezone]}$Font_Green${ipinfo[timezone]}$Font_Suffix\n"
  fi
  if [[ -n ${ipinfo[countrycode]} && ${ipinfo[countrycode]} != "null" ]];then
    if [ "${ipinfo[countrycode]}" == "${ipinfo[regcountrycode]}" ];then
      echo -ne "\r$Font_Cyan${sbasic[type]}$Back_Green$Font_B$Font_White${sbasic[type0]}$Font_Suffix\n"
    else
      echo -ne "\r$Font_Cyan${sbasic[type]}$Back_Red$Font_B$Font_White${sbasic[type1]}$Font_Suffix\n"
    fi
  fi
}

show_type(){
  echo -ne "\r${stype[title]}\n"
  echo -ne "\r$Font_Cyan${stype[db]}$Font_I   IPinfo    ipregistry    ipapi    IP2Location   AbuseIPDB $Font_Suffix\n"
  echo -ne "\r$Font_Cyan${stype[usetype]}$Font_Suffix${ipinfo[susetype]}${ipregistry[susetype]}${ipapi[susetype]}${ip2location[susetype]}${abuseipdb[susetype]}\n"
  echo -ne "\r$Font_Cyan${stype[comtype]}$Font_Suffix${ipinfo[scomtype]}${ipregistry[scomtype]}${ipapi[scomtype]}${ip2location[scomtype]}\n"
}

show_type_lite(){
  echo -ne "\r${stype[title]}\n"
  echo -ne "\r$Font_Cyan${stype[db]}$Font_I   IPinfo    ipregistry    ipapi $Font_Suffix\n"
  echo -ne "\r$Font_Cyan${stype[usetype]}$Font_Suffix${ipinfo[susetype]}${ipregistry[susetype]}${ipapi[susetype]}\n"
  echo -ne "\r$Font_Cyan${stype[comtype]}$Font_Suffix${ipinfo[scomtype]}${ipregistry[scomtype]}${ipapi[scomtype]}\n"
}

sscore_text(){
  local text="$1" p2=$2 p3=$3 p4=$4 p5=$5 p6=$6 tmplen tmp
  if ((p2>=p4));then tmplen=$((49+15*(p2-p4)/(p5-p4)-p6))
  elif ((p2>=p3));then tmplen=$((33+16*(p2-p3)/(p4-p3)-p6))
  elif ((p2>=0));then tmplen=$((17+16*p2/p3-p6))
  else tmplen=0
  fi
  tmp=$(printf '%*s' $tmplen '')
  local total_length=${#tmp} text_length=${#text}
  local tmp1="${tmp:1:total_length-text_length}$text|"
  sscore[text1]="${tmp1:1:16-p6}"
  sscore[text2]="${tmp1:17-p6:16}"
  sscore[text3]="${tmp1:33-p6:16}"
  sscore[text4]="${tmp1:49-p6}"
}

show_score(){
  echo -ne "\r${sscore[title]}\n"
  echo -ne "\r${sscore[range]}\n"
  if [[ -n ${ip2location[score]} && $mode_lite -eq 0 ]];then
    sscore_text "${ip2location[score]}" ${ip2location[score]} 33 66 99 13
    echo -ne "\r  ${Font_Cyan}IP2Location${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${ip2location[risk]}\n"
  fi
  if [[ -n ${scamalytics[score]} ]];then
    sscore_text "${scamalytics[score]}" ${scamalytics[score]} 20 60 100 13
    echo -ne "\r  ${Font_Cyan}Scamalytics${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${scamalytics[risk]}\n"
  fi
  if [[ -n ${ipapi[score]} ]];then
    local tmp_score=$(echo "${ipapi[scorenum]} * 10000 / 1"|bc)
    sscore_text "${ipapi[score]}" $tmp_score 85 300 10000 7
    echo -ne "\r  ${Font_Cyan}ipapi${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${ipapi[risk]}\n"
  fi
  if [[ $mode_lite -eq 0 ]];then
    sscore_text "${abuseipdb[score]}" ${abuseipdb[score]} 25 25 100 11
    [[ -n ${abuseipdb[score]} ]]&&echo -ne "\r  ${Font_Cyan}AbuseIPDB${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${abuseipdb[risk]}\n"
    if [ -n "${ipqs[score]}" ]&&[ "${ipqs[score]}" != "null" ];then
      sscore_text "${ipqs[score]}" ${ipqs[score]} 75 85 100 6
      echo -ne "\r  ${Font_Cyan}IPQS${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${ipqs[risk]}\n"
    fi
  fi
  sscore_text " " ${dbip[score]} 33 66 100 7
  [[ -n ${dbip[risk]} ]]&&echo -ne "\r  ${Font_Cyan}DB-IP${sscore[colon]}$Font_White$Font_B${sscore[text1]}$Back_Green${sscore[text2]}$Back_Yellow${sscore[text3]}$Back_Red${sscore[text4]}$Font_Suffix${dbip[risk]}\n"
}

format_factor(){
  local tmp_txt="  "
  for val in "$1" "$2" "$3" "$4"; do
    if [[ $val == "true" ]];then tmp_txt+="${sfactor[yes]}"
    elif [[ $val == "false" ]];then tmp_txt+="${sfactor[no]}"
    elif [ ${#val} -eq 2 ];then tmp_txt+="$Font_Green[$val]$Font_Suffix"
    else tmp_txt+="${sfactor[na]}"
    fi
    tmp_txt+="    "
  done
  if [[ $mode_lite -eq 0 ]];then
    for val in "$5" "$6" "$7" "$8"; do
      if [[ $val == "true" ]];then tmp_txt+="${sfactor[yes]}"
      elif [[ $val == "false" ]];then tmp_txt+="${sfactor[no]}"
      elif [ ${#val} -eq 2 ];then tmp_txt+="$Font_Green[$val]$Font_Suffix"
      else tmp_txt+="${sfactor[na]}"
      fi
      tmp_txt+="    "
    done
  fi
  echo "$tmp_txt"
}

show_factor(){
  local tmp_factor=""
  echo -ne "\r${sfactor[title]}\n"
  echo -ne "\r$Font_Cyan${sfactor[factor]}${Font_I}IP2Location ipapi ipregistry IPQS Scamalytics ipdata IPinfo DB-IP$Font_Suffix\n"
  tmp_factor=$(format_factor "${ip2location[countrycode]}" "${ipapi[countrycode]}" "${ipregistry[countrycode]}" "${ipqs[countrycode]}" "${scamalytics[countrycode]}" "${ipdata[countrycode]}" "${ipinfo[countrycode]}" "${dbip[countrycode]}")
  echo -ne "\r$Font_Cyan${sfactor[countrycode]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ip2location[proxy]}" "${ipapi[proxy]}" "${ipregistry[proxy]}" "${ipqs[proxy]}" "${scamalytics[proxy]}" "${ipdata[proxy]}" "${ipinfo[proxy]}" "${dbip[proxy]}")
  echo -ne "\r$Font_Cyan${sfactor[proxy]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ip2location[tor]}" "${ipapi[tor]}" "${ipregistry[tor]}" "${ipqs[tor]}" "${scamalytics[tor]}" "${ipdata[tor]}" "${ipinfo[tor]}" "${dbip[tor]}")
  echo -ne "\r$Font_Cyan${sfactor[tor]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ip2location[vpn]}" "${ipapi[vpn]}" "${ipregistry[vpn]}" "${ipqs[vpn]}" "${scamalytics[vpn]}" "${ipdata[vpn]}" "${ipinfo[vpn]}" "${dbip[vpn]}")
  echo -ne "\r$Font_Cyan${sfactor[vpn]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ip2location[server]}" "${ipapi[server]}" "${ipregistry[server]}" "${ipqs[server]}" "${scamalytics[server]}" "${ipdata[server]}" "${ipinfo[server]}" "${dbip[server]}")
  echo -ne "\r$Font_Cyan${sfactor[server]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ip2location[abuser]}" "${ipapi[abuser]}" "${ipregistry[abuser]}" "${ipqs[abuser]}" "${scamalytics[abuser]}" "${ipdata[abuser]}" "${ipinfo[abuser]}" "${dbip[abuser]}")
  echo -ne "\r$Font_Cyan${sfactor[abuser]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ip2location[robot]}" "${ipapi[robot]}" "${ipregistry[robot]}" "${ipqs[robot]}" "${scamalytics[robot]}" "${ipdata[robot]}" "${ipinfo[robot]}" "${dbip[robot]}")
  echo -ne "\r$Font_Cyan${sfactor[robot]}$Font_Suffix$tmp_factor\n"
}

show_factor_lite(){
  local tmp_factor=""
  echo -ne "\r${sfactor[title]}\n"
  echo -ne "\r$Font_Cyan${sfactor[factor]}$Font_I    ipapi ipregistry IPinfo DB-IP$Font_Suffix\n"
  tmp_factor=$(format_factor "${ipapi[countrycode]}" "${ipregistry[countrycode]}" "${ipinfo[countrycode]}" "${dbip[countrycode]}")
  echo -ne "\r$Font_Cyan${sfactor[countrycode]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ipapi[proxy]}" "${ipregistry[proxy]}" "${ipinfo[proxy]}" "${dbip[proxy]}")
  echo -ne "\r$Font_Cyan${sfactor[proxy]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ipapi[tor]}" "${ipregistry[tor]}" "${ipinfo[tor]}" "${dbip[tor]}")
  echo -ne "\r$Font_Cyan${sfactor[tor]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ipapi[vpn]}" "${ipregistry[vpn]}" "${ipinfo[vpn]}" "${dbip[vpn]}")
  echo -ne "\r$Font_Cyan${sfactor[vpn]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ipapi[server]}" "${ipregistry[server]}" "${ipinfo[server]}" "${dbip[server]}")
  echo -ne "\r$Font_Cyan${sfactor[server]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ipapi[abuser]}" "${ipregistry[abuser]}" "${ipinfo[abuser]}" "${dbip[abuser]}")
  echo -ne "\r$Font_Cyan${sfactor[abuser]}$Font_Suffix$tmp_factor\n"
  tmp_factor=$(format_factor "${ipapi[robot]}" "${ipregistry[robot]}" "${ipinfo[robot]}" "${dbip[robot]}")
  echo -ne "\r$Font_Cyan${sfactor[robot]}$Font_Suffix$tmp_factor\n"
}

show_media(){
  echo -ne "\r${smedia[title]}\n"
  echo -ne "\r$Font_Cyan${smedia[meida]}$Font_I TikTok   Disney+  Netflix Youtube  AmazonPV  Reddit   ChatGPT $Font_Suffix\n"
  echo -ne "\r$Font_Cyan${smedia[status]}${tiktok[ustatus]}${disney[ustatus]}${netflix[ustatus]}${youtube[ustatus]}${amazon[ustatus]}${reddit[ustatus]}${chatgpt[ustatus]}$Font_Suffix\n"
  echo -ne "\r$Font_Cyan${smedia[region]}$Font_Green${tiktok[uregion]}${disney[uregion]}${netflix[uregion]}${youtube[uregion]}${amazon[uregion]}${reddit[uregion]}${chatgpt[uregion]}$Font_Suffix\n"
  echo -ne "\r$Font_Cyan${smedia[type]}${tiktok[utype]}${disney[utype]}${netflix[utype]}${youtube[utype]}${amazon[utype]}${reddit[utype]}${chatgpt[utype]}$Font_Suffix\n"
}

show_mail(){
  echo -ne "\r${smail[title]}\n"
  if [ ${smail[local]} -eq 1 ];then echo -ne "\r$Font_Cyan${smail[port]}$Font_Suffix${smail[yes]}\n"
  elif [ ${smail[local]} -eq 2 ];then echo -ne "\r$Font_Cyan${smail[port]}$Font_Suffix${smail[occupied]}\n"
  else echo -ne "\r$Font_Cyan${smail[port]}$Font_Suffix${smail[no]}\n"
  fi
  if [ ${smail[remote]} -eq 1 ];then
    echo -ne "\r$Font_Cyan${smail[provider]}$Font_Suffix"
    for service in "${services[@]}";do echo -ne "${smail[$service]}"; done
    echo ""
  else
    echo -ne "\r$Font_Cyan${smail[provider]}${smail[blocked]}$Font_Suffix\n"
  fi
  [[ $1 -eq 4 ]]&&echo -ne "\r${smail[sdnsbl]}\n"
}

show_tail(){
  echo -ne "\r  $(printf '%72s'|tr ' ' '=')\n"
}

get_opts(){
  while getopts "i:l:o:x:fhjnpyEM46" opt;do
    case $opt in
      4) [[ IPV4check -ne 0 ]] && IPV6check=0 || ERRORcode=4 ;;
      6) [[ IPV6check -ne 0 ]] && IPV4check=0 || ERRORcode=6 ;;
      f) fullIP=1 ;;
      j) mode_json=1 ;;
      l) YY=$(echo "$OPTARG"|tr '[:upper:]' '[:lower:]') ;;
      E) YY="en" ;;
      \?) ERRORcode=1
    esac
  done
  [[ $IPV4check -eq 1 && $IPV6check -eq 0 && $IPV4work -eq 0 ]]&&ERRORcode=40
  [[ $IPV4check -eq 0 && $IPV6check -eq 1 && $IPV6work -eq 0 ]]&&ERRORcode=60
  CurlARG="$useNIC$usePROXY"
}

clean_ansi(){
  local input="$1"
  input=$(echo "$input"|sed 's/\\033/\x1b/g' | sed 's/\x1b\[[0-9;]*m//g' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  echo -n "$input"
}

check_IP(){
  IP=$1
  ibar_step=0
  [[ $2 -eq 4 ]]&&hide_ipv4 $IP
  [[ $2 -eq 6 ]]&&hide_ipv6 $IP
  db_maxmind $2
  db_ipinfo
  [[ $mode_lite -eq 0 ]]&&db_scamalytics $2||scamalytics=()
  db_ipregistry $2
  db_ipapi $2
  [[ $mode_lite -eq 0 ]]&&db_abuseipdb $2||abuseipdb=()
  [[ $mode_lite -eq 0 ]]&&db_ip2location $2||ip2location=()
  db_dbip
  [[ $mode_lite -eq 0 ]]&&db_ipdata $2||ipdata=()
  [[ $mode_lite -eq 0 ]]&&db_ipqs $2||ipqs=()
  MediaUnlockTest_TikTok $2
  MediaUnlockTest_DisneyPlus $2
  MediaUnlockTest_Netflix $2
  MediaUnlockTest_YouTube_Premium $2
  MediaUnlockTest_PrimeVideo_Region $2
  MediaUnlockTest_Reddit $2
  OpenAITest $2
  check_mail
  [[ $2 -eq 4 ]]&&check_dnsbl "$IP" 50
  
  echo -ne "$Font_LineClear" 1>&2
  
  if [[ $mode_lite -eq 0 ]];then
    local ip_report=$(show_head; show_basic; show_type; show_score; show_factor; show_media; show_mail $2; show_tail)
  else
    local ip_report=$(show_head; show_basic_lite; show_type_lite; show_score; show_factor_lite; show_media; show_mail $2; show_tail)
  fi
  
  echo -ne "\r$ip_report\n"
  echo -ne "\r\n"
}

generate_random_user_agent
adapt_locale

# Явное объявление переменных, чтобы не зависеть от функций
rawgithub="https://github.com/xykt/IPQuality/raw/"
Media_Cookie=$(curl $CurlARG -sL --retry 3 --max-time 10 "${rawgithub}main/ref/cookies.txt")
IATA_Database="${rawgithub}main/ref/iata-icao.csv"

get_ipv4
get_ipv6
is_valid_ipv4 $IPV4
is_valid_ipv6 $IPV6
get_opts "$@"
set_language

if [[ $ERRORcode -ne 0 ]];then
  echo -ne "\r$Font_B$Font_Red${swarn[$ERRORcode]}$Font_Suffix\n"
  exit $ERRORcode
fi

[[ $IPV4work -ne 0 && $IPV4check -ne 0 ]]&&check_IP "$IPV4" 4
[[ $IPV6work -ne 0 && $IPV6check -ne 0 ]]&&check_IP "$IPV6" 6
EOF_IPQUALITY

    chmod +x /usr/local/bin/ipquality
    echo -e "\n  ${C_DIM}Инициализация проверок (может занять некоторое время)...${C_BASE}\n"
    /usr/local/bin/ipquality -E
    echo
}
