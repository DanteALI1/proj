#!/usr/bin/env bash
# =============================================================================
# linux-security-audit.sh
# Универсальный аудит и (опционально) hardening настроек безопасности Linux.
# Без firewall и SELinux. Совместим с Debian/Ubuntu, RHEL/Rocky/Alma/Fedora,
# openSUSE, Arch и большинством systemd-дистрибутивов (актуально на 2026).
# =============================================================================
set -uo pipefail

AUDIT_VERSION="1.0.0"
SCRIPT_NAME="$(basename "$0")"
REPORT_DIR="${REPORT_DIR:-/tmp/linux-security-audit}"
REPORT_FILE=""
FIX_MODE=0
AUTO_YES=0
DRY_RUN=0
QUIET=0
ONLY_CATEGORY=""
# Семейство дистрибутива (заполняется detect_os)
DISTRO_FAMILY="generic"
OS_ID="unknown"
OS_LIKE=""
OS_VERSION=""
OS_NAME="Linux"

# Счётчики
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
INFO_COUNT=0
SKIP_COUNT=0
FIXED_COUNT=0

# Цвета (отключаются при не-TTY / NO_COLOR)
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[0;33m'
  C_BLUE=$'\033[0;34m'; C_CYAN=$'\033[0;36m'; C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""
  C_BOLD=""; C_DIM=""; C_RESET=""
fi

# =============================================================================
# Утилиты
# =============================================================================
usage() {
  cat <<EOF
${C_BOLD}Linux Security Audit ${AUDIT_VERSION}${C_RESET}

Использование:
  $SCRIPT_NAME [опции]

Опции:
  -a, --audit          Только аудит (по умолчанию)
  -f, --fix            Аудит + предложить/применить исправления
  -y, --yes            Не спрашивать подтверждение при --fix (осторожно!)
  -n, --dry-run        Показать, что было бы изменено, без записи
  -c, --category NAME  Только категория: ssh|auth|sysctl|perms|accounts|
                       services|kernel|logging|updates|network|misc
  -o, --output DIR     Каталог для отчёта (по умолчанию: $REPORT_DIR)
  -q, --quiet          Меньше вывода в консоль
  -h, --help           Справка
  -V, --version        Версия

Исключено по запросу: firewall, SELinux.
EOF
}

log()   { [[ $QUIET -eq 1 ]] || printf '%s\n' "$*"; }
logn()  { [[ $QUIET -eq 1 ]] || printf '%s' "$*"; }
section() {
  echo
  log "${C_BOLD}${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
  log "${C_BOLD}${C_CYAN}  $*${C_RESET}"
  log "${C_BOLD}${C_CYAN}════════════════════════════════════════════════════════════${C_RESET}"
  echo "=== $* ===" >>"$REPORT_FILE"
}

result() {
  local status="$1" title="$2" detail="${3:-}" fix_hint="${4:-}"
  local icon color
  case "$status" in
    PASS) icon="[OK]";   color="$C_GREEN";  PASS_COUNT=$((PASS_COUNT+1)) ;;
    WARN) icon="[!!]";   color="$C_YELLOW"; WARN_COUNT=$((WARN_COUNT+1)) ;;
    FAIL) icon="[XX]";   color="$C_RED";    FAIL_COUNT=$((FAIL_COUNT+1)) ;;
    INFO) icon="[--]";   color="$C_BLUE";   INFO_COUNT=$((INFO_COUNT+1)) ;;
    SKIP) icon="[>>]";   color="$C_DIM";    SKIP_COUNT=$((SKIP_COUNT+1)) ;;
    FIXED) icon="[++]";  color="$C_GREEN";  FIXED_COUNT=$((FIXED_COUNT+1)); status="FIXED" ;;
    *)    icon="[??]";   color="$C_DIM" ;;
  esac
  log "${color}${icon}${C_RESET} ${C_BOLD}${title}${C_RESET}"
  [[ -n "$detail" ]] && log "     ${C_DIM}${detail}${C_RESET}"
  [[ -n "$fix_hint" && "$status" != "PASS" && "$status" != "FIXED" && "$status" != "INFO" ]] && \
    log "     ${C_YELLOW}→ ${fix_hint}${C_RESET}"
  {
    echo "[$status] $title"
    [[ -n "$detail" ]] && echo "  detail: $detail"
    [[ -n "$fix_hint" ]] && echo "  fix: $fix_hint"
  } >>"$REPORT_FILE"
}

