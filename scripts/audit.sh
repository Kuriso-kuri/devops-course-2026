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

echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
