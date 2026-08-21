# Настройка и подключение удалённого хранилища NFS в РЕД ОС 8

Полная инструкция по развёртыванию NFS-сервера и подключению NFS-клиента на **РЕД ОС 8** (Рабочая станция, Сервер графический, Сервер минимальный).

Актуальные пакеты (ориентир по базе знаний РЕД ОС): `nfs-utils`, `nfs4-acl-tools`, при необходимости `autofs`.

---

## 1. Что такое NFS и когда его использовать

**NFS (Network File System)** — сетевой протокол, позволяющий монтировать каталоги с удалённого сервера и работать с ними как с локальными.

**Плюсы:**
- централизованное хранение данных;
- один раз разместили файлы на сервере — доступны всем клиентам;
- экономия места на дисках клиентов;
- прозрачная работа для приложений и пользователей.

**Важно по безопасности:**
- NFS по умолчанию **не шифрует** трафик;
- аутентификация пользователей как в Samba/CIFS обычно не выполняется — доступ ограничивается **IP/хостами** и опциями экспорта;
- для недоверенных сетей используйте VPN, изолированную VLAN или NFSv4 + Kerberos.

---

## 2. Подготовка

### На обеих машинах (сервер и клиент)

1. Узнайте IP-адреса:

```bash
ip -br a
hostname -I
```

2. Проверьте доступность по сети:

```bash
ping -c 3 <IP_сервера>
```

3. Обновите кэш репозиториев (по желанию — и систему):

```bash
sudo dnf makecache
# при необходимости:
# sudo dnf update
```

В примерах ниже:
- **сервер:** `192.168.114.63`
- **клиент:** `192.168.114.172`
- **экспорт:** `/srv/nfs/share`
- **точка монтирования на клиенте:** `/media/nfs_share`

Подставьте свои значения.

---

## 3. Настройка NFS-сервера (РЕД ОС 8)

### 3.1. Установка пакетов и запуск службы

```bash
sudo dnf install -y nfs-utils nfs4-acl-tools
sudo systemctl enable --now nfs-server.service
sudo systemctl status nfs-server.service
```

Ожидаемый статус: `active (exited)` или `active (running)` — зависит от версии; главное, что unit включён и без ошибок.

### 3.2. Создание каталога для экспорта

Рекомендуется выделить отдельный каталог, например `/srv/nfs/share`:

```bash
sudo mkdir -p /srv/nfs/share
sudo chown -R nobody:nobody /srv/nfs/share
sudo chmod 0775 /srv/nfs/share
```

Пояснения:
- `nobody:nobody` — удобно в паре с `root_squash` / `all_squash`;
- если нужен конкретный владелец (например, пользователь с UID/GID `1000`):

```bash
sudo chown -R 1000:1000 /srv/nfs/share
sudo chmod 0775 /srv/nfs/share
```

### 3.3. Конфигурация `/etc/exports`

Основной файл сервера — `/etc/exports`. Изначально он пуст.

**Правила оформления:**
- один экспорт — одна строка;
- между адресом клиента и `(` **не должно быть пробела**;
- опции через запятую **без пробелов**;
- несколько клиентов — через пробел;
- комментарии — после `#`.

Формат:

```text
/<путь_к_каталогу> <клиент>(<опции>) [<клиент>(<опции>) ...]
```

Откройте файл:

```bash
sudo nano /etc/exports
```

#### Пример: доступ одной машине с записью

```text
/srv/nfs/share 192.168.114.172(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000)
```

#### Пример: доступ всей подсети

```text
/srv/nfs/share 192.168.114.0/24(rw,sync,no_subtree_check,root_squash)
```

#### Пример: только чтение для всех в подсети

```text
/srv/nfs/share 192.168.114.0/24(ro,sync,no_subtree_check,root_squash)
```

#### Пример: несколько клиентов с разными правами

```text
/srv/nfs/share 192.168.114.172(rw,sync,no_subtree_check) 192.168.114.180(ro,sync,no_subtree_check)
```

