# Linux Security Audit

Универсальный скрипт аудита (и опционального hardening) настроек безопасности Linux.
Актуален для типичных серверных и desktop-дистрибутивов 2026 года.

**Не проверяет и не настраивает:** firewall, SELinux (по требованию).

## Что проверяется

| Категория | Примеры |
|-----------|---------|
| SSH | root login, PasswordAuthentication, MaxAuthTries, empty passwords, X11, PAM |
| Пароли / PAM | PASS_* в login.defs, UMASK, ENCRYPT_METHOD, pwquality, faillock, pam_wheel |
| Учётки | UID 0, пустые пароли в shadow, home permissions, sudo NOPASSWD |
| Права файлов | passwd/shadow/group/sshd_config, sticky bit /tmp, world-writable |
| Sysctl / сеть | rp_filter, redirects, source route, syncookies, ASLR, kptr_restrict, yama, BPF |
| Сервисы | telnet/rsh/ftp/nfs/avahi/cups/bluetooth, chrony, AppArmor |
| Логи | rsyslog/journald, auditd, logrotate |
| Обновления | unattended-upgrades, dnf-automatic, reboot-required |
| Прочее | core dumps, mount opts (/tmp, /dev/shm), SUID, cron.allow |

## Поддерживаемые ОС

Debian / Ubuntu / Mint, RHEL / Rocky / Alma / Fedora / Amazon Linux, openSUSE, Arch и другие systemd-дистрибутивы (часть проверок generic).

## Использование

```bash
chmod +x linux-security-audit.sh

# Только аудит (можно без root, но часть проверок будет SKIP)
sudo ./linux-security-audit.sh

# Аудит + интерактивные исправления
sudo ./linux-security-audit.sh --fix

# Посмотреть, что изменится, без записи
sudo ./linux-security-audit.sh --fix --dry-run

# Применить всё без вопросов (осторожно: отключит SSH по паролю!)
sudo ./linux-security-audit.sh --fix --yes

# Одна категория
sudo ./linux-security-audit.sh -c ssh
sudo ./linux-security-audit.sh -c sysctl --fix
```

Отчёт пишется в `/tmp/linux-security-audit/report-*.txt`.
Перед правками конфигов создаются бэкапы в `/tmp/linux-security-audit/backups/`.

## Важно

1. Перед `--fix` с отключением `PasswordAuthentication` убедитесь, что вход по SSH-ключу работает.
2. На роутерах/VPN `ip_forward=1` и часть sysctl — норма; скрипт помечает их как INFO.
3. AppArmor проверяется; SELinux намеренно пропущен.
4. Firewall (iptables/nftables/ufw/firewalld) намеренно пропущен.
