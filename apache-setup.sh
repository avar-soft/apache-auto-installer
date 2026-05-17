#!/bin/bash
# ══════════════════════════════════════════════════════════════════
#   APACHE AUTO-INSTALLER  ·  Ubuntu 20.04 / 22.04 / 24.04
#   Запуск: sudo bash apache-setup.sh
# ══════════════════════════════════════════════════════════════════

[[ $EUID -ne 0 ]] && { echo "Запустите через sudo"; exit 1; }

# Цвета
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m'
B='\033[0;34m' C='\033[0;36m' M='\033[0;35m'
W='\033[1;37m' D='\033[2m'    N='\033[0m' BOLD='\033[1m'

LOG="/var/log/apache-setup-$(date +%Y%m%d_%H%M%S).log"
touch "$LOG"

log()  { echo -e "$*" | tee -a "$LOG"; }
ok()   { log "  ${G}✔${N}  $*"; }
err()  { log "  ${R}✘${N}  $*"; }
inf()  { log "  ${B}·${N}  $*"; }
wrn()  { log "  ${Y}!${N}  $*"; }
run()  { bash -c "$1" >> "$LOG" 2>&1; }

# ── TTY ──────────────────────────────────────────────────────────
_tty_read() {
    if [[ -c /dev/tty ]]; then
        IFS= read -r "$1" </dev/tty
    else
        IFS= read -r "$1"
    fi
}

yn() {
    local msg="$1" def="${2:-n}" ans
    if [[ "$def" == "y" ]]; then
        printf "  \033[0;36m?\033[0m  %s \033[2m[\033[0m\033[1;37mY\033[0m\033[2m/n]\033[0m: " "$msg" >&2
    else
        printf "  \033[0;36m?\033[0m  %s \033[2m[y/\033[0m\033[1;37mN\033[0m\033[2m]\033[0m: " "$msg" >&2
    fi
    _tty_read ans
    ans="${ans:-$def}"
    [[ "$ans" =~ ^[Yy]$ ]]
}

ask() {
    local msg="$1" def="$2" val
    if [[ -n "$def" ]]; then
        printf "  \033[0;36m?\033[0m  %s \033[2m[\033[0m\033[1;37m%s\033[0m\033[2m]\033[0m: " "$msg" "$def" >&2
    else
        printf "  \033[0;36m?\033[0m  %s: " "$msg" >&2
    fi
    _tty_read val
    echo "${val:-$def}"
}

menu() {
    local prompt="$1"; shift
    local opts=("$@") choice
    printf "  \033[0;36m?\033[0m  %s\n" "$prompt" >&2
    for i in "${!opts[@]}"; do
        printf "      \033[2m%d)\033[0m %s\n" $((i+1)) "${opts[$i]}" >&2
    done
    printf "      \033[1;37mВыбор [1]\033[0m: " >&2
    _tty_read choice
    choice="${choice:-1}"
    [[ "$choice" =~ ^[0-9]+$ ]] || choice=1
    [[ $choice -lt 1 || $choice -gt ${#opts[@]} ]] && choice=1
    echo "${opts[$((choice-1))]}"
}

spin() {
    local msg="$1" pid="${2:-$!}" i=0 code
    local s=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  \033[0;36m%s\033[0m  %-50s" "${s[$((i % 10))]}" "$msg" >&2
        ((i++)); sleep 0.1
    done
    wait "$pid"; code=$?
    if [[ $code -eq 0 ]]; then
        printf "\r  \033[0;32m✔\033[0m  %-50s\n" "$msg" >&2
    else
        printf "\r  \033[0;31m✘\033[0m  %-50s  (см. лог)\n" "$msg" >&2
    fi
    echo "  [$(date +%T)] $msg — код: $code" >> "$LOG"
    return $code
}

apt_install() {
    local msg="$1"; shift
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        -o Dpkg::Options::="--force-confdef" \
        -o Dpkg::Options::="--force-confold" "$@" >> "$LOG" 2>&1 &
    spin "$msg"
}

apt_update() {
    DEBIAN_FRONTEND=noninteractive apt-get update -qq >> "$LOG" 2>&1 &
    spin "${1:-Обновление списка пакетов}"
}

section() {
    echo ""
    printf "\033[0;35m\033[1m  ──────────────────────────────────────────\033[0m\n"
    printf "\033[0;35m\033[1m  %s\033[0m\n" "$1"
    printf "\033[0;35m\033[1m  ──────────────────────────────────────────\033[0m\n"
    echo ""
}

# ══════════════════════════════════════════════════════════════════
#  ОПРЕДЕЛЕНИЕ ОС
# ══════════════════════════════════════════════════════════════════
. /etc/os-release 2>/dev/null
UBUNTU_CODENAME="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null)}"
UBUNTU_VER="${VERSION_ID:-$(lsb_release -rs 2>/dev/null)}"
UBUNTU_MAJOR="${UBUNTU_VER%%.*}"
OS_NAME="${PRETTY_NAME:-Ubuntu ${UBUNTU_VER}}"

# Доступные версии PHP в ondrej/php PPA (актуально на 2025)
case "$UBUNTU_CODENAME" in
    focal)    PHP_AVAIL=("8.4" "8.3" "8.2" "8.1" "8.0" "7.4") ;;   # 20.04
    jammy)    PHP_AVAIL=("8.4" "8.3" "8.2" "8.1" "8.0" "7.4") ;;   # 22.04
    noble)    PHP_AVAIL=("8.4" "8.3" "8.2" "8.1") ;;               # 24.04
    *)        PHP_AVAIL=("8.3" "8.2" "8.1") ;;
esac

clear
printf "\033[0;36m\033[1m"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║        APACHE AUTO-INSTALLER  ·  Ubuntu               ║"
echo "  ║        Автоматическая установка и настройка           ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
printf "\033[0m\n"

IP_LOC=$(hostname -I | awk '{print $1}')
inf "ОС: ${W}${OS_NAME}${N} (${UBUNTU_CODENAME})   IP: ${W}${IP_LOC}${N}"
inf "Лог: ${D}${LOG}${N}"
echo ""

# ══════════════════════════════════════════════════════════════════
#  ШАГ 1 — ДОМЕН
# ══════════════════════════════════════════════════════════════════
section "1 · ДОМЕН И ДИРЕКТОРИЯ"

DOMAIN=$(ask "Домен сайта (без www)" "example.com")
ADMIN_EMAIL=$(ask "Email администратора" "info@${DOMAIN}")
DOC_ROOT=$(ask "Путь к папке сайта" "/var/www/${DOMAIN}/public_html")

yn "Добавить www.${DOMAIN} как алиас?"             "y" && HAS_WWW=true    || HAS_WWW=false
yn "Удалить дефолтный сайт (000-default)?"         "y" && RM_DEFAULT=true || RM_DEFAULT=false

# ══════════════════════════════════════════════════════════════════
#  ШАГ 2 — PHP
# ══════════════════════════════════════════════════════════════════
section "2 · PHP"

INSTALL_PHP=false
USE_PHP_PPA=false
if yn "Установить PHP?" "y"; then
    INSTALL_PHP=true
    PHP_VER=$(menu "Версия PHP (доступно для ${UBUNTU_CODENAME}):" "${PHP_AVAIL[@]}")
    PHP_PRESET=$(menu "Набор расширений:" \
        "Минимальный  (cli, mysql, curl, mbstring, xml, zip)" \
        "Стандартный  (+ gd, intl, bcmath, opcache, redis)" \
        "Максимальный (+ imagick, soap, ldap, xsl, dev)")

    # Версии из системного репо: 20.04→7.4, 22.04→8.1, 24.04→8.3
    case "$UBUNTU_CODENAME" in
        focal) SYS_PHP="7.4" ;;
        jammy) SYS_PHP="8.1" ;;
        noble) SYS_PHP="8.3" ;;
        *)     SYS_PHP="" ;;
    esac
    [[ "$PHP_VER" != "$SYS_PHP" ]] && USE_PHP_PPA=true
    if [[ "$USE_PHP_PPA" == true ]]; then
        inf "PHP ${W}${PHP_VER}${N} требует PPA ${W}ondrej/php${N} — будет добавлен"
    else
        inf "PHP ${W}${PHP_VER}${N} есть в системном репо — PPA не нужен"
    fi
