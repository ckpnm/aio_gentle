#!/bin/bash

step_warp_setup() {
    draw_sub_header "Cloudflare WARP"
    _do_warp() {
        bash <(curl -fsSL https://raw.githubusercontent.com/distillium/warp-native/main/install.sh)
    }
    run_task "Установка native-клиента WARP" "_do_warp"
}

step_info() {
    draw_sub_header "Информация и Благодарности"
    echo -e "  ${C_WHITE}Огромная благодарность авторам открытых скриптов и списков,${C_BASE}"
    echo -e "  ${C_WHITE}которые были использованы или адаптированы в этой утилите:${C_BASE}\n"
    
    echo -e "  ${C_ACCENT}● Zover1337${C_BASE} — ${C_DIM}https://github.com/Zover1337${C_BASE}"
    echo -e "  ${C_ACCENT}● jaywehosl${C_BASE} — ${C_DIM}https://github.com/jaywehosl${C_BASE}"
    echo -e "  ${C_ACCENT}● Loorrr293${C_BASE} — ${C_DIM}https://github.com/Loorrr293${C_BASE}"
    echo -e "  ${C_ACCENT}● eGamesAPI${C_BASE} — ${C_DIM}https://github.com/eGamesAPI${C_BASE}\n"
    
    echo -e "  ${C_WHITE}Также спасибо всем мейнтейнерам Xray, Remnawave и других проектов.${C_BASE}"
}
