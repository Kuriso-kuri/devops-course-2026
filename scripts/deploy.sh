#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                       # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

die() { echo "ОШИБКА: $*" >&2; exit 1; }

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
  "")        ;;
  --dry-run) DRY_RUN=1 ;;
  *)         die "неизвестный аргумент '$1'. Использование: $0 [--dry-run]" ;;
esac
[[ $# -le 1 ]] || die "слишком много аргументов. Использование: $0 [--dry-run]"

# Требование 2: работа из любого каталога — переходим в корень репозитория,
# в котором лежит сам сценарий
cd "$(dirname "$(readlink -f "$0")")"
REPO_ROOT="$(git rev-parse --show-toplevel)" || die "сценарий находится вне git-репозитория"
cd "$REPO_ROOT"
LOCAL_DIR="${REPO_ROOT}/site/"

# 2. Проверки по требованиям 4 и 5
[[ -f "${LOCAL_DIR}index.html" ]] || die "файл site/index.html отсутствует — доставка отменена (иначе --delete удалит главную страницу)"

if [[ -n "$(git status --porcelain)" ]]; then
  git status --short >&2
  die "в репозитории есть незафиксированные изменения — выполните commit или stash"
fi

COMMIT="$(git rev-parse --short HEAD)"

# 3. Синхронизация: одно SSH-соединение (требование 8), без интерактивного
#    запроса пароля (требование 9)
RSYNC_OPTS=(-az --delete --chmod=D755,F644 --itemize-changes
            -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if (( DRY_RUN )); then RSYNC_OPTS+=(--dry-run); MODE=" (пробный запуск)"; else MODE=""; fi

echo "Доставка коммита ${COMMIT}: ${LOCAL_DIR} -> ${REMOTE}:${REMOTE_DIR}/${MODE}"
rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/" || die "rsync завершился с ошибкой"

# 4. При --dry-run — завершение без проверки доступности
if (( DRY_RUN )); then
  echo "Пробный запуск завершён, состояние сервера не изменено"
  exit 0
fi

# 5. Проверка доступности с проверкой сертификата (без -k), требование 6
[[ -r "$CA_CERT" ]] || die "сертификат ${CA_CERT} не найден"
if ! curl -fsS --cacert "$CA_CERT" --max-time 5 -o /dev/null "$SITE_URL/"; then
  die "ресурс ${SITE_URL} недоступен после доставки"
fi

echo "Готово: доставлен коммит ${COMMIT}, ресурс ${SITE_URL} доступен"