fi

# ══════════════════════════════════════════════════════════════════
#  ШАГ 3 — БАЗА ДАННЫХ
# ══════════════════════════════════════════════════════════════════
section "3 · БАЗА ДАННЫХ"

INSTALL_DB=false
USE_DB_REPO=false
if yn "Установить базу данных?" "n"; then
    INSTALL_DB=true
    DB_ENGINE=$(menu "СУБД:" "MariaDB" "MySQL" "PostgreSQL")

    case "$DB_ENGINE" in
        MariaDB)
            DB_VER=$(menu "Версия MariaDB:" \
                "11.4 (LTS, последняя)" \
                "10.11 (LTS)" \
                "10.6 (LTS)" \
                "из системного репо")
            ;;
        MySQL)
            DB_VER=$(menu "Версия MySQL:" \
                "8.4 (LTS)" \
                "8.0" \
                "из системного репо")
            ;;
        PostgreSQL)
            DB_VER=$(menu "Версия PostgreSQL:" \
                "17 (последняя)" \
                "16" \
                "15" \
                "14" \
                "из системного репо")
            ;;
    esac

    [[ "$DB_VER" != *системного* ]] && USE_DB_REPO=true

    DB_NAME=$(ask "Имя базы данных" "${DOMAIN//[.-]/_}")
    DB_USER=$(ask "Пользователь БД" "${DOMAIN%%.*}")
    DB_PASS=$(openssl rand -base64 14 2>/dev/null | tr -d '/+=' || tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16)
    [[ -z "$DB_PASS" ]] && DB_PASS=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)
    inf "Пароль БД сгенерирован: ${W}${DB_PASS}${N}"
    [[ "$USE_DB_REPO" == true ]] && inf "Будет добавлен официальный репо для ${W}${DB_ENGINE} ${DB_VER%% *}${N}"
fi

# ══════════════════════════════════════════════════════════════════
#  ШАГ 4 — SSL
# ══════════════════════════════════════════════════════════════════
section "4 · SSL / HTTPS"

if yn "Получить SSL-сертификат Let's Encrypt?" "y"; then
    INSTALL_SSL=true
    yn "Редиректить HTTP → HTTPS?"                  "y" && FORCE_HTTPS=true || FORCE_HTTPS=false
    yn "Включить HSTS?"                             "y" && USE_HSTS=true    || USE_HSTS=false
    SSL_EMAIL=$(ask "Email для Let's Encrypt" "$ADMIN_EMAIL")
    yn "Автообновление cron каждые 25 дней?"        "y" && SSL_CRON=true    || SSL_CRON=false
else
    INSTALL_SSL=false
    FORCE_HTTPS=false
    USE_HSTS=false
    SSL_CRON=false
fi

# ══════════════════════════════════════════════════════════════════
#  ШАГ 5 — БЕЗОПАСНОСТЬ
# ══════════════════════════════════════════════════════════════════
section "5 · БЕЗОПАСНОСТЬ"

yn "Скрыть версию Apache из заголовков?"           "y" && HIDE_VER=true    || HIDE_VER=false
yn "Запретить листинг директорий?"                 "y" && NO_LIST=true     || NO_LIST=false
yn "Security-заголовки (XSS / CSRF / CSP)?"        "y" && SEC_HDR=true     || SEC_HDR=false
yn "Блокировать .git, .env, .htaccess снаружи?"    "y" && BLOCK_HID=true   || BLOCK_HID=false
yn "mod_evasive — защита от DoS-атак?"             "n" && MOD_EVASIVE=true || MOD_EVASIVE=false
yn "mod_security — WAF?"                           "n" && MOD_SEC=true     || MOD_SEC=false

