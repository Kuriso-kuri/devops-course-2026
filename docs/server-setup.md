# Конфигурация виртуальной машины devops-vm

Документ описывает конфигурацию сервера `devops-vm` и порядок её восстановления
со снимка `01-clean-install`. Команды приведены в порядке выполнения.
Обозначения: **[Хост]** — Windows (PowerShell), **[VM]** — сервер.

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | Oracle VirtualBox 7.2.22 (Windows) |
| Имя | devops-vm |
| Гостевая ОС | Ubuntu Server 24.04.5 LTS (ядро 6.8.0-147), без LVM, ext4 на весь диск |
| Оперативная память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 25 ГБ, VDI, динамически расширяемый |
| EFI | выключен |

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Тип | Интерфейс в ВМ | Адрес | Назначение |
|---|---|---|---|---|
| 1 | NAT | enp0s3 | 10.0.2.15/24 (DHCP) | доступ в Интернет, вход по SSH через проброс портов |
| 2 | Host-only (VirtualBox Host-Only Ethernet Adapter, хост 192.168.56.1) | enp0s8 | 192.168.56.101/24 (DHCP) | прямой доступ с хоста по имени devops.local |

Проверка: `ip -brief address`.

### Имя узла и разрешение имён

```bash
# [VM]
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f                        # devops-vm.devops.local
```
[Хост] PowerShell от имени администратора (перед правкой — резервная копия):
```powershell
Copy-Item C:\Windows\System32\drivers\etc\hosts C:\Windows\System32\drivers\etc\hosts.bak
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "`r`n192.168.56.101 devops.local" -Encoding ascii
ipconfig /flushdns
```
Проверка: `ssh devops.local` — вход без пароля.

## 3. Правило проброса портов

Адаптер 1 → Дополнительно → Проброс портов:

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
|---|---|---|---|---|---|
| ssh | TCP | 127.0.0.1 | 2222 | — | **2222** |

> Снимок хранит и настройки ВМ: после отката на `01-clean-install` порт гостя снова равен **22**.
> Менять его на 2222 только после перезапуска sshd на новом порту (раздел 5).

## 4. Учётные записи

| Имя | Группы | Аутентификация по SSH |
|---|---|---|
| devops | devops, sudo | только ключ ed25519 `~/.ssh/devops_vm` (комментарий devops-vm-key) |
| student | student, sudo | вход по SSH запрещён (`AllowUsers devops`), только консоль |
| matvei | matvei, sudo | создан установщиком по ошибке; вход по SSH запрещён (`AllowUsers devops`) |

```bash
# [VM] (вход: ssh student@127.0.0.1 -p 2222)
sudo adduser devops
sudo usermod -aG sudo devops
groups devops                      # devops : devops sudo
```

Ключ (на хосте уже есть; создаётся один раз):
```powershell
# [Хост]
ssh-keygen -t ed25519 -C "devops-vm-key" -f $env:USERPROFILE\.ssh\devops_vm
```

Передача открытого ключа. Не через `type ... | ssh`: Windows PowerShell добавляет BOM и CRLF,
и sshd не распознаёт ключ. scp копирует файл байт в байт:
```powershell
# [Хост]
scp -P 2222 $env:USERPROFILE\.ssh\devops_vm.pub devops@127.0.0.1:key.pub
ssh -p 2222 devops@127.0.0.1 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat ~/key.pub >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && rm ~/key.pub"
```
Если ключ уже передан с BOM: `sed -i '1s/^\xEF\xBB\xBF//; s/\r$//' ~/.ssh/authorized_keys`.

Проверка: `ssh -i $env:USERPROFILE\.ssh\devops_vm -p 2222 devops@127.0.0.1` — без пароля;
`stat -c '%a %n' ~/.ssh ~/.ssh/authorized_keys` — 700 и 600.

