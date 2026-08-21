# Настройка NFS-сервера на РЕД ОС 8

Инструкция адаптирована с процедуры для Astra Linux 1.6 под РЕД ОС 8 (пакеты `nfs-utils`, служба `nfs-server`).

## Исходные данные

| Роль | Значение |
|---|---|
| Сервер NFS | Машина с **РЕД ОС 8**, IP `10.0.128.248` |
| Шлюз доступа | IP `10.0.31.136` |
| Экспортируемый каталог | `/opt/share` |
| Клиенты | из другой подсети `10.0.XX.XX` (обращение через шлюз/маршрутизацию) |

> В исходной схеме Astra Linux сервер был `10.0.128.248/16`. На РЕД ОС логика та же: публикуется `/opt/share`, к нему обращаются клиенты из другой подсети.

### Разметка дисков сервера (`df -T`)

Фактическая разметка на сервере РЕД ОС:

| Файловая система | Тип | Cмонтировано в | Свободно (ориентир) |
|---|---|---|---|
| `/dev/sda4` | ext4 | `/` | ~56 ГБ |
| `/dev/sda2` | ext4 | `/boot` | — |
| `/dev/sda5` | ext4 | `/home` | ~28 ГБ (почти пустой) |
| `/dev/sda1` | vfat | `/boot/efi` | — |
| tmpfs | tmpfs | `/tmp`, `/run`, … | не для хранения NFS |

**Выводы для NFS:**

1. Отдельного раздела под `/opt` **нет**. Каталог `/opt/share` будет лежать на корневом разделе `/` (`/dev/sda4`).
2. Экспорт `/opt/share` — это **часть раздела**, а не весь раздел целиком → для безопасности используйте **`subtree_check`**, а не `no_subtree_check`.
3. Места на `/` достаточно (~56 ГБ свободно при занятости ~5%).
4. Альтернатива: вынести шару на `/home` (`/dev/sda5`, ~28 ГБ свободно) — см. раздел ниже.
5. Наличие `/run/user/1000` означает, что в системе есть пользователь с **UID 1000** — опции `anonuid=1000,anongid=1000` к нему корректно привязываются.

Проверка у себя:

```bash
df -T
df -Th / /opt /home
findmnt / /opt /home
id 1000
```

---

## Настройка NFS на РЕД ОС 8

Все команды ниже выполняются от **root** (или через `sudo`).

### 1. Установка NFS-сервера

В РЕД ОС 8 аналог пакета `nfs-kernel-server` (Debian/Astra) — пакеты `nfs-utils` и при необходимости `nfs4-acl-tools`.  
`autofs` на сервере обычно не обязателен (он нужен клиенту для автомонтирования); ставим, если требуется по вашей схеме.

```bash
dnf install -y nfs-utils nfs4-acl-tools
dnf install -y autofs
```

> Установочный диск подключать не требуется, если настроены штатные репозитории РЕД ОС (`dnf repolist`).

### 2. Создание разделяемой директории

#### Вариант A (как в исходной инструкции Astra): `/opt/share`

Каталог окажется на корневом разделе `/dev/sda4` (~56 ГБ свободно):

```bash
mkdir -p /opt/share
df -Th /opt/share
```

Права (аналог `nobody:nogroup` из Astra; в РЕД ОС группа обычно `nobody`):

```bash
chown nobody:nobody /opt/share
chmod 777 /opt/share
```

Поскольку на сервере есть пользователь UID `1000`, предпочтительнее сразу привязать каталог к нему (совпадает с `anonuid`/`anongid` в exports):

```bash
chown 1000:1000 /opt/share
chmod 777 /opt/share
```

#### Вариант B (рекомендуется при большом объёме данных): `/home/share`

`/home` — отдельный раздел `/dev/sda5` (~28 ГБ свободно, почти не занят). Это удобнее, если NFS-данные не должны заполнять корневой `/`:

```bash
mkdir -p /home/share
chown 1000:1000 /home/share
chmod 777 /home/share
df -Th /home/share
```

Дальше в инструкции везде, где указано `/opt/share`, при варианте B подставьте `/home/share`.

> Даже на отдельном разделе `/home` каталог `/home/share` — это **подкаталог**, а не точка монтирования раздела целиком. Поэтому `subtree_check` всё равно предпочтителен. `no_subtree_check` допустим только если экспортируете весь раздел (например, сам `/home` как mountpoint) — так обычно **не** делают.

