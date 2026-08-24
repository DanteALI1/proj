# Настройка Zabbix Agent на NFS-сервере (РЕД ОС 8)

Отдельная инструкция: установка и настройка **Zabbix Agent** на сервере NFS (`/opt/share`), чтобы Zabbix Server собирал метрики хоста и состояния NFS.

Все команды на NFS-сервере — от **root** (или через `sudo`).

> IP и имена ниже — **демонстрационные**. Подставьте свои.  
> Связанные инструкции: [настройка NFS](redos-8-nfs-setup.md) · [перенос данных](redos-8-nfs-migration.md).

---

## 1. Исходные данные

| Параметр | Значение (пример) |
|---|---|
| ОС | РЕД ОС 8 |
| Хост с агентом (NFS-сервер) | `172.16.40.10` |
| Имя хоста в Zabbix | `nfs-redos-01` |
| Zabbix Server | `172.16.40.20` |
| Порт агента (по умолчанию) | `10050/tcp` |
| Порт server (active checks) | `10051/tcp` |
| Конфиг агента | `/etc/zabbix/zabbix_agentd.conf` |
| Доп. конфиги | `/etc/zabbix/zabbix_agentd.d/*.conf` |
| Служба | `zabbix-agent.service` |
| Мониторируемая шара | `/opt/share` |

### Что делает агент

| Режим | Кто инициирует | Ключевые параметры в конфиге |
|---|---|---|
| **Passive** | Zabbix Server сам опрашивает агент на `10050` | `Server=` |
| **Active** | Агент сам забирает список проверок с сервера (`10051`) и отдаёт данные | `ServerActive=`, `Hostname=` |

Обычно настраивают **оба**: `Server` и `ServerActive`.

---

## 2. Этап 1. Установка репозитория и пакета

