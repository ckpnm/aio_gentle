#!/bin/bash
# Файл: modules/base.sh

step_base_deps() {
    draw_sub_header "Базовая подготовка"
    _do_base_deps() {
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y curl ufw logrotate sudo git dnsutils unzip psmisc certbot
    }
    run_task "Обновление кэша пакетов и установка зависимостей" "_do_base_deps"
}

step_swap() {
    draw_sub_header "Создание Swap (Подкачка)"
    read -p "Укажите размер Swap в ГБ (по умолчанию 2): " SWAP_SIZE
    SWAP_SIZE=${SWAP_SIZE:-2}

    _do_swap() {
        if [ -f /swapfile ]; then
            swapoff /swapfile || true
            rm -f /swapfile
        fi
        fallocate -l ${SWAP_SIZE}G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        if ! grep -q '/swapfile' /etc/fstab; then
            echo '/swapfile none swap sw 0 0' >> /etc/fstab
        fi
    }
    run_task "Настройка файла подкачки на ${SWAP_SIZE}GB" "_do_swap"
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