# ══════════════════════════════════════════════════════════════════
#  ШАГ 6 — ПРОИЗВОДИТЕЛЬНОСТЬ
# ══════════════════════════════════════════════════════════════════
section "6 · ПРОИЗВОДИТЕЛЬНОСТЬ"

yn "Gzip-сжатие (mod_deflate)?"                    "y" && USE_GZIP=true  || USE_GZIP=false
yn "Кеш браузера (mod_expires)?"                   "y" && USE_CACHE=true || USE_CACHE=false
yn "HTTP/2?"                                       "y" && USE_H2=true    || USE_H2=false
if yn "Изменить MPM?" "n"; then
    MPM=$(menu "MPM:" "event (рекомендуется)" "prefork (для mod_php)" "worker")
    SET_MPM=true
else
    SET_MPM=false
fi

# ══════════════════════════════════════════════════════════════════
#  ШАГ 7 — КОНТЕНТ И ЛОГИ
# ══════════════════════════════════════════════════════════════════
section "7 · КОНТЕНТ И ЛОГИ"

yn "Создать index.html заглушку?"                   "y" && MK_INDEX=true    || MK_INDEX=false
yn "Создать robots.txt?"                            "y" && MK_ROBOTS=true   || MK_ROBOTS=false
ROBOTS_CLOSE=false
if [[ "$MK_ROBOTS" == true ]]; then
    yn "Закрыть от индексации (сайт в разработке)?" "n" && ROBOTS_CLOSE=true || ROBOTS_CLOSE=false
fi
yn "Создать .htaccess с базовыми правилами?"        "y" && MK_HTACCESS=true || MK_HTACCESS=false
yn "Страницы ошибок 403 / 404 / 500?"               "y" && MK_ERRORS=true   || MK_ERRORS=false
yn "Ротация логов?"                                 "y" && LOG_ROT=true     || LOG_ROT=false
LOG_DAYS=14
if [[ "$LOG_ROT" == true ]]; then
    LOG_DAYS=$(ask "Хранить логи (дней)" "14")
fi
yn "Расширенный формат логов (+ время ответа)?"    "n" && EXT_LOG=true     || EXT_LOG=false

# ══════════════════════════════════════════════════════════════════
#  ШАГ 8 — FIREWALL
# ══════════════════════════════════════════════════════════════════
section "8 · FIREWALL (UFW)"

UFW_ST=$(ufw status 2>/dev/null | head -1)
inf "Текущий статус UFW: ${W}${UFW_ST:-не установлен}${N}"

if yn "Настроить UFW?" "y"; then
    SET_UFW=true
    yn "Разрешить SSH (порт 22)?" "y" && UFW_SSH=true || UFW_SSH=false
else
    SET_UFW=false
    UFW_SSH=false
fi

# ══════════════════════════════════════════════════════════════════
#  СВОДКА
# ══════════════════════════════════════════════════════════════════
echo ""
printf "\033[0;36m\033[1m  ══════════════════════════════════════════════════════\033[0m\n"
printf "\033[0;36m\033[1m  ИТОГОВАЯ КОНФИГУРАЦИЯ\033[0m\n"
printf "\033[0;36m\033[1m  ══════════════════════════════════════════════════════\033[0m\n"
echo ""

_b() { [[ "$1" == true ]] && printf "\033[0;32mДа\033[0m" || printf "\033[2mНет\033[0m"; }

printf "  \033[2m%-24s\033[0m \033[1;37m%s\033[0m\n"  "Домен:"           "$DOMAIN"
printf "  \033[2m%-24s\033[0m %s\n"                   "www-алиас:"       "$(_b $HAS_WWW)"
printf "  \033[2m%-24s\033[0m \033[1;37m%s\033[0m\n"  "Email:"           "$ADMIN_EMAIL"
printf "  \033[2m%-24s\033[0m \033[1;37m%s\033[0m\n"  "DocumentRoot:"    "$DOC_ROOT"
if [[ "$INSTALL_PHP" == true ]]; then
    printf "  \033[2m%-24s\033[0m \033[0;32m%s\033[0m %s\n" "PHP:" "$PHP_VER" "$([[ $USE_PHP_PPA == true ]] && echo '(ondrej PPA)' || echo '(системный репо)')"
else
    printf "  \033[2m%-24s\033[0m \033[2mНет\033[0m\n"   "PHP:"
fi
if [[ "$INSTALL_DB" == true ]]; then
    printf "  \033[2m%-24s\033[0m \033[0;32m%s\033[0m %s\n" "База данных:" "$DB_ENGINE" "$DB_VER"
else
    printf "  \033[2m%-24s\033[0m \033[2mНет\033[0m\n"   "База данных:"
fi
printf "  \033[2m%-24s\033[0m %s\n"  "SSL:"             "$(_b $INSTALL_SSL)"
printf "  \033[2m%-24s\033[0m %s\n"  "HTTPS редирект:"  "$(_b $FORCE_HTTPS)"
printf "  \033[2m%-24s\033[0m %s\n"  "HSTS:"            "$(_b $USE_HSTS)"
printf "  \033[2m%-24s\033[0m %s\n"  "Cron SSL:"        "$(_b $SSL_CRON)"
printf "  \033[2m%-24s\033[0m %s\n"  "Gzip:"            "$(_b $USE_GZIP)"
printf "  \033[2m%-24s\033[0m %s\n"  "Кеш браузера:"    "$(_b $USE_CACHE)"
printf "  \033[2m%-24s\033[0m %s\n"  "HTTP/2:"          "$(_b $USE_H2)"
printf "  \033[2m%-24s\033[0m %s\n"  "Security Headers:" "$(_b $SEC_HDR)"
printf "  \033[2m%-24s\033[0m %s\n"  "mod_evasive:"     "$(_b $MOD_EVASIVE)"
printf "  \033[2m%-24s\033[0m %s\n"  "mod_security:"    "$(_b $MOD_SEC)"
printf "  \033[2m%-24s\033[0m %s\n"  "UFW:"             "$(_b $SET_UFW)"
printf "  \033[2m%-24s\033[0m %s\n"  "Удалить default:" "$(_b $RM_DEFAULT)"
echo ""