Версия агента должна быть **совместима** с версией вашего Zabbix Server (лучше та же major, например 6.0 / 6.4 / 7.0). Уточните версию на сервере Zabbix и на [странице загрузки](https://www.zabbix.com/download).

### 2.1. Пример для Zabbix 6.0 на RHEL/РЕД ОС 8

```bash
rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/8/x86_64/zabbix-release-latest.el8.noarch.rpm
dnf clean all
dnf install -y zabbix-agent
```

> Имя RPM репозитория может отличаться (`zabbix-release-6.0-4.el8...` и т.п.) — берите актуальный с сайта Zabbix под вашу версию и `RHEL 8`.

### 2.2. Если официальный репозиторий недоступен

Иногда агент есть в EPEL / зеркалах РЕД ОС:

```bash
dnf search zabbix-agent
dnf install -y zabbix-agent
# либо: dnf install -y zabbix6.0-agent
```

После установки проверьте путь к конфигу:

```bash
rpm -ql zabbix-agent | grep -E 'conf$'
ls -la /etc/zabbix/
```

Ожидается файл: **`/etc/zabbix/zabbix_agentd.conf`**.

---

## 3. Этап 2. Что менять в конфиге (подробно)

Файл:

```bash
cp -a /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.bak.$(date +%F)
nano /etc/zabbix/zabbix_agentd.conf
```

Ниже — **только те параметры, которые обычно нужно менять**. Остальное можно не трогать.

### 3.1. `Server=` — кто имеет право опрашивать агент (passive)

**Где:** секция около строки `# Server=` / `Server=127.0.0.1`

**Было (типично):**

```text
Server=127.0.0.1
```

**Стало:**

```text
Server=172.16.40.20
```

| Зачем | Смысл |
|---|---|
| Безопасность | Агент принимает passive-запросы **только** с этих IP |
| Несколько серверов/прокси | Через запятую: `Server=172.16.40.20,172.16.40.21` |

Если оставить `127.0.0.1`, Zabbix Server с другой машины **не сможет** опросить агент.

---

### 3.2. `ServerActive=` — куда агент ходит за active-проверками

**Где:** около `# ServerActive=` / `ServerActive=127.0.0.1`

**Было:**

```text
ServerActive=127.0.0.1
```

**Стало:**

```text
ServerActive=172.16.40.20
```

| Зачем | Смысл |
|---|---|
| Active checks | Агент подключается к Zabbix Server (порт **10051**) |
| Порт нестандартный | `ServerActive=172.16.40.20:10051` |

Если active не используете — можно закомментировать `#ServerActive=`, но чаще оставляют.

---

### 3.3. `Hostname=` — имя хоста в Zabbix

**Где:** около `Hostname=`

**Было (часто):**

```text
Hostname=Zabbix server
```

**Стало (обязательно своё уникальное имя):**

```text
Hostname=nfs-redos-01
```

| Важно | Почему |
|---|---|
| Должно **точно совпасть** | С полем *Host name* у хоста в веб-интерфейсе Zabbix (для active) |
| Регистр имеет значение | `NFS` ≠ `nfs` |
| Не путать с DNS | Это логическое имя в Zabbix, не обязательно FQDN |

В интерфейсе Zabbix при создании хоста:

- **Host name:** `nfs-redos-01` ← как в конфиге  
- **Visible name:** например `NFS РЕД ОС /opt/share`  
- **Interfaces → Agent:** IP `172.16.40.10`, port `10050`

---

### 3.4. `ListenPort=` — порт агента (по желанию)

**Где:** `# ListenPort=10050`

По умолчанию **10050**. Меняйте только если на сервере конфликт портов:

```text
ListenPort=10050
```

Если измените — укажите тот же порт в интерфейсе хоста Zabbix и в firewall.

---

### 3.5. `ListenIP=` — на каком адресе слушать (по желанию)

Если у NFS-сервера несколько IP и агент должен слушать только один:

```text
ListenIP=172.16.40.10
```

Иначе оставьте закомментированным (слушать на всех).

---

### 3.6. Логи (обычно не меняют)

```text
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=0
```

Смотреть лог:

```bash
tail -f /var/log/zabbix/zabbix_agentd.log
```

---

### 3.7. Пример минимального рабочего фрагмента

В `/etc/zabbix/zabbix_agentd.conf` после правок должны быть (среди прочего):

```text
PidFile=/var/run/zabbix/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=0

Server=172.16.40.20
ServerActive=172.16.40.20
Hostname=nfs-redos-01

Include=/etc/zabbix/zabbix_agentd.d/*.conf
```

Строка `Include=...` должна быть **раскомментирована**, если будете добавлять свои метрики NFS в отдельный файл (этап 5).

Проверка синтаксиса:

```bash
zabbix_agentd -t agent.ping
# или
zabbix_agentd -f -c /etc/zabbix/zabbix_agentd.conf   # только для теста, Ctrl+C
```

---

## 4. Этап 3. Firewall (firewalld)

На **NFS-сервере** разрешите входящие к агенту с Zabbix Server:

```bash
firewall-cmd --permanent --add-port=10050/tcp
# лучше ограничить источником:
firewall-cmd --permanent --remove-port=10050/tcp
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="172.16.40.20" port protocol="tcp" port="10050" accept'
firewall-cmd --reload
firewall-cmd --list-all
```

На **Zabbix Server** для active checks агент сам ходит на `10051` — порт `10051` должен быть открыт **на сервере Zabbix**, не на NFS.

| Направление | Порт | Где открывать |
|---|---|---|
| Server → Agent (passive) | `10050/tcp` | firewall **NFS-сервера** |
| Agent → Server (active) | `10051/tcp` | firewall **Zabbix Server** |

---

## 5. Этап 4. SELinux (если Enforcing)

```bash
getenforce
```

Если `Enforcing` и агент не стартует / не отвечает:

```bash
# разрешить агенту в сеть (часто нужно для active)
setsebool -P zabbix_can_network 1

# при кастомном порте агента (не 10050):
# dnf install -y policycoreutils-python-utils
# semanage port -a -t zabbix_agent_port_t -p tcp <порт>
```

Проверка AVC:

```bash
ausearch -m avc -ts recent | grep -i zabbix | tail
```

---

## 6. Этап 5. Доп. метрики для NFS (рекомендуется)

Чтобы не править основной конфиг каждый раз, создайте отдельный файл.

### 6.1. Создать файл

```bash
nano /etc/zabbix/zabbix_agentd.d/nfs_share.conf
```

### 6.2. Содержимое файла (что это значит)

```text
# Свободное место на шаре /opt/share (байты)
UserParameter=nfs.share.free,df -B1 --output=avail /opt/share | tail -1

# Размер ФС /opt/share (байты)
UserParameter=nfs.share.total,df -B1 --output=size /opt/share | tail -1

# Процент использования /opt/share
UserParameter=nfs.share.pused,df --output=pcent /opt/share | tail -1 | tr -dc '0-9'

# Смонтирован ли /opt/share (1=да, 0=нет)
UserParameter=nfs.share.mounted,findmnt -n /opt/share >/dev/null && echo 1 || echo 0

# Активен ли nfs-server (1=да, 0=нет)
UserParameter=nfs.service.active,systemctl is-active --quiet nfs-server && echo 1 || echo 0

# Число строк экспорта (грубая проверка, что exports не пустой)
UserParameter=nfs.exports.count,exportfs -s 2>/dev/null | wc -l
```

| Ключ (Item key в Zabbix) | Что показывает |
|---|---|
| `nfs.share.free` | Свободно байт на `/opt/share` |
| `nfs.share.total` | Размер тома |
| `nfs.share.pused` | Занято, % |
| `nfs.share.mounted` | 1 если шара смонтирована |
| `nfs.service.active` | 1 если `nfs-server` active |
| `nfs.exports.count` | Сколько экспортов видно через `exportfs -s` |

> Пользователь службы `zabbix` должен иметь право выполнять эти команды. `df`/`findmnt`/`systemctl is-active` обычно доступны; для `exportfs` иногда нужен sudoers — если ключ не работает, см. этап 8.

В основном конфиге должна быть строка:

```text
Include=/etc/zabbix/zabbix_agentd.d/*.conf
```

---

## 7. Этап 6. Запуск службы

```bash
systemctl enable --now zabbix-agent
systemctl restart zabbix-agent
systemctl status zabbix-agent
ss -tlnp | grep 10050
```

Ожидается: `active (running)`, порт `10050` слушается.

---

## 8. Этап 7. Настройка хоста в веб-интерфейсе Zabbix

На Zabbix Server (UI):

1. **Configuration → Hosts → Create host**
2. **Host name:** `nfs-redos-01` ← **как в** `Hostname=`
3. **Groups:** например `Linux servers` / `NFS`
4. **Interfaces:** Type **Agent**, IP `172.16.40.10`, Port `10050`
5. **Templates:** минимум  
   - `Linux by Zabbix agent` (или `Linux by Zabbix agent active`)  
6. Сохранить.

Дополнительно создайте Items (или шаблон) с ключами:

- `nfs.share.pused`
- `nfs.share.mounted`
- `nfs.service.active`
- …

Тип: **Zabbix agent** (passive) или **Zabbix agent (active)** — в зависимости от того, как настроены `Server` / `ServerActive` и шаблон.

Триггеры (примеры идей):

- `nfs.share.mounted = 0` — шара не смонтирована  
- `nfs.service.active = 0` — NFS-сервис упал  
- `nfs.share.pused > 90` — мало места на `/opt/share`

---

## 9. Этап 8. Проверка, что всё работает

### На NFS-сервере

```bash
# локальный тест ключей
zabbix_agentd -t agent.ping
zabbix_agentd -t vfs.fs.size[/opt/share,pfree]
zabbix_agentd -t nfs.share.mounted
zabbix_agentd -t nfs.service.active
zabbix_agentd -t nfs.share.pused

tail -50 /var/log/zabbix/zabbix_agentd.log
```

Ожидается `agent.ping` → `1`, кастомные ключи без ошибки `[m|ZBX_NOTSUPPORTED]`.

### С Zabbix Server

```bash
# пакет zabbix-get на сервере Zabbix
zabbix_get -s 172.16.40.10 -p 10050 -k agent.ping
zabbix_get -s 172.16.40.10 -p 10050 -k nfs.share.mounted
```

В UI: **Monitoring → Latest data** → хост `nfs-redos-01` — должны появиться данные (через 1–2 интервала опроса).

---

## 10. Чеклист «с нуля»

```bash
# на NFS 172.16.40.10
rpm -Uvh https://repo.zabbix.com/zabbix/6.0/rhel/8/x86_64/zabbix-release-latest.el8.noarch.rpm
dnf clean all
dnf install -y zabbix-agent

cp -a /etc/zabbix/zabbix_agentd.conf /etc/zabbix/zabbix_agentd.conf.bak
# в conf:
#   Server=172.16.40.20
#   ServerActive=172.16.40.20
#   Hostname=nfs-redos-01
#   Include=/etc/zabbix/zabbix_agentd.d/*.conf

cat > /etc/zabbix/zabbix_agentd.d/nfs_share.conf <<'EOF'
UserParameter=nfs.share.free,df -B1 --output=avail /opt/share | tail -1
UserParameter=nfs.share.total,df -B1 --output=size /opt/share | tail -1
UserParameter=nfs.share.pused,df --output=pcent /opt/share | tail -1 | tr -dc '0-9'
UserParameter=nfs.share.mounted,findmnt -n /opt/share >/dev/null && echo 1 || echo 0
UserParameter=nfs.service.active,systemctl is-active --quiet nfs-server && echo 1 || echo 0
UserParameter=nfs.exports.count,exportfs -s 2>/dev/null | wc -l
EOF

firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="172.16.40.20" port protocol="tcp" port="10050" accept'
firewall-cmd --reload
setsebool -P zabbix_can_network 1

systemctl enable --now zabbix-agent
systemctl restart zabbix-agent
zabbix_agentd -t agent.ping
zabbix_agentd -t nfs.share.mounted
```

Затем в UI Zabbix создайте хост `nfs-redos-01` с IP `172.16.40.10`.

---

## 11. Типовые проблемы

| Симптом | Что проверить |
|---|---|
| Host not available / красный агент | firewall `10050`, `Server=` на агенте = IP Zabbix, SELinux, `systemctl status zabbix-agent` |
| Active checks не идут | `ServerActive=`, `Hostname=` = Host name в UI, на Zabbix открыт `10051` |
| `ZBX_NOTSUPPORTED` на UserParameter | опечатка в ключе, нет `Include=`, перезапуск агента после правки `.d/*.conf` |
| `exportfs` / systemctl denied | права пользователя `zabbix`, sudoers или упростить ключ |
| Путаница имени | `Hostname` в conf ≠ Host name в UI |
| Не тот репозиторий | версия агента сильно отличается от server |

Логи:

```bash
journalctl -u zabbix-agent -xe
tail -100 /var/log/zabbix/zabbix_agentd.log
```

---

## 12. Что не нужно путать

| Тема | Файл / порт |
|---|---|
| SSH (у вас мог быть порт `2242`) | `/etc/ssh/sshd_config` — **не** относится к Zabbix |
| NFS export | `/etc/exports` |
| Zabbix Agent | `/etc/zabbix/zabbix_agentd.conf` + порт **10050** |

---

## 13. Итог

| Компонент | Значение |
|---|---|
| Агент на | NFS `172.16.40.10` |
| Конфиг | `/etc/zabbix/zabbix_agentd.conf` |
| Обязательно изменить | `Server`, `ServerActive`, `Hostname` |
| Доп. NFS-метрики | `/etc/zabbix/zabbix_agentd.d/nfs_share.conf` |
| В Zabbix UI | хост `nfs-redos-01`, IP `172.16.40.10:10050` |

---

*Инструкция для РЕД ОС 8 (RHEL-совместимая установка пакетов Zabbix). Версию репозитория выбирайте под ваш Zabbix Server.*