### 3. Зависимость NFS от rpcbind (аналог правки UNIT-файла)

В Astra правили symlink  
`/etc/systemd/system/multi-user.target.wants/nfs-server.service`  
и службу `nfs-kernel-server`.

В РЕД ОС 8:

- служба сервера: `nfs-server.service` (не `nfs-kernel-server`);
- symlink в `multi-user.target.wants` **нельзя править напрямую** — после `systemctl enable` / обновлений правки могут пропасть;
- корректный способ — drop-in override.

Создайте override:

```bash
mkdir -p /etc/systemd/system/nfs-server.service.d
nano /etc/systemd/system/nfs-server.service.d/override.conf
```

Содержимое файла:

```ini
[Unit]
Requires=rpcbind.service
After=rpcbind.service
```

Сохраните файл, затем:

```bash
systemctl daemon-reload
systemctl enable --now rpcbind.service
systemctl enable --now nfs-server.service
systemctl restart nfs-server.service
systemctl status nfs-server.service
```

### 4. Конфигурация экспорта `/etc/exports`

Конфигурация сервиса — файл `/etc/exports`.

```bash
nano /etc/exports
```

#### Для одного клиента

```text
/opt/share <IP-клиента>(rw,nohide,all_squash,anonuid=1000,anongid=1000,subtree_check)
```

Пример (клиент = шлюз доступа):

```text
/opt/share 10.0.31.136(rw,nohide,all_squash,anonuid=1000,anongid=1000,subtree_check)
```

> Для `/opt/share` на этой машине указан **`subtree_check`**: каталог лежит на общем разделе `/` (`/dev/sda4`), а не совпадает с отдельным разделом диска. В исходной Astra-инструкции для одного клиента стояло `no_subtree_check` — на данной разметке так делать не стоит.

#### Для сети

```text
/opt/share <IP-сети>/<маска>(rw,nohide,all_squash,anonuid=1000,anongid=1000,subtree_check)
```

Пример для сети `10.0.0.0/16` (как в исходной схеме с `/16`):

```text
/opt/share 10.0.0.0/16(rw,nohide,all_squash,anonuid=1000,anongid=1000,subtree_check)
```

Или в формате с десятичной маской:

```text
/opt/share 10.0.0.0/255.255.0.0(rw,nohide,all_squash,anonuid=1000,anongid=1000,subtree_check)
```

Пример для варианта B (`/home/share` на `/dev/sda5`):

```text
/home/share 10.0.0.0/16(rw,nohide,all_squash,anonuid=1000,anongid=1000,subtree_check)
```

**Важно:** между адресом клиента/сети и открывающей скобкой `(` пробела быть не должно.

### 5. Пояснение параметров доступа

`(rw,nohide,all_squash,anonuid=1000,anongid=1000,...)` — набор параметров доступа:

| Параметр | Назначение |
|---|---|
| `rw` | чтение и запись (`ro` — только чтение) |
| `nohide` | показывать нелокальные ресурсы (например, примонтированные через `mount --bind`); без неё NFS может их скрывать |
| `all_squash` | все подключения идут от анонимного пользователя |
| `anonuid=1000` | привязка анонимного пользователя к локальному UID `1000` |
| `anongid=1000` | привязка анонимного пользователя к локальной группе GID `1000` |
| `subtree_check` | проверка, что клиент обращается только к файлам внутри экспортируемого поддерева (безопаснее, чуть медленнее). **Нужен на этой машине**, т.к. `/opt/share` — часть раздела `/`, а не весь раздел |
| `no_subtree_check` | отключение контроля поддерева (быстрее). Допустимо **только** если экспортируемый каталог совпадает с отдельным разделом диска; для `/opt/share` на `/dev/sda4` — **не использовать** |

В данном примере публикуется `/opt/share` на машине с РЕД ОС 8 и IP `10.0.128.248`, а обращаться будут из другой подсети `10.0.XX.XX`.

Пользователь UID/GID `1000` на сервере уже есть (`/run/user/1000`). Выровняйте владельца каталога:

```bash
chown 1000:1000 /opt/share
chmod 777 /opt/share
id 1000
```

### 6. Применение изменений

После правок `/etc/exports`:

```bash
exportfs -ra
systemctl restart nfs-server.service
```

Проверка:

```bash
exportfs -v
showmount -e localhost
```

Ожидаемый результат — в списке экспортов есть `/opt/share`.

---