yn "Начать установку?" "y" || { wrn "Отменено."; exit 0; }

# ══════════════════════════════════════════════════════════════════
#  УСТАНОВКА
# ══════════════════════════════════════════════════════════════════
section "УСТАНОВКА"

# ── Снимаем автообновления (сервисы + ТАЙМЕРЫ) ──────────────────
inf "Останавливаем автообновления apt..."
systemctl stop unattended-upgrades.service \
               apt-daily.service apt-daily-upgrade.service \
               apt-daily.timer   apt-daily-upgrade.timer 2>/dev/null || true
systemctl mask apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

_unmask_timers() {
    systemctl unmask apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
    systemctl start  apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
}
trap _unmask_timers EXIT

# ── Ждём освобождения dpkg lock ─────────────────────────────────
_lock_wait=0
while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock /var/lib/dpkg/lock >/dev/null 2>&1; do
    _lock_wait=$(( _lock_wait + 1 ))
    (( _lock_wait > 120 )) && { err "dpkg lock не освобождается. Перезагрузите сервер."; exit 1; }
    sleep 1
done

# ── Базовые утилиты (нужны для добавления репозиториев) ─────────
apt_update "Обновление списка пакетов"
apt_install "Базовые утилиты" \
    ca-certificates curl wget gnupg lsb-release \
    apt-transport-https software-properties-common openssl

# ══════════════════════════════════════════════════════════════════
#  РЕПОЗИТОРИИ
# ══════════════════════════════════════════════════════════════════

# ── PHP: ondrej PPA ──────────────────────────────────────────────
if [[ "$INSTALL_PHP" == true && "$USE_PHP_PPA" == true ]]; then
    LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php >> "$LOG" 2>&1 &
    spin "Добавление PPA ondrej/php"
    apt_update "Обновление списка пакетов (PHP)"
fi

# ── БД: официальные репозитории ──────────────────────────────────
if [[ "$INSTALL_DB" == true && "$USE_DB_REPO" == true ]]; then
    case "$DB_ENGINE" in
        MariaDB)
            MARIADB_VER="${DB_VER%% *}"   # "11.4" из "11.4 (LTS, последняя)"
            (
                install -d /etc/apt/keyrings
                curl -fsSL https://mariadb.org/mariadb_release_signing_key.pgp \
                    -o /etc/apt/keyrings/mariadb-keyring.pgp
                cat > /etc/apt/sources.list.d/mariadb.sources <<EOF
X-Repolib-Name: MariaDB
Types: deb
URIs: https://mirror.mariadb.org/repo/${MARIADB_VER}/ubuntu
Suites: ${UBUNTU_CODENAME}
Components: main main/debug
Signed-By: /etc/apt/keyrings/mariadb-keyring.pgp
EOF
            ) >> "$LOG" 2>&1 &
            spin "Добавление репо MariaDB ${MARIADB_VER}"
            apt_update "Обновление списка пакетов (MariaDB)"
            ;;
        MySQL)
            MYSQL_VER="${DB_VER%% *}"   # "8.4" / "8.0"
            (
                install -d /etc/apt/keyrings
                # Ключ MySQL APT (актуальный 2023+)
                curl -fsSL https://repo.mysql.com/RPM-GPG-KEY-mysql-2023 \
                    | gpg --dearmor -o /etc/apt/keyrings/mysql.gpg
                # Канал: mysql-8.0 / mysql-8.4-lts
                MYSQL_CHAN="mysql-${MYSQL_VER}"
                [[ "$MYSQL_VER" == "8.4" ]] && MYSQL_CHAN="mysql-8.4-lts"
                cat > /etc/apt/sources.list.d/mysql.list <<EOF
deb [signed-by=/etc/apt/keyrings/mysql.gpg] http://repo.mysql.com/apt/ubuntu/ ${UBUNTU_CODENAME} ${MYSQL_CHAN}
deb [signed-by=/etc/apt/keyrings/mysql.gpg] http://repo.mysql.com/apt/ubuntu/ ${UBUNTU_CODENAME} mysql-tools
EOF
            ) >> "$LOG" 2>&1 &
            spin "Добавление репо MySQL ${MYSQL_VER}"
            apt_update "Обновление списка пакетов (MySQL)"
            ;;
        PostgreSQL)
            PG_VER="${DB_VER%% *}"   # "17" / "16" / ...
            (
                install -d /etc/apt/keyrings
                curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
                    | gpg --dearmor -o /etc/apt/keyrings/postgresql.gpg
                cat > /etc/apt/sources.list.d/pgdg.list <<EOF
deb [signed-by=/etc/apt/keyrings/postgresql.gpg] https://apt.postgresql.org/pub/repos/apt ${UBUNTU_CODENAME}-pgdg main
EOF
            ) >> "$LOG" 2>&1 &
            spin "Добавление репо PostgreSQL ${PG_VER}"
            apt_update "Обновление списка пакетов (PostgreSQL)"
            ;;
    esac
fi

# ══════════════════════════════════════════════════════════════════
#  УСТАНОВКА ПАКЕТОВ
# ══════════════════════════════════════════════════════════════════

PKGS="apache2"
[[ "$MOD_EVASIVE" == true ]] && PKGS="$PKGS libapache2-mod-evasive"
[[ "$MOD_SEC"     == true ]] && PKGS="$PKGS libapache2-mod-security2"

if [[ "$INSTALL_DB" == true ]]; then
    case "$DB_ENGINE" in
        MariaDB)
            PKGS="$PKGS mariadb-server mariadb-client"
            ;;
        MySQL)
            PKGS="$PKGS mysql-server mysql-client"
            ;;
        PostgreSQL)
            if [[ "$USE_DB_REPO" == true ]]; then
                PKGS="$PKGS postgresql-${PG_VER} postgresql-contrib-${PG_VER}"
            else
                PKGS="$PKGS postgresql postgresql-contrib"
            fi
            ;;
    esac
fi