### 3.4. Основные опции экспорта

| Опция | Назначение |
|---|---|
| `ro` | только чтение |
| `rw` | чтение и запись |
| `sync` | запись на диск до подтверждения клиенту (надёжнее, медленнее) |
| `async` | буферизация в памяти (быстрее, риск потери данных при сбое) |
| `no_subtree_check` | без проверки прав на каждом уровне вложенности (обычно рекомендуется) |
| `subtree_check` | проверка прав и у подкаталогов |
| `root_squash` | root клиента → nobody на сервере (**по умолчанию**, безопаснее) |
| `no_root_squash` | root клиента остаётся root на сервере (**не рекомендуется**) |
| `all_squash` | все пользователи клиента → анонимный пользователь |
| `anonuid=` / `anongid=` | UID/GID анонимного пользователя вместо nobody |

Клиент можно указать как:
- IP: `192.168.114.172`
- подсеть: `192.168.114.0/24` или `192.168.114.0/255.255.255.0`
- FQDN / hostname
- шаблон: `*.example.local`
- `*` — всем (только в доверенной изолированной сети)

Справка:

```bash
man exports
```

### 3.5. Применение экспорта

```bash
sudo exportfs -rav
sudo exportfs -v
```

Или:

```bash
sudo systemctl restart nfs-server.service
```

Проверка списка экспортов на самом сервере:

```bash
sudo exportfs -s
showmount -e localhost
```

### 3.6. Firewall (firewalld)

Если firewall включён:

```bash
sudo systemctl status firewalld
```

Откройте необходимые службы и перезагрузите правила:

```bash
sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload
sudo firewall-cmd --list-services
```

Для ограниченного доступа только с подсети клиентов (рекомендуется):

```bash
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.114.0/24" service name="nfs" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.114.0/24" service name="mountd" accept'
sudo firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="192.168.114.0/24" service name="rpc-bind" accept'
sudo firewall-cmd --reload
```

### 3.7. SELinux (если включён Enforcing)

Проверка режима:

```bash
getenforce
```

Если каталог экспорта нестандартный, может потребоваться контекст:

```bash
sudo semanage fcontext -a -t nfs_t "/srv/nfs(/.*)?"
sudo restorecon -Rv /srv/nfs
```

Разрешить NFS экспортировать любые каталоги (при необходимости):

```bash
sudo setsebool -P nfs_export_all_rw 1
```

Пакет для `semanage` (если нет):

```bash
sudo dnf install -y policycoreutils-python-utils
```

---

## 4. Настройка NFS-клиента (РЕД ОС 8)

### 4.1. Установка и запуск

```bash
sudo dnf install -y nfs-utils
sudo systemctl enable --now nfs-client.target
```

### 4.2. Проверка доступности экспорта

```bash
showmount -e 192.168.114.63
```

Пример ответа:

```text
Export list for 192.168.114.63:
/srv/nfs/share 192.168.114.172
```

Если команда не отвечает — проверьте сеть, firewall на сервере и статус `nfs-server`.

---

## 5. Подключение хранилища на клиенте

Есть три основных способа.

### 5.1. Ручное монтирование (для проверки)

```bash
sudo mkdir -p /media/nfs_share
sudo mount -t nfs 192.168.114.63:/srv/nfs/share /media/nfs_share
```

Проверка:

```bash
mount | grep nfs
df -h /media/nfs_share
ls -la /media/nfs_share
```

Проверка записи:

```bash
echo "NFS OK $(date)" | sudo tee /media/nfs_share/test.txt
cat /media/nfs_share/test.txt
```

Отмонтирование:

```bash
sudo umount /media/nfs_share
```

**Важно:** после перезагрузки ручной mount пропадает.

Полезные опции монтирования:

```bash
sudo mount -t nfs -o rw,hard,timeo=600,retrans=2,rsize=1048576,wsize=1048576 \
  192.168.114.63:/srv/nfs/share /media/nfs_share
```

