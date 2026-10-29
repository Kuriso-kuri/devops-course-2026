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

## Контроль

Скрипт `scripts/audit.sh` (запуск на сервере, код возврата 0 — конфигурация соответствует документу):
```powershell
# [Хост], из корня репозитория
scp scripts/audit.sh devops:
ssh -t devops 'bash audit.sh; echo exit=$?'
```