# Преднастройка MySQL — отключаем интерактивный запрос пароля
if [[ "$INSTALL_DB" == true && "$DB_ENGINE" == "MySQL" ]]; then
    echo "mysql-community-server mysql-community-server/root-pass password ${DB_PASS}" | debconf-set-selections
    echo "mysql-community-server mysql-community-server/re-root-pass password ${DB_PASS}" | debconf-set-selections
    echo "mysql-community-server mysql-community-server/default-auth-override select Use Strong Password Encryption (RECOMMENDED)" | debconf-set-selections
fi

# shellcheck disable=SC2086
apt_install "Установка: Apache + модули + БД" $PKGS
run "systemctl enable apache2"
ok "Apache2 установлен и включён"

# ── PHP ──────────────────────────────────────────────────────────
if [[ "$INSTALL_PHP" == true ]]; then
    PHP_PKGS="php${PHP_VER} php${PHP_VER}-cli php${PHP_VER}-common"
    PHP_PKGS="$PHP_PKGS php${PHP_VER}-mysql php${PHP_VER}-curl"
    PHP_PKGS="$PHP_PKGS php${PHP_VER}-mbstring php${PHP_VER}-xml php${PHP_VER}-zip"
    PHP_PKGS="$PHP_PKGS libapache2-mod-php${PHP_VER}"
    [[ "$PHP_PRESET" == *тандарт* || "$PHP_PRESET" == *аксим* ]] && \
        PHP_PKGS="$PHP_PKGS php${PHP_VER}-gd php${PHP_VER}-intl php${PHP_VER}-bcmath php${PHP_VER}-opcache php${PHP_VER}-redis"
    [[ "$PHP_PRESET" == *аксим* ]] && \
        PHP_PKGS="$PHP_PKGS php${PHP_VER}-imagick php${PHP_VER}-soap php${PHP_VER}-ldap php${PHP_VER}-xsl php${PHP_VER}-dev"

    # shellcheck disable=SC2086
    apt_install "Установка PHP ${PHP_VER}" $PHP_PKGS
fi

# ── Модули Apache ────────────────────────────────────────────────
MODS="rewrite ssl headers"
[[ "$USE_GZIP"  == true ]] && MODS="$MODS deflate"
[[ "$USE_CACHE" == true ]] && MODS="$MODS expires"
[[ "$USE_H2"    == true ]] && MODS="$MODS http2"
# shellcheck disable=SC2086
run "a2enmod $MODS"
ok "Модули включены: $MODS"

# ── mod_evasive ──────────────────────────────────────────────────
if [[ "$MOD_EVASIVE" == true ]]; then
    run "a2enmod evasive || a2enmod mod-evasive"
    mkdir -p /var/log/apache2/evasive
    chown www-data:www-data /var/log/apache2/evasive
    cat > /etc/apache2/mods-available/evasive.conf << 'EOF'
<IfModule mod_evasive20.c>
    DOSHashTableSize  3097
    DOSPageCount      5
    DOSSiteCount      50
    DOSPageInterval   1
    DOSSiteInterval   1
    DOSBlockingPeriod 10
    DOSLogDir         /var/log/apache2/evasive
</IfModule>
EOF
    ok "mod_evasive настроен"
fi

# ── mod_security ─────────────────────────────────────────────────
if [[ "$MOD_SEC" == true ]]; then
    run "a2enmod security2"
    for _msec_f in /etc/modsecurity/modsecurity.conf-recommended \
                   /usr/share/modsecurity-crs/modsecurity.conf-recommended; do
        if [[ -f "$_msec_f" ]]; then
            cp "$_msec_f" /etc/modsecurity/modsecurity.conf
            sed -i 's/SecRuleEngine DetectionOnly/SecRuleEngine On/' /etc/modsecurity/modsecurity.conf
            ok "mod_security настроен (SecRuleEngine On)"
            break
        fi
    done
fi

# ── База данных: запуск и создание ───────────────────────────────
if [[ "$INSTALL_DB" == true ]]; then
    case "$DB_ENGINE" in
        MariaDB)    SVC="mariadb" ;;
        MySQL)      SVC="mysql" ;;
        PostgreSQL) SVC="postgresql" ;;
    esac
    run "systemctl enable $SVC && systemctl start $SVC"
    sleep 2
    ok "${DB_ENGINE} запущен"

    if [[ "$DB_ENGINE" == "MariaDB" || "$DB_ENGINE" == "MySQL" ]]; then
        # MariaDB: root через unix_socket без пароля
        # MySQL 8: сначала пробуем socket, при неудаче — пароль
        if [[ "$DB_ENGINE" == "MariaDB" ]]; then
            MYSQL_CMD="mysql"
        else
            if mysql -e "SELECT 1;" >/dev/null 2>&1; then
                MYSQL_CMD="mysql"
            else
                MYSQL_CMD="mysql -u root -p${DB_PASS}"
            fi
        fi

        $MYSQL_CMD -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" >> "$LOG" 2>&1
        $MYSQL_CMD -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';" >> "$LOG" 2>&1
        $MYSQL_CMD -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';" >> "$LOG" 2>&1
        $MYSQL_CMD -e "FLUSH PRIVILEGES;" >> "$LOG" 2>&1
        ok "БД '${DB_NAME}' и пользователь '${DB_USER}' созданы"
        printf "DB_ENGINE=%s\nDB_VER=%s\nDB_NAME=%s\nDB_USER=%s\nDB_PASS=%s\n" \
            "$DB_ENGINE" "$DB_VER" "$DB_NAME" "$DB_USER" "$DB_PASS" > "/root/.db_${DOMAIN}"
        chmod 600 "/root/.db_${DOMAIN}"
    elif [[ "$DB_ENGINE" == "PostgreSQL" ]]; then
        sudo -u postgres psql -c "CREATE DATABASE ${DB_NAME};" >> "$LOG" 2>&1
        sudo -u postgres psql -c "CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASS}';" >> "$LOG" 2>&1
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" >> "$LOG" 2>&1
        sudo -u postgres psql -d "${DB_NAME}" -c "GRANT ALL ON SCHEMA public TO ${DB_USER};" >> "$LOG" 2>&1
        ok "PostgreSQL: БД '${DB_NAME}' и пользователь '${DB_USER}' созданы"
        printf "DB_ENGINE=%s\nDB_VER=%s\nDB_NAME=%s\nDB_USER=%s\nDB_PASS=%s\n" \
            "$DB_ENGINE" "$DB_VER" "$DB_NAME" "$DB_USER" "$DB_PASS" > "/root/.db_${DOMAIN}"
        chmod 600 "/root/.db_${DOMAIN}"
    fi