## Firewall (firewalld) — обязательно на РЕД ОС

В Astra часто открывают порты отдельно; в РЕД ОС 8 штатно используют `firewalld`.

```bash
systemctl status firewalld

firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-service=mountd
firewall-cmd --permanent --add-service=rpc-bind
firewall-cmd --reload
firewall-cmd --list-services
```

Ограничение только нужной сетью (рекомендуется):

```bash
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/16" service name="nfs" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/16" service name="mountd" accept'
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="10.0.0.0/16" service name="rpc-bind" accept'
firewall-cmd --reload
```

---

## SELinux (если включён)

```bash
getenforce
```

Если режим `Enforcing` и экспорт из `/opt/share` блокируется:

```bash
dnf install -y policycoreutils-python-utils
semanage fcontext -a -t nfs_t "/opt/share(/.*)?"
restorecon -Rv /opt/share
setsebool -P nfs_export_all_rw 1
```

---

## Подключение с клиента (кратко)

На клиенте (РЕД ОС / Linux):

```bash
dnf install -y nfs-utils
systemctl enable --now nfs-client.target

showmount -e 10.0.128.248

mkdir -p /mnt/share
mount -t nfs 10.0.128.248:/opt/share /mnt/share
df -h /mnt/share
```

Постоянное монтирование в `/etc/fstab`:

```text
10.0.128.248:/opt/share  /mnt/share  nfs  defaults,_netdev  0  0
```

---

## Соответствие команд Astra Linux → РЕД ОС 8

| Astra Linux 1.6 | РЕД ОС 8 |
|---|---|
| `apt install nfs-kernel-server` | `dnf install nfs-utils nfs4-acl-tools` |
| `apt install autofs` | `dnf install autofs` |
| `nobody:nogroup` | `nobody:nobody` |
| служба `nfs-kernel-server` | служба `nfs-server` |
| правка unit в `multi-user.target.wants/...` | drop-in `/etc/systemd/system/nfs-server.service.d/override.conf` |
| `/etc/exports` | `/etc/exports` (формат тот же) |
| `exportfs -ra` | `exportfs -ra` |
| `systemctl restart nfs-kernel-server.service` | `systemctl restart nfs-server.service` |

---

## Чеклист «с нуля» (копипаст)

```bash
# 1. Пакеты
dnf install -y nfs-utils nfs4-acl-tools

# 2. Каталог на корневом разделе / (/dev/sda4)
mkdir -p /opt/share
chown 1000:1000 /opt/share
chmod 777 /opt/share
df -Th /opt/share

# 3. Зависимость от rpcbind
mkdir -p /etc/systemd/system/nfs-server.service.d
cat > /etc/systemd/system/nfs-server.service.d/override.conf <<'EOF'
[Unit]
Requires=rpcbind.service
After=rpcbind.service
EOF
systemctl daemon-reload
systemctl enable --now rpcbind.service
systemctl enable --now nfs-server.service

# 4. Экспорт (subtree_check — т.к. /opt/share не отдельный раздел)
cat >> /etc/exports <<'EOF'
/opt/share 10.0.0.0/16(rw,nohide,all_squash,anonuid=1000,anongid=1000,subtree_check)
EOF
exportfs -ra
systemctl restart nfs-server.service

# 5. Firewall
firewall-cmd --permanent --add-service=nfs
firewall-cmd --permanent --add-service=mountd
firewall-cmd --permanent --add-service=rpc-bind
firewall-cmd --reload

# 6. Проверка
exportfs -v
showmount -e localhost
df -Th /opt/share
```

---

## Диагностика

```bash
systemctl status nfs-server.service rpcbind.service
journalctl -u nfs-server.service -xe
exportfs -v
showmount -e 10.0.128.248
rpcinfo -p 10.0.128.248
firewall-cmd --list-all
```

Типовые проблемы:
- клиент не видит экспорт → firewall / `exports` / маршрутизация через шлюз `10.0.31.136`;
- `Permission denied` при записи → `anonuid`/`anongid` и права на `/opt/share` (владелец `1000:1000`);
- зависание mount → сеть между подсетями, `rpcbind`, порты NFS;
- переполнение корня `/` → шара на `/opt/share` занимает место на `/dev/sda4`; при нехватке места перенесите данные на `/home/share` (`/dev/sda5`).

Контроль места на сервере:

```bash
df -Th / /opt/share /home
du -sh /opt/share
```