Конфигурация клиента `C:\Users\Matvey\.ssh\config` (кодировка ASCII, без BOM):
```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

Основной файл `/etc/ssh/sshd_config` не изменяется (копия: `/etc/ssh/sshd_config.backup`).
Изменения — в `/etc/ssh/sshd_config.d/99-hardening.conf`. Текущую сессию не закрывать,
проверять в новом терминале.

| Директива | Значение |
|---|---|
| Port | 2222 |
| PermitRootLogin | no |
| PasswordAuthentication | no |
| PubkeyAuthentication | yes |
| PermitEmptyPasswords | no |
| MaxAuthTries | 3 |
| LoginGraceTime | 30 |
| AllowUsers | devops |
| X11Forwarding | no |
| ClientAliveInterval | 300 |
| ClientAliveCountMax | 2 |

```bash
# [VM]
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null <<'CONF'
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
CONF
# 50-cloud-init.conf содержит PasswordAuthentication yes и читается раньше (первое значение побеждает);
# файл доступен только root, поэтому grep — через sudo
sudo grep -r PasswordAuthentication /etc/ssh/sshd_config.d/
sudo sed -i 's/^PasswordAuthentication yes/#&/' /etc/ssh/sshd_config.d/50-cloud-init.conf

sudo sshd -t && echo OK
sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"

# Ubuntu 24.04: отказ от активации по сокету, иначе sshd слушает 22
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd          # 0.0.0.0:2222 и [::]:2222
```
Затем в VirtualBox: проброс `ssh`, порт гостя 22 → **2222** (раздел 3).
Проверка в новом терминале: `ssh devops` — успех; `ssh -p 2222 root@127.0.0.1` и
`ssh -p 2222 -o PubkeyAuthentication=no devops@127.0.0.1` — `Permission denied (publickey)`.

## 6. Правила межсетевого экрана

Политики: входящие — deny, исходящие — allow, маршрутизируемые — disabled. Журналирование — medium.

| Порт | Действие | Комментарий |
|---|---|---|
| 2222/tcp (+v6) | LIMIT IN | SSH rate-limited (блокировка источника при 6+ соединениях за 30 с) |
| 80/tcp (+v6) | ALLOW IN | HTTP (ПР № 6) |
| 443/tcp (+v6) | ALLOW IN | HTTPS (ПР № 6) |

Разрешающее правило для 2222 создаётся **до** `ufw enable`. `ufw allow ssh` не использовать — это порт 22 из `/etc/services`.
```bash
# [VM]
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw logging medium
sudo ufw --force enable
sudo ufw status verbose
```
Журнал блокировок: `/var/log/ufw.log` (записи `UFW BLOCK`).

## 7. Снимки состояния

| Снимок | Момент создания | Состояние |
|---|---|---|
| 01-clean-install | 28.10.2026 23:27, после установки и `apt upgrade`, ВМ выключена | чистая система, пользователи student и matvei, sshd на 22 |
| 02-keys-configured | 29.10.2026 11:53, после задания 1 | пользователь devops, вход по ключу |
| 03-ssh-hardened | 29.10.2026 12:08, после задания 2 | sshd на 2222, только ключи, AllowUsers devops |
| 03b-ufw-dns | 29.10.2026 13:01, после заданий 3 и 4 | UFW (deny, LIMIT 2222, 80, 443), FQDN devops-vm.devops.local |
| 04-nginx-https | 29.10.2026 14:32, ПР № 6, задание 2 | nginx, ресурс devops.local по HTTPS, перенаправление HTTP → HTTPS |
| 05-docker-compose | 29.10.2026, ПР № 7, задание 2 | Docker Engine, проект ~/app: приложение + PostgreSQL, том app_db_data |

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` из репозитория Ubuntu (nginx/1.24.0) |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, ссылка в `/etc/nginx/sites-enabled/`; ссылка `default` удалена |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталоги 755, файлы 644 |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` (блок перенаправления пишет в общий `/var/log/nginx/access.log`) |
| Сертификат | `/etc/ssl/certs/devops.crt`, `root:root`, 644; самоподписанный, CN и SAN `devops.local`, RSA 2048, 365 дней (до 29.10.2027) |
| Закрытый ключ | `/etc/ssl/private/devops.key`, `root:root`, 600 |
| Процессы | master — root, workers — www-data |

Порты 80/tcp и 443/tcp разрешены в UFW (раздел 6), профили `Nginx *` не используются.
Конфигурацию применять только `sudo nginx -t && sudo systemctl reload nginx`.

```bash
# [VM]
sudo apt update && sudo apt install -y nginx rsync
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"