| Опция | Смысл |
|---|---|
| `hard` | при недоступности сервера операции ждут (для серверов/постоянных данных) |
| `soft` | операции могут завершиться ошибкой (удобнее для ноутбуков) |
| `intr` / `nointr` | возможность прерывания операций (зависит от версии NFS) |
| `vers=4` / `vers=4.2` | явная версия протокола |
| `rsize` / `wsize` | размер блоков чтения/записи |

Точки монтирования в `/media` обычно видны на рабочем столе и в файловых менеджерах (Nemo/Caja).

### 5.2. Автомонтирование через `/etc/fstab` (постоянное)

Создайте точку монтирования:

```bash
sudo mkdir -p /media/nfs_share
```

Добавьте строку в `/etc/fstab`:

```bash
sudo nano /etc/fstab
```

Минимальный вариант:

```text
192.168.114.63:/srv/nfs/share  /media/nfs_share  nfs  defaults  0  0
```

Практичный вариант для рабочих станций/серверов:

```text
192.168.114.63:/srv/nfs/share  /media/nfs_share  nfs  rw,_netdev,hard,timeo=600,retrans=2,x-systemd.automount  0  0
```

Пояснения:
- `_netdev` — монтировать после поднятия сети;
- `x-systemd.automount` — монтировать при первом обращении (снижает риск зависания при загрузке, если сервер недоступен).

Применить без перезагрузки:

```bash
sudo systemctl daemon-reload
sudo mount -a
# или:
sudo mount /media/nfs_share
```

Монтирование «по требованию» (не при старте ОС):

```text
192.168.114.63:/srv/nfs/share  /media/nfs_share  nfs  noauto,defaults  0  0
```

Затем:

```bash
sudo mount /media/nfs_share
sudo umount /media/nfs_share
```

**Замечание для ноутбуков:** если NFS в `fstab` без `_netdev`/`automount`/`autofs`, при недоступности сети возможны зависания при выключении/сне. Для ноутбуков предпочтительнее **autofs**.

### 5.3. Автомонтирование через `autofs` (по обращению)

Подходит, когда ресурс нужен не постоянно.

```bash
sudo dnf install -y autofs
sudo mkdir -p /media/nfs_share_autofs
```

В `/etc/auto.master` добавьте:

```text
/media/nfs_share_autofs  /etc/auto.nfs  timeout=120  -browse
```

Создайте `/etc/auto.nfs`:

```bash
sudo nano /etc/auto.nfs
```

Содержимое:

```text
server  -rw,soft,intr,rsize=8192,wsize=8192  192.168.114.63:/srv/nfs/share
```

Где:
- `server` — имя подкаталога, который появится в `/media/nfs_share_autofs/`;
- после обращения путь будет: `/media/nfs_share_autofs/server`.

Запуск:

```bash
sudo systemctl enable --now autofs
sudo systemctl restart autofs
```

Проверка:

```bash
ls /media/nfs_share_autofs/server
df -h /media/nfs_share_autofs/server
```

При отсутствии активности ресурс отмонтируется через заданный timeout.

Альтернативный вариант из документации РЕД ОС (корень `/nfs`):

```text
# /etc/auto.master
/nfs  /etc/auto.nfs  --timeout=60
```

```text
# /etc/auto.nfs
server  -rw,soft,intr,rsize=8192,wsize=8192  192.168.114.63:/srv/nfs/share
```

---

## 6. Типовой сценарий «с нуля» (краткий чеклист)

### На сервере

```bash
sudo dnf install -y nfs-utils nfs4-acl-tools
sudo mkdir -p /srv/nfs/share
sudo chown nobody:nobody /srv/nfs/share
sudo chmod 0775 /srv/nfs/share

echo '/srv/nfs/share 192.168.114.0/24(rw,sync,no_subtree_check,root_squash)' | sudo tee -a /etc/exports

sudo systemctl enable --now nfs-server.service
sudo exportfs -rav

sudo firewall-cmd --permanent --add-service=nfs
sudo firewall-cmd --permanent --add-service=mountd
sudo firewall-cmd --permanent --add-service=rpc-bind
sudo firewall-cmd --reload
```

