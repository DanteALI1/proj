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

```bash
mkdir -p /opt/share
```

Применяем права (аналог `nobody:nogroup` из Astra; в РЕД ОС / RHEL-подобных системах группа обычно `nobody`):

```bash
chown nobody:nobody /opt/share
chmod 777 /opt/share
```

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
/opt/share <IP-клиента>(rw,nohide,all_squash,anonuid=1000,anongid=1000,no_subtree_check)
```

Пример (клиент = шлюз доступа):

```text
/opt/share 10.0.31.136(rw,nohide,all_squash,anonuid=1000,anongid=1000,no_subtree_check)
```

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
| `subtree_check` | проверка, что клиент обращается только к файлам внутри экспортируемого поддерева (безопаснее, чуть медленнее; по умолчанию в классическом NFS) |
| `no_subtree_check` | отключение контроля поддерева (быстрее; допустимо, если экспорт совпадает с целым разделом диска) |

В данном примере публикуется `/opt/share` на машине с РЕД ОС 8 и IP `10.0.128.248`, а обращаться будут из другой подсети `10.0.XX.XX`.

Если используете `anonuid=1000` / `anongid=1000`, убедитесь, что на сервере существует пользователь/группа с этими ID, либо выровняйте владельца каталога:

```bash
# опционально, если UID/GID 1000 уже есть
chown 1000:1000 /opt/share
chmod 777 /opt/share
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

# 2. Каталог
mkdir -p /opt/share
chown nobody:nobody /opt/share
chmod 777 /opt/share

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

# 4. Экспорт (пример для сети 10.0.0.0/16)
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
- `Permission denied` при записи → `anonuid`/`anongid` и права на `/opt/share`;
- зависание mount → сеть между подсетями, `rpcbind`, порты NFS.
