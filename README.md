
# A I O - GENTLE  UTILITY

Интерактивная TUI - утилита для быстрой и модульной настройки сервера (Remnawave / Xray), комплексной защиты сети и глубокой диагностики. 

Скрипт отличается абсолютной независимостью модулей — вы сами выбираете, что именно нужно установить на сервер в данный момент.

## ⚡️ Быстрый старт

Запустите скрипт одной командой от пользователя `root`:

```bash
bash <(curl -sL https://raw.githubusercontent.com/ckpnm/aio_gentle/main/main.sh)
```


# 🛠 Возможности

## 📦 Развертывание Remnanode

A I O - GENTLE берет на себя установку Remnanode — от Docker до SSL — и предлагает три варианта развертывания:

* **Remnanode** — только Xray, без лишних компонентов.
* **Remnanode + Caddy** — автоматическое получение SSL и проксирование через Caddy.
* **Remnanode + Nginx** — Nginx с автоматической настройкой сертификатов.

Во всех прокси-конфигурациях связь между прокси и Xray осуществляется через Unix-сокеты (`/dev/shm/nginx.sock`) в оперативной памяти вместо TCP-портов.

---

## 🛡 Безопасность

### Системные настройки

* TCP BBR.
* Отключение IPv6.
* Автоматическая смена SSH-порта.
* Настройка UFW.
* Fail2Ban.

### Сетевые фильтры

**Traffic Guard**

Блокировка IP-адресов известных сканеров и нежелательных сетей.

**AS Block**

Блокировка зараженных БОТНЕТ подсетей Leaseweb и Hurricane Electric через `ipset` + `iptables` с автоматическим еженедельным обновлением.

**URL Block**

Блокировка по пользовательским спискам через `nftables` и `systemd`.

---

## 📊 Диагностика

Утилита включает встроенный набор инструментов для проверки сервера.

### CensorCheck

Проверка доступности популярных сервисов и выявление признаков DPI или DNS-подмены.

### IP Quality

Комплексная проверка IP-адреса:

- репутация;
- AbuseIPDB;
- Scamalytics;
- IP2Location;
- DB-IP;
- доступность Netflix, Disney+, TikTok;
- SMTP/DNSBL.

### Speedtest

Поддерживаются:

- Ookla Speedtest;
- iPerf3 с готовым списком российских серверов.

### Reality

Просмотр X25519-ключей и параметров Reality непосредственно из контейнера.

---

## 📁 Структура

```
main.sh      — загрузчик и интерфейс
modules/     — функциональные модули
src/         — шаблоны конфигураций
```

---

## 🙏 Благодарности

Проект основан на идеях и решениях сообщества.

Спасибо:

- **[eGamesAPI](https://github.com/eGamesAPI)** — идеи установочных скриптов и шаблонов.
- **[Zover1337](https://github.com/Zover1337)** — автоматизация Fail2Ban.
- **[Loorrr293](https://github.com/Loorrr293)** — актуальные блок-листы.
- **[distillium](https://github.com/distillium)** — WARP Native и Watchdog.
- **[Davoyan](https://github.com/Davoyan)** — CensorCheck.
- **[vernette](https://github.com/vernette)** — IP Region Check.
- **[xykt](https://github.com/xykt)** — IP Quality.
- **[itdoginfo](https://github.com/itdoginfo)** — публичный список iPerf3-серверов.