need_root() {
  if [[ $EUID -ne 0 ]]; then
    log "${C_YELLOW}Внимание: запуск без root. Часть проверок и все исправления недоступны.${C_RESET}"
    return 1
  fi
  return 0
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# Определение семейства ОС
detect_os() {
  OS_ID="unknown"; OS_LIKE=""; OS_VERSION=""; OS_NAME="Linux"
  if [[ -f /etc/os-release ]]; then
    # Не source целиком — VERSION из os-release перетирает наши переменные
    OS_ID="$(. /etc/os-release; echo "${ID:-unknown}")"
    OS_LIKE="$(. /etc/os-release; echo "${ID_LIKE:-}")"
    OS_VERSION="$(. /etc/os-release; echo "${VERSION_ID:-}")"
    OS_NAME="$(. /etc/os-release; echo "${PRETTY_NAME:-$NAME}")"
  fi
  if [[ "$OS_ID" =~ ^(debian|ubuntu|linuxmint|pop|elementary|raspbian)$ ]] || \
     [[ "$OS_LIKE" =~ debian ]]; then
    DISTRO_FAMILY="debian"
  elif [[ "$OS_ID" =~ ^(rhel|centos|rocky|almalinux|fedora|ol|amzn|eurolinux)$ ]] || \
       [[ "$OS_LIKE" =~ (rhel|fedora|centos) ]]; then
    DISTRO_FAMILY="rhel"
  elif [[ "$OS_ID" =~ ^(opensuse|sles|suse)$ ]] || [[ "$OS_LIKE" =~ suse ]]; then
    DISTRO_FAMILY="suse"
  elif [[ "$OS_ID" =~ ^(arch|manjaro|endeavouros|garuda)$ ]] || [[ "$OS_LIKE" =~ arch ]]; then
    DISTRO_FAMILY="arch"
  else
    DISTRO_FAMILY="generic"
  fi
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  local b="${REPORT_DIR}/backups$(echo "$f" | sed 's|/|_|g').bak.$(date +%Y%m%d%H%M%S)"
  mkdir -p "$(dirname "$b")"
  cp -a "$f" "$b" 2>/dev/null || cp "$f" "$b"
  echo "$b"
}

confirm_fix() {
  local msg="$1"
  [[ $FIX_MODE -eq 0 ]] && return 1
  [[ $DRY_RUN -eq 1 ]] && { log "     ${C_DIM}[dry-run] $msg${C_RESET}"; return 0; }
  [[ $AUTO_YES -eq 1 ]] && return 0
  local ans
  logn "     ${C_YELLOW}Применить? [y/N]: ${C_RESET}"
  read -r ans
  [[ "$ans" =~ ^[YyДд]$ ]]
}

set_sysctl() {
  local key="$1" val="$2" conf="${3:-/etc/sysctl.d/99-security-audit.conf}"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "     ${C_DIM}[dry-run] sysctl $key=$val → $conf${C_RESET}"
    return 0
  fi
  mkdir -p "$(dirname "$conf")"
  touch "$conf"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "$conf" 2>/dev/null; then
    sed -i "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${val}|" "$conf"
  else
    echo "${key} = ${val}" >>"$conf"
  fi
  sysctl -w "${key}=${val}" >/dev/null 2>&1 || true
}

ensure_line_in_file() {
  local file="$1" pattern="$2" line="$3"
  if [[ $DRY_RUN -eq 1 ]]; then
    log "     ${C_DIM}[dry-run] ensure in $file: $line${C_RESET}"
    return 0
  fi
  mkdir -p "$(dirname "$file")"
  touch "$file"
  if grep -qE "$pattern" "$file" 2>/dev/null; then
    sed -i "s|$pattern|$line|" "$file" 2>/dev/null || {
      # fallback: удалить и добавить
      grep -vE "$pattern" "$file" >"${file}.tmp" && mv "${file}.tmp" "$file"
      echo "$line" >>"$file"
    }
  else
    echo "$line" >>"$file"
  fi
}

get_sshd_config() {
  # Эффективное значение sshd (если доступен sshd -T)
  local key="$1" default="${2:-}"
  if have_cmd sshd; then
    local v
    v="$(sshd -T 2>/dev/null | awk -v k="$(echo "$key" | tr '[:upper:]' '[:lower:]')" 'tolower($1)==k {print $2; exit}')"
    [[ -n "$v" ]] && { echo "$v"; return 0; }
  fi
  # Fallback: парсинг конфигов
  local conf="/etc/ssh/sshd_config"
  [[ -f "$conf" ]] || { echo "$default"; return 1; }
  local v
  v="$(grep -E "^[[:space:]]*${key}[[:space:]]+" "$conf" 2>/dev/null | awk '{print $2}' | tail -1)"
  echo "${v:-$default}"
}

service_active() {
  local s="$1"
  have_cmd systemctl || return 1
  systemctl is-active --quiet "$s" 2>/dev/null
}

service_enabled() {
  local s="$1"
  have_cmd systemctl || return 1
  systemctl is-enabled --quiet "$s" 2>/dev/null
}

# =============================================================================
# Категория: система / окружение
# =============================================================================
check_system_info() {
  section "Информация о системе"
  result INFO "ОС" "$OS_NAME (family=$DISTRO_FAMILY, id=$OS_ID $OS_VERSION)"
  result INFO "Ядро" "$(uname -r) ($(uname -m))"
  result INFO "Hostname" "$(hostname 2>/dev/null || echo '?')"
  result INFO "Дата аудита" "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
  if [[ $EUID -eq 0 ]]; then
    result PASS "Права запуска" "root — полный аудит и исправления доступны"
  else
    result WARN "Права запуска" "не root — часть проверок ограничена" \
      "Запустите: sudo $SCRIPT_NAME $*"
  fi
}

# =============================================================================
# Категория: SSH
# =============================================================================
check_ssh() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "ssh" ]] && return 0
  section "SSH (OpenSSH)"

  if ! have_cmd sshd && [[ ! -f /etc/ssh/sshd_config ]]; then
    result SKIP "OpenSSH" "sshd не установлен"
    return 0
  fi

  local v

  v="$(get_sshd_config PermitRootLogin no)"
  if [[ "${v,,}" =~ ^(no|prohibit-password|without-password|forced-commands-only)$ ]]; then
    result PASS "PermitRootLogin" "значение: $v"
  else
    result FAIL "PermitRootLogin" "значение: ${v:-unset} (ожидается no / prohibit-password)" \
      "В /etc/ssh/sshd_config: PermitRootLogin no"
    if confirm_fix "Установить PermitRootLogin no"; then
      backup_file /etc/ssh/sshd_config >/dev/null
      if [[ -f /etc/ssh/sshd_config ]]; then
        if grep -qiE '^[[:space:]]*PermitRootLogin' /etc/ssh/sshd_config; then
          sed -i 's/^[[:space:]]*PermitRootLogin.*/PermitRootLogin no/I' /etc/ssh/sshd_config
        else
          echo "PermitRootLogin no" >>/etc/ssh/sshd_config
        fi
        [[ $DRY_RUN -eq 0 ]] && systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
        result FIXED "PermitRootLogin" "установлено no"
      fi
    fi
  fi

  v="$(get_sshd_config PasswordAuthentication yes)"
  if [[ "${v,,}" == "no" ]]; then
    result PASS "PasswordAuthentication" "отключена (только ключи)"
  else
    result WARN "PasswordAuthentication" "значение: ${v:-yes} — парольный вход уязвим к брутфорсу" \
      "PasswordAuthentication no (убедитесь, что ключи настроены!)"
    if confirm_fix "Отключить PasswordAuthentication (нужны SSH-ключи!)"; then
      backup_file /etc/ssh/sshd_config >/dev/null
      if grep -qiE '^[[:space:]]*PasswordAuthentication' /etc/ssh/sshd_config; then
        sed -i 's/^[[:space:]]*PasswordAuthentication.*/PasswordAuthentication no/I' /etc/ssh/sshd_config
      else
        echo "PasswordAuthentication no" >>/etc/ssh/sshd_config
      fi
      [[ $DRY_RUN -eq 0 ]] && systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || true
      result FIXED "PasswordAuthentication" "отключена"
    fi
  fi

  v="$(get_sshd_config KbdInteractiveAuthentication yes)"
  # Старые версии: ChallengeResponseAuthentication
  local cra
  cra="$(get_sshd_config ChallengeResponseAuthentication "${v}")"
  if [[ "${v,,}" == "no" || "${cra,,}" == "no" ]]; then
    result PASS "KbdInteractive/ChallengeResponse" "отключено"
  else
    result WARN "KbdInteractiveAuthentication" "может обходить PasswordAuthentication" \
      "KbdInteractiveAuthentication no"
  fi

  v="$(get_sshd_config PermitEmptyPasswords no)"
  if [[ "${v,,}" == "no" ]]; then
    result PASS "PermitEmptyPasswords" "no"
  else
    result FAIL "PermitEmptyPasswords" "значение: $v" "PermitEmptyPasswords no"
    if confirm_fix "Запретить пустые пароли в SSH"; then
      backup_file /etc/ssh/sshd_config >/dev/null
      if grep -qiE '^[[:space:]]*PermitEmptyPasswords' /etc/ssh/sshd_config; then
        sed -i 's/^[[:space:]]*PermitEmptyPasswords.*/PermitEmptyPasswords no/I' /etc/ssh/sshd_config
      else
        echo "PermitEmptyPasswords no" >>/etc/ssh/sshd_config
      fi
      result FIXED "PermitEmptyPasswords" "no"
    fi
  fi

  v="$(get_sshd_config X11Forwarding no)"
  if [[ "${v,,}" == "no" ]]; then
    result PASS "X11Forwarding" "отключено"
  else
    result WARN "X11Forwarding" "включено — риск при компрометации X" "X11Forwarding no"
  fi

  v="$(get_sshd_config MaxAuthTries 6)"
  if [[ "${v:-6}" -le 4 ]] 2>/dev/null; then
    result PASS "MaxAuthTries" "$v"
  else
    result WARN "MaxAuthTries" "${v:-default} (рекомендуется ≤ 4)" "MaxAuthTries 4"
    if confirm_fix "Установить MaxAuthTries 4"; then
      backup_file /etc/ssh/sshd_config >/dev/null
      if grep -qiE '^[[:space:]]*MaxAuthTries' /etc/ssh/sshd_config; then
        sed -i 's/^[[:space:]]*MaxAuthTries.*/MaxAuthTries 4/I' /etc/ssh/sshd_config
      else
        echo "MaxAuthTries 4" >>/etc/ssh/sshd_config
      fi
      result FIXED "MaxAuthTries" "4"
    fi
  fi

  v="$(get_sshd_config ClientAliveInterval 0)"
  local ca="$(get_sshd_config ClientAliveCountMax 3)"
  if [[ "${v:-0}" -gt 0 ]] 2>/dev/null; then
    result PASS "ClientAliveInterval" "$v (CountMax=$ca)"
  else
    result WARN "ClientAliveInterval" "не задан — «мёртвые» сессии не рвутся" \
      "ClientAliveInterval 300 / ClientAliveCountMax 2"
  fi

  v="$(get_sshd_config AllowTcpForwarding yes)"
  if [[ "${v,,}" == "no" ]]; then
    result PASS "AllowTcpForwarding" "no"
  else
    result INFO "AllowTcpForwarding" "${v:-yes} — отключайте, если туннели не нужны"
  fi

  v="$(get_sshd_config Protocol 2)"
  result INFO "Protocol / версия OpenSSH" "$(sshd -V 2>&1 | head -1 || echo "Protocol $v")"

  # Порт
  v="$(get_sshd_config Port 22)"
  if [[ "$v" == "22" ]]; then
    result INFO "SSH Port" "22 (стандартный; смена — security through obscurity, опционально)"
  else
    result PASS "SSH Port" "нестандартный: $v"
  fi

  # Banner / LoginGraceTime
  v="$(get_sshd_config LoginGraceTime 120)"
  if [[ "${v:-120}" -le 60 ]] 2>/dev/null; then
    result PASS "LoginGraceTime" "$v"
  else
    result WARN "LoginGraceTime" "${v}s (рекомендуется ≤ 60)" "LoginGraceTime 60"
  fi

  # UsePAM
  v="$(get_sshd_config UsePAM yes)"
  if [[ "${v,,}" == "yes" ]]; then
    result PASS "UsePAM" "yes"
  else
    result WARN "UsePAM" "$v — без PAM слабее контроль политик" "UsePAM yes"
  fi
}