fi

# ── Директория сайта ─────────────────────────────────────────────
mkdir -p "${DOC_ROOT}"
_site_root="$(dirname "${DOC_ROOT%/}")"
[[ "$_site_root" == "/var/www" || "$_site_root" == "/" ]] && _site_root="${DOC_ROOT}"
chown -R www-data:www-data "$_site_root"
chmod -R 755 "$_site_root"
ok "Директория ${DOC_ROOT} создана"

# ── Скрытие версии ──────────────────────────────────────────────
if [[ "$HIDE_VER" == true ]]; then
    cat > /etc/apache2/conf-available/hide-version.conf << 'EOF'
ServerTokens Prod
ServerSignature Off
TraceEnable Off
EOF
    run "a2enconf hide-version"
fi

# ── Security-заголовки ──────────────────────────────────────────
if [[ "$SEC_HDR" == true ]]; then
    cat > /etc/apache2/conf-available/sec-headers.conf << 'EOF'
<IfModule mod_headers.c>
    Header always set X-Content-Type-Options  "nosniff"
    Header always set X-Frame-Options         "SAMEORIGIN"
    Header always set X-XSS-Protection        "1; mode=block"
    Header always set Referrer-Policy         "strict-origin-when-cross-origin"
    Header always set Permissions-Policy      "geolocation=(), microphone=(), camera=()"
    Header always unset X-Powered-By
</IfModule>
EOF
    run "a2enconf sec-headers"
fi

# ── Лог-формат ──────────────────────────────────────────────────
LOG_FMT="combined"
if [[ "$EXT_LOG" == true ]]; then
    cat > /etc/apache2/conf-available/extended-log.conf << 'EOF'
LogFormat "%h %l %u %t \"%r\" %>s %b \"%{Referer}i\" \"%{User-Agent}i\" %D" extended
EOF
    run "a2enconf extended-log"
    LOG_FMT="extended"
fi

# ── VirtualHost ─────────────────────────────────────────────────
VHOST="/etc/apache2/sites-available/${DOMAIN}.conf"

ALIAS_LINE=""
[[ "$HAS_WWW" == true ]] && ALIAS_LINE="    ServerAlias www.${DOMAIN}"
HTTP2_LINE=""
[[ "$USE_H2" == true ]] && HTTP2_LINE="    Protocols h2 http/1.1"
DIR_OPTS="+FollowSymLinks"
[[ "$NO_LIST" == true ]] && DIR_OPTS="-Indexes +FollowSymLinks"

if [[ "$BLOCK_HID" == true ]]; then
    BLOCK_BLOCK='
    <FilesMatch "\.(htaccess|htpasswd|env|git|svn|DS_Store|bak|sql|sh)$">
        Require all denied
    </FilesMatch>
    <DirectoryMatch "/\.(git|svn)">
        Require all denied
    </DirectoryMatch>'
else
    BLOCK_BLOCK=""
fi

if [[ "$USE_GZIP" == true ]]; then
    GZIP_BLOCK='
    <IfModule mod_deflate.c>
        AddOutputFilterByType DEFLATE text/html text/plain text/xml text/css
        AddOutputFilterByType DEFLATE application/javascript application/json
        AddOutputFilterByType DEFLATE image/svg+xml
    </IfModule>'
else
    GZIP_BLOCK=""
fi

if [[ "$USE_CACHE" == true ]]; then
    CACHE_BLOCK='
    <IfModule mod_expires.c>
        ExpiresActive On
        ExpiresByType image/jpeg             "access plus 1 year"
        ExpiresByType image/png              "access plus 1 year"
        ExpiresByType image/webp             "access plus 1 year"
        ExpiresByType image/gif              "access plus 1 year"
        ExpiresByType image/svg+xml          "access plus 1 month"
        ExpiresByType text/css               "access plus 1 month"
        ExpiresByType application/javascript "access plus 1 month"
        ExpiresByType text/html              "access plus 1 hour"
        ExpiresDefault                       "access plus 1 week"
    </IfModule>'
else
    CACHE_BLOCK=""
fi

if [[ "$MK_ERRORS" == true ]]; then
    ERROR_BLOCK='
    ErrorDocument 403 /errors/403.html
    ErrorDocument 404 /errors/404.html
    ErrorDocument 500 /errors/500.html'
else
    ERROR_BLOCK=""
fi

cat > "$VHOST" << VHEOF
<VirtualHost *:80>
    ServerAdmin   ${ADMIN_EMAIL}
    ServerName    ${DOMAIN}
${ALIAS_LINE}
    DocumentRoot  ${DOC_ROOT}
${HTTP2_LINE}

    <Directory ${DOC_ROOT}>
        Options ${DIR_OPTS}
        AllowOverride All
        Require all granted
    </Directory>
${BLOCK_BLOCK}
${GZIP_BLOCK}
${CACHE_BLOCK}
${ERROR_BLOCK}

    ErrorLog  \${APACHE_LOG_DIR}/${DOMAIN}_error.log
    CustomLog \${APACHE_LOG_DIR}/${DOMAIN}_access.log ${LOG_FMT}
</VirtualHost>
VHEOF

ok "VirtualHost создан: $VHOST"
run "a2ensite ${DOMAIN}.conf"

if [[ "$RM_DEFAULT" == true ]]; then
    run "a2dissite 000-default.conf"
    run "a2dissite default-ssl.conf"
    ok "Дефолтный сайт отключён"
fi

# ── index.html ──────────────────────────────────────────────────
if [[ "$MK_INDEX" == true ]]; then
    cat > "${DOC_ROOT}/index.html" << IDXEOF
