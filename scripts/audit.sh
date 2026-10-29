#!/usr/bin/env bash
# Аудит конфигурации devops-vm (ПР № 5)
# Запуск на сервере: bash audit.sh; echo $?
set -uo pipefail

PASS=0; FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  [OK]   $desc"; ((PASS++))
  else
    echo "  [FAIL] $desc (ожидалось: '$expected', получено: '$actual')"; ((FAIL++))
  fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"
check "Вход от имени root запрещён" "no" \
  "$(sudo sshd -T | awk '/^permitrootlogin/{print $2}')"
check "Парольная аутентификация отключена" "no" \
  "$(sudo sshd -T | awk '/^passwordauthentication/{print $2}')"

# TODO 1: значение параметра port отлично от 22
ssh_port="$(sudo sshd -T | awk '/^port /{print $2}')"
check "Порт SSH отличен от 22 (текущий: ${ssh_port})" "yes" \
  "$([[ -n "$ssh_port" && "$ssh_port" != "22" ]] && echo yes || echo no)"

# TODO 2: значение параметра maxauthtries равно 3
check "MaxAuthTries равен 3" "3" \
  "$(sudo sshd -T | awk '/^maxauthtries/{print $2}')"

echo "[2] Межсетевой экран"
check "Межсетевой экран активен" "active" \
  "$(sudo ufw status | awk '/^Status:/{print $2}')"

# TODO 3: политика по умолчанию для входящего трафика равна deny
# строка вида: Default: deny (incoming), allow (outgoing), disabled (routed)
check "Политика по умолчанию для входящего трафика: deny" "deny" \
  "$(sudo ufw status verbose | awk '/^Default:/{print $2}')"

echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "  %s (uid=%s)\n",$1,$3}' /etc/passwd

echo "[4] Веб-сервер"
# Порог для проверки срока сертификата (дней); для проверки на нарушенном
# условии можно запустить: CERT_MIN_DAYS=400 bash audit.sh
CERT_MIN_DAYS="${CERT_MIN_DAYS:-30}"
check "Служба nginx активна" "active" \
  "$(systemctl is-active nginx)"
check "Конфигурация nginx синтаксически корректна" "0" \
  "$(sudo nginx -t >/dev/null 2>&1; echo $?)"
check "Сертификат действует ещё не менее ${CERT_MIN_DAYS} дней" "0" \
  "$(openssl x509 -checkend $((CERT_MIN_DAYS * 86400)) -noout -in /etc/ssl/certs/devops.crt >/dev/null 2>&1; echo $?)"
check "В каталоге ресурса нет файлов, доступных на запись всем" "" \
  "$(find /var/www/devops-site -perm -o+w 2>/dev/null | tr '\n' ' ' | sed 's/ $//')"
check "Права закрытого ключа TLS равны 600" "600" \
  "$(sudo stat -c '%a' /etc/ssl/private/devops.key)"

echo "[5] Контейнеризация"
APP_DIR="${APP_DIR:-/home/devops/app}"
check "Служба docker активна" "active" \
  "$(systemctl is-active docker)"
check "Контейнер СУБД app-db-1 в состоянии healthy" "healthy" \
  "$(docker inspect -f '{{.State.Health.Status}}' app-db-1 2>/dev/null || echo 'нет контейнера')"
check "Порты 5000 и 5432 прослушиваются только на 127.0.0.1" "" \
  "$(ss -tln | awk '$4 ~ /:(5000|5432)$/ {print $4}' | grep -v '^127\.0\.0\.1:' | tr '\n' ' ' | sed 's/ $//')"
check "Права файла ${APP_DIR}/.env равны 600" "600" \
  "$(stat -c '%a' "${APP_DIR}/.env" 2>/dev/null || echo 'нет файла')"

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