sudo tee /etc/nginx/sites-available/devops-site > /dev/null <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log  /var/log/nginx/devops-site.error.log;
}
CONF
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
```

Хост (WSL 1 Ubuntu-24.04: rsync, curl, bash; `git push` — из Windows, ключ GitHub только там):
```bash
# [Хост, WSL]
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt   # доверенный канал — SSH
cd /mnt/c/Users/Matvey/devops-course-2026
scripts/deploy.sh                                    # доставка site/ с правами 755/644
curl --cacert ~/devops.crt -I https://devops.local   # 200 OK
```
HSTS не включается (самоподписанный сертификат).

## 9. Контейнеризация

| Параметр | Значение |
|---|---|
| Docker Engine | 29.9.2 из официального репозитория `download.docker.com` (`/etc/apt/sources.list.d/docker.sources`, ключ `/etc/apt/keyrings/docker.asc`); пакет `docker.io` не используется |
| Компоненты | containerd 2.4.2, runc 1.5.2, плагин Compose v5.6.1, buildx |
| Группа docker | `devops` (имеет sudo). Участие в группе равносильно правам root — других пользователей не добавлять |
| Проект | `/home/devops/app`, имя проекта Compose `app`; источник — каталог `app/` репозитория, доставка rsync |
| Сервисы | `app` — образ `devops-app:1.0` (python:3.12-slim, gunicorn, пользователь `app` uid 999); `db` — `postgres:16-alpine`, healthcheck `pg_isready` |
| Файл секретов | `/home/devops/app/.env`, владелец devops, права 600; создаётся только на сервере из `.env.example`, в репозиторий и на хост не копируется |
| Публикуемые порты | `127.0.0.1:5000` → app:5000 (только для Nginx); порт 5432 не публикуется |
| Сеть | `app_backend` (bridge), СУБД доступна приложению по имени `db` |
| Тома | `app_db_data` → `/var/lib/postgresql/data`. `docker compose down -v` удаляет данные безвозвратно |
| Обратный прокси | `location /app/` в блоке HTTPS `/etc/nginx/sites-available/devops-site` → `http://127.0.0.1:5000/` |

```bash
# [VM] Docker Engine
sudo apt update && sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops     # затем новая SSH-сессия
```

```bash
# [Хост, WSL] доставка проекта (без --chmod права 777 с /mnt/c попадут на сервер
# и сбросят кэш сборки; без --exclude=.env флаг --delete удалит секреты)
rsync -avz --delete --exclude=.env --chmod=D755,F644 app/ devops:app/
```

```bash
# [VM] секреты и запуск
cd ~/app
cp .env.example .env
chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
docker compose ps                  # db — (healthy)
sudo ss -tlnp | grep -E ':(5000|5432)\b'   # только 127.0.0.1:5000
```

Фрагмент блока `server { listen 443 ssl; ... }` в `/etc/nginx/sites-available/devops-site`:
```nginx
    location /app/ {
        proxy_pass http://127.0.0.1:5000/;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
```
```bash
sudo nginx -t && sudo systemctl reload nginx
curl --cacert ~/devops.crt https://devops.local/app/health   # [Хост] ok
```
Публикация на `0.0.0.0` (`"5000:5000"`) не допускается: правила Docker в iptables обходят UFW.

## Контроль

Скрипт `scripts/audit.sh` (запуск на сервере, код возврата 0 — конфигурация соответствует документу):
```powershell
# [Хост], из корня репозитория
scp scripts/audit.sh devops:
ssh -t devops 'bash audit.sh; echo exit=$?'
```