<!DOCTYPE html>
<html lang="ru">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${DOMAIN}</title>
<style>
  *{margin:0;padding:0;box-sizing:border-box}
  body{font-family:'Segoe UI',system-ui,sans-serif;background:#09090b;color:#e4e4e7;
       min-height:100vh;display:flex;align-items:center;justify-content:center}
  .wrap{text-align:center;padding:2rem}
  .badge{display:inline-flex;align-items:center;gap:.4rem;background:#18181b;
         border:1px solid #27272a;border-radius:999px;padding:.35rem .9rem;
         font-size:.8rem;color:#71717a;margin-bottom:2rem}
  .dot{width:7px;height:7px;border-radius:50%;background:#22c55e;animation:p 2s infinite}
  @keyframes p{0%,100%{opacity:1}50%{opacity:.3}}
  h1{font-size:2.4rem;font-weight:700;letter-spacing:-.03em;margin-bottom:.5rem}
  h1 span{color:#38bdf8}
  p{color:#71717a;margin:.5rem auto 0;line-height:1.6;font-size:.95rem;max-width:400px}
  .meta{margin-top:2rem;display:flex;gap:1rem;justify-content:center;flex-wrap:wrap}
  .meta span{font-size:.78rem;color:#52525b;background:#18181b;
             border:1px solid #27272a;border-radius:6px;padding:.3rem .7rem}
</style>
</head>
<body>
<div class="wrap">
  <div class="badge"><span class="dot"></span> Сервер работает</div>
  <h1>Добро пожаловать на<br><span>${DOMAIN}</span></h1>
  <p>Apache успешно установлен и настроен.<br>Замените этот файл содержимым вашего сайта.</p>
  <div class="meta">
    <span>Apache 2</span><span>Ubuntu ${UBUNTU_VER}</span><span>$(date +"%d.%m.%Y")</span>
  </div>
</div>
</body>
</html>
IDXEOF
    chown www-data:www-data "${DOC_ROOT}/index.html"
    ok "index.html создан"
fi

# ── robots.txt ──────────────────────────────────────────────────
if [[ "$MK_ROBOTS" == true ]]; then
    if [[ "$ROBOTS_CLOSE" == true ]]; then
        printf "User-agent: *\nDisallow: /\n" > "${DOC_ROOT}/robots.txt"
    else
        cat > "${DOC_ROOT}/robots.txt" << REOF
User-agent: *
Allow: /
Disallow: /admin/
Disallow: /private/
Disallow: /tmp/
Sitemap: https://${DOMAIN}/sitemap.xml
REOF
    fi
    chown www-data:www-data "${DOC_ROOT}/robots.txt"
    ok "robots.txt создан"
fi

# ── .htaccess ───────────────────────────────────────────────────
if [[ "$MK_HTACCESS" == true ]]; then
    cat > "${DOC_ROOT}/.htaccess" << 'HTEOF'
Options -Indexes -MultiViews

<FilesMatch "\.(env|log|ini|bak|sql|sh|conf)$">
    Require all denied
</FilesMatch>

<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteRule ^uploads/.*\.php$ - [F,L]
</IfModule>

<IfModule mod_deflate.c>
    AddOutputFilterByType DEFLATE text/html text/plain text/css application/javascript application/json
</IfModule>

<IfModule mod_expires.c>
    ExpiresActive On
    ExpiresByType image/jpeg "access 1 year"
    ExpiresByType image/png  "access 1 year"
    ExpiresByType image/webp "access 1 year"
    ExpiresByType text/css   "access 1 month"
    ExpiresByType application/javascript "access 1 month"
</IfModule>

<IfModule mod_headers.c>
    Header unset X-Powered-By
</IfModule>
HTEOF
    chown www-data:www-data "${DOC_ROOT}/.htaccess"
    ok ".htaccess создан"
fi

# ── Страницы ошибок ─────────────────────────────────────────────
if [[ "$MK_ERRORS" == true ]]; then
    mkdir -p "${DOC_ROOT}/errors"
    for code in 403 404 500; do
        case $code in
            403) t="403 — Доступ запрещён"    m="У вас нет прав для просмотра этой страницы." ic="🔒" ;;
            404) t="404 — Страница не найдена" m="Страница не существует или была перемещена." ic="🔍" ;;
            500) t="500 — Ошибка сервера"      m="Внутренняя ошибка сервера. Попробуйте позже." ic="⚙️" ;;
        esac
        cat > "${DOC_ROOT}/errors/${code}.html" << EEOF
<!DOCTYPE html><html lang="ru"><head><meta charset="UTF-8"><title>${t}</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:'Segoe UI',sans-serif;
background:#09090b;color:#e4e4e7;min-height:100vh;display:flex;align-items:center;
justify-content:center;text-align:center}.i{font-size:3rem;margin-bottom:.8rem}
.c{font-size:5rem;font-weight:900;color:#38bdf8;line-height:1}
.m{color:#71717a;margin:1rem 0 1.5rem;max-width:320px}
a{color:#38bdf8;text-decoration:none}</style></head>
<body><div><div class="i">${ic}</div><div class="c">${code}</div>
<p class="m">${m}</p><a href="/">← На главную</a></div></body></html>
EEOF
    done
    chown -R www-data:www-data "${DOC_ROOT}/errors"
    ok "Страницы ошибок 403/404/500 созданы"
fi

# ── Ротация логов ───────────────────────────────────────────────
if [[ "$LOG_ROT" == true ]]; then
    cat > "/etc/logrotate.d/apache2-${DOMAIN//\./-}" << LREOF
/var/log/apache2/${DOMAIN}_*.log {
    daily
    rotate ${LOG_DAYS}
    compress
    delaycompress
    missingok
    notifempty
    sharedscripts
    postrotate
        systemctl reload apache2 > /dev/null 2>&1 || true
    endscript
}
LREOF
    ok "Ротация логов: хранить ${LOG_DAYS} дней"
fi

# ── UFW ─────────────────────────────────────────────────────────
if [[ "$SET_UFW" == true ]]; then
    if ! command -v ufw >/dev/null 2>&1; then
        apt_install "Установка UFW" ufw
    fi
    (
        [[ "$UFW_SSH" == true ]] && ufw allow OpenSSH >> "$LOG" 2>&1
        ufw allow 'Apache Full' >> "$LOG" 2>&1
        ufw --force enable >> "$LOG" 2>&1
    ) &
    spin "Настройка UFW"
fi

# ── MPM ─────────────────────────────────────────────────────────
if [[ "$SET_MPM" == true ]]; then
    case "$MPM" in
        *event*)   run "a2dismod mpm_prefork mpm_worker"; run "a2enmod mpm_event"   ;;
        *prefork*) run "a2dismod mpm_event   mpm_worker"; run "a2enmod mpm_prefork" ;;
        *worker*)  run "a2dismod mpm_event mpm_prefork";  run "a2enmod mpm_worker"  ;;
    esac
    ok "MPM настроен"
fi

# ── Проверка конфига и перезапуск ───────────────────────────────
apache2ctl configtest >> "$LOG" 2>&1
_cfg_ok=$?
if [[ $_cfg_ok -eq 0 ]]; then
    systemctl restart apache2 >> "$LOG" 2>&1 &
    spin "Перезапуск Apache"
else
    err "Ошибка в конфиге Apache! Проверьте: $LOG"
fi

# ── SSL ─────────────────────────────────────────────────────────
SSL_OK=false
if [[ "$INSTALL_SSL" == true ]]; then
    echo ""
    if [[ "$UBUNTU_MAJOR" -ge 22 ]] && command -v snap &>/dev/null; then
        (snap install --classic certbot >> "$LOG" 2>&1 && ln -sf /snap/bin/certbot /usr/bin/certbot 2>/dev/null) &
        spin "Установка Certbot (snap)"
        # Ждём готовности snap-пакета (монтирование squashfs может занять секунды)
        _cb_wait=0
        until command -v certbot >/dev/null 2>&1 || (( ++_cb_wait > 15 )); do sleep 1; done
    else
        apt_install "Установка Certbot" certbot python3-certbot-apache
    fi

    CERT_DOMS="-d ${DOMAIN}"
    [[ "$HAS_WWW" == true ]] && CERT_DOMS="$CERT_DOMS -d www.${DOMAIN}"
    REDIR="--redirect"
    [[ "$FORCE_HTTPS" != true ]] && REDIR="--no-redirect"

    # shellcheck disable=SC2086
    certbot --apache $CERT_DOMS \
        --email "$SSL_EMAIL" \
        --agree-tos $REDIR \
        --non-interactive >> "$LOG" 2>&1 &
    spin "Получение SSL-сертификата для ${DOMAIN}"
    _ssl_rc=$?   # spin() делает wait внутри и возвращает код certbot

    if [[ $_ssl_rc -eq 0 ]]; then
        SSL_OK=true
        ok "SSL-сертификат получён"
        if [[ "$USE_HSTS" == true ]]; then
            SC="/etc/apache2/sites-available/${DOMAIN}-le-ssl.conf"
            if [[ -f "$SC" ]]; then
                # вставляем только в ПЕРВЫЙ <VirtualHost
                sed -i '0,/^<VirtualHost/{/^<VirtualHost/a\    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains; preload"
}' "$SC"
                run "systemctl reload apache2" && ok "HSTS включён"
            fi
        fi
        if [[ "$SSL_CRON" == true ]]; then
            ( crontab -l 2>/dev/null | grep -v certbot
              echo "0 3 1,26 * * certbot renew --quiet --post-hook 'systemctl reload apache2' >> /var/log/certbot-renew.log 2>&1"
            ) | crontab -
            ok "Cron: автообновление SSL 1-го и 26-го числа каждого месяца в 03:00"
        fi
    else
        wrn "Ошибка SSL. Проверьте что ${DOMAIN} указывает на этот сервер"
        wrn "Подробности: $LOG"
    fi