# =============================================================================
# Категория: аутентификация / пароли / PAM
# =============================================================================
check_auth() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "auth" ]] && return 0
  section "Аутентификация и политика паролей"

  # login.defs
  local pass_max pass_min pass_warn umask_val encrypt
  if [[ -f /etc/login.defs ]]; then
    pass_max="$(awk '/^PASS_MAX_DAYS/ {print $2}' /etc/login.defs | tail -1)"
    pass_min="$(awk '/^PASS_MIN_DAYS/ {print $2}' /etc/login.defs | tail -1)"
    pass_warn="$(awk '/^PASS_WARN_AGE/ {print $2}' /etc/login.defs | tail -1)"
    umask_val="$(awk '/^UMASK/ {print $2}' /etc/login.defs | tail -1)"
    encrypt="$(awk '/^ENCRYPT_METHOD/ {print $2}' /etc/login.defs | tail -1)"

    if [[ -n "$pass_max" && "$pass_max" -le 365 && "$pass_max" -gt 0 ]] 2>/dev/null; then
      result PASS "PASS_MAX_DAYS" "$pass_max"
    else
      result WARN "PASS_MAX_DAYS" "${pass_max:-unset} (рекомендуется 90–365)" \
        "В /etc/login.defs: PASS_MAX_DAYS 90"
      if confirm_fix "Установить PASS_MAX_DAYS 90"; then
        backup_file /etc/login.defs >/dev/null
        if grep -qE '^PASS_MAX_DAYS' /etc/login.defs; then
          sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS\t90/' /etc/login.defs
        else
          echo -e "PASS_MAX_DAYS\t90" >>/etc/login.defs
        fi
        result FIXED "PASS_MAX_DAYS" "90"
      fi
    fi

    if [[ -n "$pass_min" && "$pass_min" -ge 1 ]] 2>/dev/null; then
      result PASS "PASS_MIN_DAYS" "$pass_min"
    else
      result WARN "PASS_MIN_DAYS" "${pass_min:-0}" "PASS_MIN_DAYS 1"
    fi

    if [[ -n "$pass_warn" && "$pass_warn" -ge 7 ]] 2>/dev/null; then
      result PASS "PASS_WARN_AGE" "$pass_warn"
    else
      result WARN "PASS_WARN_AGE" "${pass_warn:-unset}" "PASS_WARN_AGE 14"
    fi

    if [[ "${umask_val:-022}" =~ ^(027|077)$ ]]; then
      result PASS "UMASK (login.defs)" "$umask_val"
    else
      result WARN "UMASK (login.defs)" "${umask_val:-022} (рекомендуется 027)" \
        "UMASK 027"
      if confirm_fix "Установить UMASK 027"; then
        backup_file /etc/login.defs >/dev/null
        if grep -qE '^UMASK' /etc/login.defs; then
          sed -i 's/^UMASK.*/UMASK\t\t027/' /etc/login.defs
        else
          echo -e "UMASK\t\t027" >>/etc/login.defs
        fi
        result FIXED "UMASK" "027"
      fi
    fi

    case "${encrypt^^}" in
      SHA512|YESCRYPT|BCRYPT) result PASS "ENCRYPT_METHOD" "$encrypt" ;;
      *) result WARN "ENCRYPT_METHOD" "${encrypt:-default} (рекомендуется yescrypt или SHA512)" \
           "ENCRYPT_METHOD YESCRYPT" ;;
    esac
  else
    result SKIP "login.defs" "файл не найден"
  fi

  # pwquality / pam_pwquality
  local pwq=""
  for f in /etc/security/pwquality.conf /etc/security/pwquality.conf.d/*.conf; do
    [[ -f "$f" ]] || continue
    pwq="$f"
    break
  done
  if [[ -n "$pwq" ]]; then
    local minlen dcredit ucredit ocredit lcredit
    minlen="$(grep -E '^[[:space:]]*minlen' "$pwq" 2>/dev/null | awk -F= '{gsub(/ /,"",$2); print $2}' | tail -1)"
    dcredit="$(grep -E '^[[:space:]]*dcredit' "$pwq" 2>/dev/null | awk -F= '{gsub(/ /,"",$2); print $2}' | tail -1)"
    if [[ -n "$minlen" && "$minlen" -ge 12 ]] 2>/dev/null; then
      result PASS "pwquality minlen" "$minlen ($pwq)"
    else
      result WARN "pwquality minlen" "${minlen:-unset} (рекомендуется ≥ 12)" \
        "minlen = 14 в $pwq"
      if confirm_fix "Установить minlen=14 в pwquality"; then
        backup_file "$pwq" >/dev/null
        ensure_line_in_file "$pwq" '^[[:space:]]*minlen[[:space:]]*=' 'minlen = 14'
        result FIXED "pwquality minlen" "14"
      fi
    fi
    result INFO "pwquality credits" "dcredit=${dcredit:-?} (отрицательные значения = обязательные классы символов)"
  else
    # Debian часто использует pam_unix + common-password
    if [[ -f /etc/pam.d/common-password ]] || [[ -f /etc/pam.d/system-auth ]]; then
      result WARN "pwquality" "конфиг не найден — проверьте PAM (pam_pwquality / pam_passwdqc)" \
        "apt install libpam-pwquality  или  dnf install libpwquality"
    else
      result SKIP "pwquality" "нет конфига"
    fi
  fi

  # faillock / tally2
  if [[ -f /etc/security/faillock.conf ]] || grep -rq faillock /etc/pam.d 2>/dev/null; then
    result PASS "Блокировка после неудачных попыток" "pam_faillock обнаружен"
  elif grep -rq 'pam_tally2\|pam_faillock' /etc/pam.d 2>/dev/null; then
    result PASS "Блокировка после неудачных попыток" "настроена в PAM"
  else
    result WARN "Блокировка после неудачных попыток" "pam_faillock не найден" \
      "Включите pam_faillock.so в password-auth / system-auth / common-auth"
  fi

  # su restrictions
  if [[ -f /etc/pam.d/su ]]; then
    if grep -qE '^auth[[:space:]].*pam_wheel' /etc/pam.d/su; then
      result PASS "su → wheel/group" "pam_wheel включён"
    else
      result WARN "su → wheel/group" "любой пользователь может пробовать su" \
        "Раскомментируйте: auth required pam_wheel.so use_uid"
    fi
  fi
}

# =============================================================================
# Категория: учётные записи
# =============================================================================
check_accounts() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "accounts" ]] && return 0
  section "Учётные записи"

  # UID 0
  local root_users
  root_users="$(awk -F: '($3==0){print $1}' /etc/passwd 2>/dev/null)"
  local root_count
  root_count="$(echo "$root_users" | grep -c . || true)"
  if [[ "$root_count" -eq 1 && "$root_users" == "root" ]]; then
    result PASS "UID 0" "только root"
  else
    result FAIL "UID 0" "аккаунты с UID 0: $root_users" "Удалите/исправьте лишние учётки с UID 0"
  fi

  # Пустые пароли
  if [[ -r /etc/shadow ]]; then
    local empty
    empty="$(awk -F: '($2==""){print $1}' /etc/shadow 2>/dev/null | tr '\n' ' ')"
    if [[ -z "${empty// }" ]]; then
      result PASS "Пустые пароли в shadow" "нет"
    else
      result FAIL "Пустые пароли в shadow" "$empty" "passwd -l USER или задайте пароль"
    fi
  else
    result SKIP "shadow" "нет прав на чтение /etc/shadow"
  fi

  # Интерактивные пользователи без пароля / заблокированные shell
  local nologin_shells="/usr/sbin/nologin|/sbin/nologin|/bin/false|/usr/bin/false"
  local suspicious=""
  while IFS=: read -r user _ uid _ _ _ shell; do
    [[ "$uid" -ge 1000 ]] 2>/dev/null || continue
    [[ "$user" == "nobody" ]] && continue
    if [[ ! "$shell" =~ ($nologin_shells) ]]; then
      if [[ -r /etc/shadow ]]; then
        local hash
        hash="$(awk -F: -v u="$user" '($1==u){print $2}' /etc/shadow)"
        if [[ "$hash" == "*" || "$hash" == "!" || "$hash" == "!!" ]]; then
          suspicious+="$user(locked+shell) "
        fi
      fi
    fi
  done </etc/passwd
  if [[ -z "$suspicious" ]]; then
    result PASS "Заблокированные интерактивные учётки" "аномалий не видно"
  else
    result WARN "Заблокированные с login-shell" "$suspicious" \
      "usermod -s /usr/sbin/nologin USER"
  fi

  # home world-writable
  local bad_homes=""
  while IFS=: read -r user _ uid _ _ home _; do
    [[ "$uid" -ge 1000 && -d "$home" ]] || continue
    local mode
    mode="$(stat -c '%a' "$home" 2>/dev/null || stat -f '%OLp' "$home" 2>/dev/null)"
    if [[ "${mode: -1}" =~ [2367] ]]; then
      bad_homes+="$home($mode) "
    fi
  done </etc/passwd
  if [[ -z "$bad_homes" ]]; then
    result PASS "Права на home" "нет world-writable каталогов"
  else
    result FAIL "World-writable home" "$bad_homes" "chmod 750 /home/USER"
  fi

  # sudo
  if have_cmd sudo || [[ -d /etc/sudoers.d ]]; then
    if [[ -r /etc/sudoers ]]; then
      if grep -rE '^[^#].*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -qv '^\s*$'; then
        local nopass
        nopass="$(grep -rhE '^[^#].*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null | head -5 | tr '\n' ';')"
        result WARN "sudo NOPASSWD" "найдены правила: $nopass" \
          "Уберите NOPASSWD там, где не критично для автоматизации"
      else
        result PASS "sudo NOPASSWD" "явных опасных правил не найдено"
      fi
      if grep -rE '^[^#].*ALL=\(ALL\)[[:space:]]*ALL' /etc/sudoers /etc/sudoers.d 2>/dev/null | grep -qv root; then
        result INFO "sudo ALL=(ALL) ALL" "широкие права — проверьте, кому выданы"
      fi
    else
      result SKIP "sudoers" "нет прав на чтение"
    fi
  else
    result INFO "sudo" "не установлен"
  fi

  # inactive users (lastlog) — info
  if have_cmd lastlog; then
    result INFO "lastlog" "проверьте неактивных: lastlog -b 90"
  fi
}

# =============================================================================
# Категория: права на критичные файлы
# =============================================================================
check_perms() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "perms" ]] && return 0
  section "Права на критичные файлы и каталоги"

  check_file_mode() {
    local path="$1" max_mode="$2" owner="$3" group="${4:-$3}"
    [[ -e "$path" ]] || { result SKIP "$path" "не существует"; return; }
    local mode own grp
    mode="$(stat -c '%a' "$path" 2>/dev/null)"
    own="$(stat -c '%U' "$path" 2>/dev/null)"
    grp="$(stat -c '%G' "$path" 2>/dev/null)"
    local ok=1
    if [[ -n "$mode" ]]; then
      local m=$((8#$mode)) mx=$((8#$max_mode))
      if (( m > mx )); then ok=0; fi
    fi
    if [[ "$own" != "$owner" && "$owner" != "*" ]]; then ok=0; fi
    if [[ "$group" != "*" && "$grp" != "$group" && "$grp" != "root" && "$grp" != "shadow" ]]; then
      # shadow/root — допустимые группы для shadow-файлов
      :
    fi
    if [[ $ok -eq 1 ]]; then
      result PASS "$path" "mode=$mode owner=$own:$grp"
    else
      result FAIL "$path" "mode=$mode owner=$own:$grp (ожидается ≤$max_mode, owner=$owner)" \
        "chown $owner:$group $path; chmod $max_mode $path"
      if confirm_fix "Исправить права $path → $max_mode $owner:$group"; then
        [[ $DRY_RUN -eq 0 ]] && chown "$owner:$group" "$path" 2>/dev/null
        [[ $DRY_RUN -eq 0 ]] && chmod "$max_mode" "$path" 2>/dev/null
        result FIXED "$path" "mode=$max_mode owner=$owner:$group"
      fi
    fi
  }

  check_file_mode /etc/passwd 644 root root
  # Debian/Ubuntu: root:shadow; RHEL: root:root — принимаем оба
  if [[ -f /etc/shadow ]]; then
    local sg
    sg="$(stat -c '%G' /etc/shadow 2>/dev/null)"
    if [[ "$sg" == "shadow" ]]; then
      check_file_mode /etc/shadow 640 root shadow
    else
      check_file_mode /etc/shadow 640 root root
    fi
  fi
  if [[ -f /etc/gshadow ]]; then
    local gg
    gg="$(stat -c '%G' /etc/gshadow 2>/dev/null)"
    if [[ "$gg" == "shadow" ]]; then
      check_file_mode /etc/gshadow 640 root shadow
    else
      check_file_mode /etc/gshadow 640 root root
    fi
  fi
  check_file_mode /etc/group 644 root root
  check_file_mode /etc/ssh/sshd_config 600 root root
  [[ -d /boot ]] && check_file_mode /boot 755 root root
  check_file_mode /etc/crontab 600 root root
  [[ -d /etc/cron.d ]] && check_file_mode /etc/cron.d 755 root root

  # sticky /tmp и остальное — ниже без изменений маркера
  # (повторно не вызываем старые check_file_mode для shadow)

  # Sticky bit на /tmp
  if [[ -d /tmp ]]; then
    local tmode
    tmode="$(stat -c '%a' /tmp 2>/dev/null)"
    if [[ "$tmode" =~ ^1[0-9]{3}$ ]] || [[ "$tmode" == "1777" ]]; then
      result PASS "/tmp sticky bit" "mode=$tmode"
    else
      result FAIL "/tmp sticky bit" "mode=$tmode (нужен 1777)" "chmod 1777 /tmp"
      if confirm_fix "chmod 1777 /tmp"; then
        [[ $DRY_RUN -eq 0 ]] && chmod 1777 /tmp
        result FIXED "/tmp" "1777"
      fi
    fi
  fi

  # World-writable вне tmp (выборочно, ограниченный поиск)
  if [[ $EUID -eq 0 ]]; then
    local ww
    ww="$(find /etc /usr/local/etc /opt -xdev -type f -perm -0002 2>/dev/null | head -20)"
    if [[ -z "$ww" ]]; then
      result PASS "World-writable файлы в /etc,/opt" "не найдены (выборка)"
    else
      result WARN "World-writable файлы" "$(echo "$ww" | tr '\n' ' ')" \
        "chmod o-w FILE"
    fi
  else
    result SKIP "World-writable поиск" "нужен root"
  fi

  # Unowned files sample
  if [[ $EUID -eq 0 ]]; then
    local unowned
    unowned="$(find /etc -xdev \( -nouser -o -nogroup \) 2>/dev/null | head -10)"
    if [[ -z "$unowned" ]]; then
      result PASS "Файлы без владельца (/etc)" "не найдены"
    else
      result WARN "Файлы без владельца" "$(echo "$unowned" | tr '\n' ' ')" \
        "chown root:root FILE или удалите"
    fi
  fi
}

# =============================================================================
# Категория: sysctl / сеть (без firewall)
# =============================================================================
check_sysctl() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "sysctl" && "$ONLY_CATEGORY" != "network" && "$ONLY_CATEGORY" != "kernel" ]] && return 0
  section "Параметры ядра (sysctl) и сеть"

  check_sysctl_key() {
    local key="$1" expected="$2" severity="${3:-WARN}" desc="${4:-}"
    local cur
    cur="$(sysctl -n "$key" 2>/dev/null || echo "N/A")"
    if [[ "$cur" == "N/A" ]]; then
      result SKIP "$key" "параметр недоступен"
      return
    fi
    if [[ "$cur" == "$expected" ]]; then
      result PASS "$key" "=$cur ${desc:+— $desc}"
    else
      result "$severity" "$key" "=$cur (ожидается $expected) ${desc:+— $desc}" \
        "sysctl -w $key=$expected и запись в /etc/sysctl.d/99-security-audit.conf"
      if confirm_fix "Установить $key=$expected"; then
        set_sysctl "$key" "$expected"
        result FIXED "$key" "=$expected"
      fi
    fi
  }

  # IP spoofing / redirects / source route
  check_sysctl_key net.ipv4.conf.all.rp_filter 1 WARN "anti-spoofing"
  check_sysctl_key net.ipv4.conf.default.rp_filter 1 WARN
  check_sysctl_key net.ipv4.conf.all.accept_source_route 0 FAIL "запрет source routing"
  check_sysctl_key net.ipv4.conf.default.accept_source_route 0 FAIL
  check_sysctl_key net.ipv4.conf.all.accept_redirects 0 WARN "ICMP redirects"
  check_sysctl_key net.ipv4.conf.default.accept_redirects 0 WARN
  check_sysctl_key net.ipv4.conf.all.secure_redirects 0 WARN
  check_sysctl_key net.ipv4.conf.all.send_redirects 0 WARN "хост не должен быть роутером"
  check_sysctl_key net.ipv4.conf.default.send_redirects 0 WARN
  check_sysctl_key net.ipv4.icmp_echo_ignore_broadcasts 1 WARN
  check_sysctl_key net.ipv4.icmp_ignore_bogus_error_responses 1 WARN
  check_sysctl_key net.ipv4.tcp_syncookies 1 WARN "защита от SYN flood"
  check_sysctl_key net.ipv4.conf.all.log_martians 1 INFO "лог «martian» пакетов"

  # IPv6 redirects (если включён)
  if [[ -e /proc/sys/net/ipv6/conf/all/accept_redirects ]]; then
    check_sysctl_key net.ipv6.conf.all.accept_redirects 0 WARN
    check_sysctl_key net.ipv6.conf.default.accept_redirects 0 WARN
    check_sysctl_key net.ipv6.conf.all.accept_source_route 0 WARN
  fi

  # IP forwarding — info (может быть нужно на роутере/VPN)
  local fwd
  fwd="$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo 0)"
  if [[ "$fwd" == "0" ]]; then
    result PASS "ip_forward" "0 (не роутер)"
  else
    result INFO "ip_forward" "1 — нормально для роутера/NAT/VPN, иначе отключите"
  fi

  # ASLR
  check_sysctl_key kernel.randomize_va_space 2 FAIL "ASLR полный"
  # kptr
  check_sysctl_key kernel.kptr_restrict 1 WARN "скрытие адресов ядра"
  check_sysctl_key kernel.dmesg_restrict 1 WARN "ограничение dmesg"
  check_sysctl_key kernel.yama.ptrace_scope 1 WARN "ограничение ptrace"
  check_sysctl_key kernel.sysrq 0 INFO "SysRq (0=выкл; на серверах часто 0 или 176)"
  check_sysctl_key kernel.core_uses_pid 1 INFO
  check_sysctl_key fs.protected_hardlinks 1 WARN
  check_sysctl_key fs.protected_symlinks 1 WARN
  check_sysctl_key fs.suid_dumpable 0 WARN "запрет core dump для SUID"
  # 1 = disabled, 2 = disabled permanently (ещё строже) — оба OK
  local bpf_dis
  bpf_dis="$(sysctl -n kernel.unprivileged_bpf_disabled 2>/dev/null || echo N/A)"
  if [[ "$bpf_dis" == "N/A" ]]; then
    result SKIP "kernel.unprivileged_bpf_disabled" "параметр недоступен"
  elif [[ "$bpf_dis" == "1" || "$bpf_dis" == "2" ]]; then
    result PASS "kernel.unprivileged_bpf_disabled" "=$bpf_dis — unprivileged BPF выключен"
  else
    result WARN "kernel.unprivileged_bpf_disabled" "=$bpf_dis (ожидается 1 или 2)" \
      "sysctl -w kernel.unprivileged_bpf_disabled=1"
    if confirm_fix "Установить kernel.unprivileged_bpf_disabled=1"; then
      set_sysctl kernel.unprivileged_bpf_disabled 1
      result FIXED "kernel.unprivileged_bpf_disabled" "=1"
    fi
  fi
  # user namespaces — спорно для контейнеров
  if [[ -e /proc/sys/kernel/unprivileged_userns_clone ]]; then
    local uns
    uns="$(sysctl -n kernel.unprivileged_userns_clone 2>/dev/null)"
    result INFO "unprivileged_userns_clone" "=$uns (0 безопаснее, но ломает часть контейнеров/браузеров)"
  fi
  if [[ -e /proc/sys/user/max_user_namespaces ]]; then
    result INFO "max_user_namespaces" "=$(sysctl -n user.max_user_namespaces 2>/dev/null)"
  fi
}

# =============================================================================
# Категория: сервисы
# =============================================================================
check_services() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "services" ]] && return 0
  section "Сервисы и демоны"

  if ! have_cmd systemctl; then
    result SKIP "systemd" "systemctl недоступен"
    return 0
  fi

  # Потенциально опасные / лишние на сервере
  local risky=(
    "telnet.socket:telnet"
    "telnet.service:telnet"
    "rsh.socket:rsh"
    "rlogin.socket:rlogin"
    "rexec.socket:rexec"
    "vsftpd.service:ftp"
    "ftp.service:ftp"
    "nfs-server.service:nfs"
    "rpcbind.service:rpcbind"
    "ypbind.service:nis"
    "xinetd.service:xinetd"
    "avahi-daemon.service:avahi"
    "cups.service:cups"
    "bluetooth.service:bluetooth"
  )

  local entry svc name
  for entry in "${risky[@]}"; do
    svc="${entry%%:*}"; name="${entry##*:}"
    if systemctl list-unit-files "$svc" 2>/dev/null | grep -q "$svc"; then
      if service_active "$svc" || service_enabled "$svc"; then
        result WARN "Сервис $name ($svc)" "активен/включён — отключите, если не нужен" \
          "systemctl disable --now $svc"
        if confirm_fix "Отключить $svc"; then
          if [[ $DRY_RUN -eq 0 ]]; then
            systemctl disable --now "$svc" 2>/dev/null || true
          fi
          result FIXED "$svc" "отключён"
        fi
      else
        result PASS "Сервис $name" "не активен"
      fi
    fi
  done

  # chrony / systemd-timesyncd
  if service_active chronyd || service_active chrony || service_active systemd-timesyncd; then
    result PASS "Синхронизация времени" "chrony/timesyncd активен"
  else
    result WARN "Синхронизация времени" "NTP-клиент не активен" \
      "systemctl enable --now chronyd  или  systemd-timesyncd"
  fi

  # AppArmor (не SELinux)
  if have_cmd aa-status || [[ -d /sys/kernel/security/apparmor ]]; then
    if have_cmd aa-status; then
      local aa
      aa="$(aa-status --enabled 2>/dev/null && echo enabled || echo disabled)"
      if [[ "$aa" == "enabled" ]] || aa-status >/dev/null 2>&1; then
        result PASS "AppArmor" "загружен (профили: $(aa-status 2>/dev/null | head -1))"
      else
        result WARN "AppArmor" "установлен, но не активен" "systemctl enable --now apparmor"
      fi
    else
      result INFO "AppArmor" "интерфейс ядра есть, утилиты aa-status нет"
    fi
  else
    result INFO "AppArmor" "не обнаружен (на RHEL обычно SELinux — исключён из скрипта)"
  fi
}

# =============================================================================
# Категория: логирование / audit
# =============================================================================
check_logging() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "logging" ]] && return 0
  section "Логирование и аудит"

  if service_active rsyslog || service_active syslog-ng || \
     service_active systemd-journald || [[ -d /run/log/journal || -d /var/log/journal ]] || \
     have_cmd journalctl; then
    if service_active rsyslog || service_active syslog-ng; then
      result PASS "Системный лог" "rsyslog/syslog-ng активен"
    elif have_cmd journalctl && journalctl -n 1 >/dev/null 2>&1; then
      result PASS "Системный лог" "systemd-journald доступен"
    else
      result PASS "Системный лог" "journal присутствует"
    fi
  else
    result WARN "Системный лог" "не удалось подтвердить активный логгер"
  fi

  if have_cmd auditctl || [[ -f /etc/audit/auditd.conf ]]; then
    if service_active auditd; then
      result PASS "auditd" "активен"
    else
      result WARN "auditd" "установлен, но не запущен" \
        "systemctl enable --now auditd"
      if confirm_fix "Включить auditd"; then
        [[ $DRY_RUN -eq 0 ]] && systemctl enable --now auditd 2>/dev/null || true
        result FIXED "auditd" "попытка включения выполнена"
      fi
    fi
  else
    result WARN "auditd" "не установлен" \
      "apt install auditd / dnf install audit"
  fi

  # journal persistent
  if [[ -d /var/log/journal ]] || grep -qE '^Storage=persistent' /etc/systemd/journald.conf 2>/dev/null; then
    result PASS "journald persistent" "похоже настроено"
  else
    result INFO "journald persistent" "Storage=persistent в /etc/systemd/journald.conf для сохранения логов"
  fi

  # logrotate
  if have_cmd logrotate || [[ -d /etc/logrotate.d ]]; then
    result PASS "logrotate" "присутствует"
  else
    result WARN "logrotate" "не найден — логи могут забить диск"
  fi
}

# =============================================================================
# Категория: обновления
# =============================================================================
check_updates() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "updates" ]] && return 0
  section "Обновления безопасности"

  case "$DISTRO_FAMILY" in
    debian)
      if [[ -d /etc/apt/apt.conf.d ]]; then
        if grep -rqE 'Unattended-Upgrade|APT::Periodic::Update-Package-Lists.*"1"' \
            /etc/apt/apt.conf.d 2>/dev/null; then
          result PASS "Автообновления (Debian/Ubuntu)" "unattended-upgrades / APT Periodic намечены"
        else
          result WARN "Автообновления (Debian/Ubuntu)" "не видно включённых unattended-upgrades" \
            "apt install unattended-upgrades && dpkg-reconfigure -plow unattended-upgrades"
          if confirm_fix "Установить и включить unattended-upgrades"; then
            if [[ $DRY_RUN -eq 0 && $EUID -eq 0 ]]; then
              export DEBIAN_FRONTEND=noninteractive
              apt-get update -qq 2>/dev/null || true
              apt-get install -y -qq unattended-upgrades 2>/dev/null || true
              echo 'APT::Periodic::Update-Package-Lists "1";' >/etc/apt/apt.conf.d/20auto-upgrades
              echo 'APT::Periodic::Unattended-Upgrade "1";' >>/etc/apt/apt.conf.d/20auto-upgrades
            fi
            result FIXED "unattended-upgrades" "установка/включение запрошены"
          fi
        fi
      fi
      ;;
    rhel)
      if have_cmd dnf; then
        if systemctl list-unit-files 'dnf-automatic*' 2>/dev/null | grep -q dnf-automatic; then
          if service_enabled dnf-automatic.timer || service_enabled dnf-automatic-install.timer; then
            result PASS "dnf-automatic" "таймер включён"
          else
            result WARN "dnf-automatic" "пакет есть, таймер выключен" \
              "systemctl enable --now dnf-automatic.timer"
          fi
        else
          result WARN "dnf-automatic" "не установлен" "dnf install dnf-automatic"
        fi
      elif have_cmd yum-cron || [[ -f /etc/yum/yum-cron.conf ]]; then
        result INFO "yum-cron" "проверьте конфигурацию /etc/yum/yum-cron.conf"
      fi
      ;;
    suse)
      if have_cmd zypper; then
        result INFO "Обновления SUSE" "проверьте: systemctl status rebootmgr / transactional-update"
      fi
      ;;
    arch)
      result INFO "Arch" "автообновления обычно не ставят — следите вручную / через systemd timer"
      ;;
    *)
      result INFO "Обновления" "проверьте политику обновлений вашего дистрибутива"
      ;;
  esac

  # reboot required
  if [[ -f /var/run/reboot-required ]]; then
    result WARN "Требуется перезагрузка" "$(cat /var/run/reboot-required.pkgs 2>/dev/null | tr '\n' ' ')" \
      "reboot после установки обновлений ядра"
  else
    result INFO "reboot-required" "флаг не установлен (или не Debian-like)"
  fi
}

# =============================================================================
# Категория: kernel / модули / mounts / core dumps
# =============================================================================
check_kernel_misc() {
  [[ -n "$ONLY_CATEGORY" && "$ONLY_CATEGORY" != "kernel" && "$ONLY_CATEGORY" != "misc" ]] && return 0
  section "Ядро, mounts, core dumps, прочее"

  # Core dumps
  local core
  core="$(ulimit -c 2>/dev/null || echo '?')"
  if [[ "$core" == "0" ]]; then
    result PASS "ulimit core (текущая сессия)" "0"
  else
    result WARN "ulimit core" "$core (рекомендуется 0 на серверах)" \
      "В limits.conf: * hard core 0"
  fi
  if [[ -f /etc/security/limits.conf ]]; then
    if grep -qE '^[^#]*[[:space:]]core[[:space:]]+0' /etc/security/limits.conf \
       || grep -rqE 'core[[:space:]]+0' /etc/security/limits.d 2>/dev/null; then
      result PASS "limits.conf core" "ограничение задано"
    else
      result WARN "limits.conf core" "нет явного hard core 0" \
        "echo '* hard core 0' >> /etc/security/limits.d/99-security.conf"
      if confirm_fix "Добавить * hard core 0"; then
        if [[ $DRY_RUN -eq 0 ]]; then
          mkdir -p /etc/security/limits.d
          echo '* hard core 0' >/etc/security/limits.d/99-security-audit.conf
        fi
        result FIXED "core dumps" "hard core 0"
      fi
    fi
  fi

  # coredump.conf
  if [[ -f /etc/systemd/coredump.conf ]]; then
    if grep -qE '^Storage=none' /etc/systemd/coredump.conf; then
      result PASS "systemd-coredump Storage" "none"
    else
      result INFO "systemd-coredump" "Storage не none — для серверов можно отключить"
    fi
  fi

  # Dangerous mounts options for /tmp /dev/shm
  check_mount_opts() {
    local mp="$1"; shift
    local need=("$@")
    local opts
    opts="$(findmnt -n -o OPTIONS "$mp" 2>/dev/null || true)"
    if [[ -z "$opts" ]]; then
      result SKIP "mount $mp" "не смонтирован / findmnt недоступен"
      return
    fi
    local missing=()
    local n
    for n in "${need[@]}"; do
      [[ "$opts" == *"$n"* ]] || missing+=("$n")
    done
    if [[ ${#missing[@]} -eq 0 ]]; then
      result PASS "mount $mp" "$opts"
    else
      result WARN "mount $mp" "нет опций: ${missing[*]} (сейчас: $opts)" \
        "В fstab: $mp ... defaults,${missing[*]}"
    fi
  }
  check_mount_opts /tmp nosuid nodev
  check_mount_opts /dev/shm nosuid nodev noexec
  check_mount_opts /home nodev

  # USB storage blacklist — optional
  if lsmod 2>/dev/null | grep -q '^usb_storage'; then
    result INFO "usb_storage" "модуль загружен — для киосков можно blacklist'ить"
  else
    if [[ -f /etc/modprobe.d/blacklist-usb-storage.conf ]] || \
       grep -rq 'usb-storage' /etc/modprobe.d 2>/dev/null; then
      result PASS "usb_storage" "похоже заблокирован"
    else
      result INFO "usb_storage" "не загружен / не проверен"
    fi
  fi

  # CRAMFS / freevxfs и др. редко нужные ФС
  local uncommon=(cramfs freevxfs jffs2 hfs hfsplus squashfs udf)
  # squashfs часто нужен — только info
  result INFO "Редкие ФС" "при hardened-профиле blacklist: cramfs freevxfs jffs2 hfs hfsplus udf"

  # SUID sample — известные опасные
  if [[ $EUID -eq 0 ]]; then
    local suid_unusual
    suid_unusual="$(find /usr /bin /sbin -xdev -type f \( -perm -4000 -o -perm -2000 \) 2>/dev/null \
      | grep -Eiv 'sudo|su|passwd|ping|mount|umount|chfn|chsh|newgrp|gpasswd|pkexec|ssh-keysign|ssh-agent|crontab|ntfs|fusermount|expiry|chage|unix_chkpwd|pam_extrausers|dotlock|locale|write|wall|staprun|sg|ksu|Xorg|nvidia|chrome|chromium|firejail|snap|utempter|polkit|dbus-daemon-launch|unix_update|restrict_user|vmware|virtualbox|qemu|schroot|bsd-write|pt_chown' \
      | head -15)"
    if [[ -z "$suid_unusual" ]]; then
      result PASS "Необычные SUID/SGID" "подозрительных в выборке нет"
    else
      result WARN "Необычные SUID/SGID (выборка)" "$(echo "$suid_unusual" | tr '\n' ' ')" \
        "Проверьте необходимость; chmod u-s FILE"
    fi
  fi

  # Cron allow/deny
  if [[ -f /etc/cron.allow ]]; then
    result PASS "cron.allow" "существует (whitelist)"
  elif [[ -f /etc/cron.deny ]]; then
    result INFO "cron.deny" "существует — предпочтительнее cron.allow whitelist"
  else
    result INFO "cron allow/deny" "нет ограничений — любой пользователь может иметь crontab"
  fi

  # Legal banner
  if [[ -s /etc/issue.net ]] || [[ -s /etc/motd ]]; then
    result INFO "Banner/MOTD" "есть содержимое — добавьте юридическое предупреждение при необходимости"
  else
    result INFO "Banner/MOTD" "пустые — для серверов рекомендуется /etc/issue.net + Banner в sshd"
  fi

  # Automount / autofs
  if service_active autofs 2>/dev/null; then
    result INFO "autofs" "активен — убедитесь в необходимости"
  fi
}

# =============================================================================
# Сводка рекомендаций
# =============================================================================
print_summary() {
  section "Итог"
  log "${C_GREEN}PASS : $PASS_COUNT${C_RESET}"
  log "${C_YELLOW}WARN : $WARN_COUNT${C_RESET}"
  log "${C_RED}FAIL : $FAIL_COUNT${C_RESET}"
  log "${C_BLUE}INFO : $INFO_COUNT${C_RESET}"
  log "${C_DIM}SKIP : $SKIP_COUNT${C_RESET}"
  [[ $FIXED_COUNT -gt 0 ]] && log "${C_GREEN}FIXED: $FIXED_COUNT${C_RESET}"
  echo
  log "Отчёт: ${C_BOLD}$REPORT_FILE${C_RESET}"
  [[ -d "${REPORT_DIR}/backups" ]] && log "Бэкапы: ${REPORT_DIR}/backups/"
  echo
  if [[ $FAIL_COUNT -gt 0 || $WARN_COUNT -gt 0 ]]; then
    log "${C_BOLD}Что сделать дальше:${C_RESET}"
    log "  1. Просмотрите FAIL/WARN выше и в отчёте."
    log "  2. Примените безопасные правки:"
    log "       sudo $SCRIPT_NAME --fix"
    log "  3. Для бездиалогового прогона (после проверки ключей SSH!):"
    log "       sudo $SCRIPT_NAME --fix --yes"
    log "  4. Сначала посмотрите изменения без записи:"
    log "       sudo $SCRIPT_NAME --fix --dry-run"
  else
    log "${C_GREEN}Критических замечаний нет по пройденным проверкам.${C_RESET}"
  fi
  {
    echo
    echo "SUMMARY: PASS=$PASS_COUNT WARN=$WARN_COUNT FAIL=$FAIL_COUNT INFO=$INFO_COUNT SKIP=$SKIP_COUNT FIXED=$FIXED_COUNT"
  } >>"$REPORT_FILE"
}

# =============================================================================
# main
# =============================================================================
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -a|--audit) FIX_MODE=0; shift ;;
      -f|--fix) FIX_MODE=1; shift ;;
      -y|--yes) AUTO_YES=1; shift ;;
      -n|--dry-run) DRY_RUN=1; shift ;;
      -q|--quiet) QUIET=1; shift ;;
      -c|--category) ONLY_CATEGORY="${2:-}"; shift 2 ;;
      -o|--output) REPORT_DIR="${2:-}"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      -V|--version) echo "$AUDIT_VERSION"; exit 0 ;;
      *) echo "Неизвестная опция: $1"; usage; exit 1 ;;
    esac
  done
}

main() {
  parse_args "$@"
  mkdir -p "$REPORT_DIR/backups"
  REPORT_FILE="${REPORT_DIR}/report-$(date +%Y%m%d-%H%M%S).txt"

  detect_os
  {
    echo "Linux Security Audit $AUDIT_VERSION"
    echo "Host: $(hostname)  Date: $(date -Is)"
    echo "OS: $OS_NAME  Family: $DISTRO_FAMILY"
    echo "Mode: $([[ $FIX_MODE -eq 1 ]] && echo FIX || echo AUDIT) dry_run=$DRY_RUN"
    echo
  } >"$REPORT_FILE"

  log "${C_BOLD}Linux Security Audit ${AUDIT_VERSION}${C_RESET}"
  log "Режим: $([[ $FIX_MODE -eq 1 ]] && echo "аудит + исправления" || echo "только аудит")$([[ $DRY_RUN -eq 1 ]] && echo " [dry-run]")"
  log "Исключено: firewall, SELinux"

  if [[ $FIX_MODE -eq 1 && $EUID -ne 0 ]]; then
    log "${C_RED}Для --fix нужны права root (sudo).${C_RESET}"
    exit 2
  fi

  check_system_info
  check_ssh
  check_auth
  check_accounts
  check_perms
  check_sysctl
  check_services
  check_logging
  check_updates
  check_kernel_misc
  print_summary

  # Код выхода: 0 = нет FAIL, 1 = есть FAIL, 2 = ошибка запуска
  [[ $FAIL_COUNT -eq 0 ]] && exit 0 || exit 1
}

main "$@"