### На клиенте

```bash
sudo dnf install -y nfs-utils
sudo systemctl enable --now nfs-client.target
showmount -e 192.168.114.63

sudo mkdir -p /media/nfs_share
echo '192.168.114.63:/srv/nfs/share  /media/nfs_share  nfs  defaults,_netdev  0  0' | sudo tee -a /etc/fstab
sudo mount -a
df -h /media/nfs_share
```

---

## 7. Диагностика и устранение проблем

### Службы на сервере

```bash
sudo systemctl status nfs-server.service
sudo systemctl status rpcbind.service
sudo journalctl -u nfs-server.service -xe
```

### Что экспортируется

```bash
sudo exportfs -v
showmount -e <IP_сервера>
```

### Сеть и порты

```bash
# с клиента
ping <IP_сервера>
rpcinfo -p <IP_сервера>
```

Типичные порты/службы: `nfs`, `mountd`, `rpcbind` (через firewalld-сервисы).

### Ошибки монтирования

| Симптом | Что проверить |
|---|---|
| `Connection refused` / timeout | firewall, `nfs-server`, сеть |
| `Access denied by server` | IP клиента в `/etc/exports`, `exportfs -rav` |
| `Permission denied` при записи | владельцы/права каталога, `root_squash`/`all_squash`/`anonuid` |
| Зависание при загрузке клиента | `_netdev`, `x-systemd.automount` или `autofs` |
| SELinux AVC | `ausearch -m avc -ts recent`, контекст `nfs_t`, boolean |

Проверка, что клиент видит ресурс с нужного IP:

```bash
ip -br a
# IP клиента должен попадать под правило в /etc/exports
```

Права на сервере после `root_squash`:
- локальный `root` на клиенте **не** имеет root-прав на сервере;
- для записи обычно нужны корректные `anonuid`/`anongid` или права каталога на `nobody`/нужную группу.

Пересоздание экспорта «с нуля»:

```bash
sudo exportfs -ua
sudo exportfs -rav
```

---

## 8. Рекомендации по безопасности и эксплуатации

1. **Не экспортируйте** `/` или домашние каталоги целиком без необходимости.
2. Ограничивайте доступ **конкретными IP/подсетями**, не используйте `*` в продакшене.
3. Оставляйте `root_squash` включённым; `no_root_squash` — только для осознанных служебных сценариев.
4. Держите NFS в **доверенной сети** или поверх VPN.
5. Делайте бэкапы каталога экспорта на сервере.
6. Для высокой нагрузки при необходимости настраивайте `rsize`/`wsize`, отдельный NIC, мониторинг диска и сети.
7. Для виртуализации (например, РЕД Вирт) не размещайте критичный NFS-сервер на том же хосте, который от него зависит как от storage domain.

---

## 9. Полезные команды (шпаргалка)

```bash
# сервер
sudo systemctl enable --now nfs-server
sudo exportfs -rav
sudo exportfs -v
showmount -e localhost

# клиент
showmount -e <IP_сервера>
sudo mount -t nfs <IP>:/путь /точка
mount | grep nfs
df -hT | grep nfs
sudo umount /точка

# firewall
sudo firewall-cmd --list-all
```

---

## 10. Ссылки на официальную документацию

- [Настройка NFS (база знаний РЕД ОС 8)](https://redos.red-soft.ru/base/redos-8_0/8_0-network/8_0-nfs/)
- [Подключение сетевых директорий с помощью NFS](https://redos.red-soft.ru/base/redos-8_0/8_0-administation/8_0-domain-redos/8_0-share/8_0-nfs-mount/)

---

*Инструкция ориентирована на РЕД ОС 8 и соответствует типовым практикам RHEL-совместимых систем с пакетом `nfs-utils`.*