fi

# ══════════════════════════════════════════════════════════════════
#  ФИНАЛЬНЫЙ ОТЧЁТ
# ══════════════════════════════════════════════════════════════════
echo ""
printf "\033[0;32m\033[1m"
echo "  ╔═══════════════════════════════════════════════════════╗"
echo "  ║           УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО                 ║"
echo "  ╚═══════════════════════════════════════════════════════╝"
printf "\033[0m\n"

PROTO="http"
[[ "$SSL_OK" == true ]] && PROTO="https"

inf "Сайт:       ${W}${PROTO}://${DOMAIN}${N}"
inf "Файлы:      ${W}${DOC_ROOT}${N}"
inf "Конфиг:     ${W}${VHOST}${N}"
inf "Логи:       ${W}/var/log/apache2/${DOMAIN}_*.log${N}"
inf "Лог уст-ки: ${W}${LOG}${N}"

if [[ "$INSTALL_PHP" == true ]]; then
    inf "PHP:        ${W}${PHP_VER}${N}"
fi
if [[ "$INSTALL_DB" == true ]]; then
    echo ""
    printf "  \033[1;33m\033[1m  ДАННЫЕ БД — сохраните!\033[0m\n"
    inf "СУБД:    ${W}${DB_ENGINE} ${DB_VER}${N}"
    inf "База:    ${W}${DB_NAME}${N}"
    inf "Юзер:    ${W}${DB_USER}${N}"
    inf "Пароль:  ${R}${DB_PASS}${N}  ${D}(файл: /root/.db_${DOMAIN})${N}"
fi

echo ""
printf "  \033[2mПолезные команды:\033[0m\n"
printf "  \033[2m  systemctl status apache2\033[0m\n"
printf "  \033[2m  apache2ctl configtest\033[0m\n"
printf "  \033[2m  tail -f /var/log/apache2/${DOMAIN}_error.log\033[0m\n"
[[ "$INSTALL_SSL" == true ]] && printf "  \033[2m  certbot renew --dry-run\033[0m\n"
echo ""
