#!/usr/bin/env bash
#===============================================================================
# fedora-optimize.sh — интернет, видеокарта и видео для Fedora Workstation 42–45
#
# Что делает:
#   • Интернет: BBR + fq, TCP-буферы, быстрые повторные соединения; Wi-Fi без
#     энергосбережения на ПК; DNS-over-TLS — только по вашему выбору, с проверкой.
#   • Видеокарта и видео: RPM Fusion, полный ffmpeg, кодеки и аппаратное
#     декодирование видео (VA-API) для Intel и AMD; драйвер NVIDIA (--nvidia).
#
# Предохранители:
#   • Без --apply скрипт только показывает план и ничего не меняет.
#   • Только новые drop-in файлы 99-fedora-optimize-full*; файлы Fedora не правятся.
#   • Исходные значения sysctl запоминаются, всё откатывается через --undo.
#
# Использование:
#   curl -fsSL URL | sudo bash -s -- --apply   # одной командой (см. README.md)
#   ./fedora-optimize.sh --status              # текущие значения (root не нужен)
#   sudo ./fedora-optimize.sh                  # план (ничего не меняет)
#   sudo ./fedora-optimize.sh --apply          # применить
#   sudo ./fedora-optimize.sh --undo           # откатить
#   sudo fedora-optimize --undo                # откат без интернета (копия
#                                              # ставится в /usr/local/sbin при --apply)
#
# Флаги:
#   --nvidia           драйвер NVIDIA из RPM Fusion (Secure Boot учитывается)
#   --dns=ИМЯ          DNS-over-TLS: cloudflare | quad9 | google | none.
#                      Без флага при --apply спросит в консоли (по умолчанию — не
#                      менять). Перед включением проверяет порт 853 и сертификат,
#                      после — что TLS-соединение реально установилось; если нет,
#                      автоматически откатывает.
#   --no-dns           не спрашивать про DNS (то же, что --dns=none)
#   --no-wifi          не отключать энергосбережение Wi-Fi на ПК
#   --no-network       пропустить настройки интернета (оставить только видео/GPU)
#   --no-multimedia    пропустить кодеки, RPM Fusion и VA-API (оставить только сеть)
#   --offline          без интернета: только настройки, без установки пакетов
#   --online           не проверять сеть (считать, что интернет есть)
# Без флагов --offline/--online наличие интернета определяется автоматически.

set -Eeuo pipefail

TAG="fedora-optimize-full"
STATE_DIR="/var/lib/${TAG}"
MANIFEST="${STATE_DIR}/files.list"
SVC_STATE="${STATE_DIR}/disabled-services.list"
ENABLED_STATE="${STATE_DIR}/enabled-services.list"
SYSCTL_ORIG="${STATE_DIR}/sysctl-orig.list"
PROFILE_STATE="${STATE_DIR}/power-profile.txt"

DRY=1; UNDO=0; STATUS=0
DO_NET=1; DO_MM=1; DO_WIFI=1; DO_NVIDIA=0; DNS_CHOICE=""
DNS_CHANGED=0
NET_MODE="auto"   # auto | offline | online
OFFLINE=0

# Адрес скрипта в репозитории (замените Maesev/fedora-optimize на свой, если назвали иначе)
RAW_URL="https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh"

# Путь к самому файлу (пусто, если скрипт запущен через конвейер: curl | bash)
SELF=""
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then SELF="${BASH_SOURCE[0]}"; fi
# Как повторить запуск (для подсказок в выводе)
if [[ -n "$SELF" ]]; then RUN_HINT="sudo bash $SELF"; else RUN_HINT="curl -fsSL $RAW_URL | sudo bash -s --"; fi
UNDO_HINT="$RUN_HINT"

if [[ -t 1 ]]; then
  C_G=$'\e[32m'; C_Y=$'\e[33m'; C_R=$'\e[31m'; C_B=$'\e[1m'; C_0=$'\e[0m'
else
  C_G=''; C_Y=''; C_R=''; C_B=''; C_0=''
fi
step(){ printf '\n%s==> %s%s\n' "$C_B" "$*" "$C_0"; }
ok()  { printf '  %s✔%s %s\n' "$C_G" "$C_0" "$*"; }
warn(){ printf '  %s!%s %s\n' "$C_Y" "$C_0" "$*"; }
die() { printf '%s✘ %s%s\n' "$C_R" "$*" "$C_0" >&2; exit 1; }
have(){ command -v "$1" >/dev/null 2>&1; }
usage(){
  if [[ -n "$SELF" ]]; then awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1{exit}' "$SELF"
  else echo "Справка доступна в самом файле и в README.md (флаги: --apply --nvidia --dns= --offline --undo --status)"; fi
  exit 0
}

for a in "$@"; do
  case "$a" in
    --apply)             DRY=0 ;;
    --undo)              UNDO=1; DRY=0 ;;
    --status)            STATUS=1 ;;
    --nvidia)            DO_NVIDIA=1 ;;
    --no-multimedia)     DO_MM=0 ;;
    --no-network)        DO_NET=0 ;;
    --no-wifi)           DO_WIFI=0 ;;
    --offline)           NET_MODE="offline" ;;
    --online)            NET_MODE="online" ;;
    --dns=*)             DNS_CHOICE="${a#--dns=}" ;;
    --no-dns)            DNS_CHOICE="none" ;;
    -h|--help)           usage ;;
    *) die "Неизвестный параметр: $a (см. --help)" ;;
  esac
done
case "$DNS_CHOICE" in ""|none|cloudflare|quad9|google) ;; *) die "--dns=cloudflare|quad9|google|none" ;; esac
DNS_FILE="/etc/systemd/resolved.conf.d/99-fedora-optimize-dns.conf"
DNS_SERVERS=""; DNS_PROBE_IP=""; DNS_PROBE_HOST=""

#--- Статус (без root) ---------------------------------------------------------
status(){
  step "Текущее состояние"
  local k
  for k in net.ipv4.tcp_congestion_control net.core.default_qdisc net.ipv4.tcp_fastopen \
           net.core.rmem_max net.core.wmem_max; do
    printf '  %-34s %s\n' "$k" "$(sysctl -n "$k" 2>/dev/null || echo n/a)"
  done
  if have resolvectl; then
    echo "  DNS:"
    resolvectl status 2>/dev/null | grep -E 'Current DNS Server|DNS Servers|DNSOverTLS' | head -4 | sed 's/^ */    /' || true
  fi
  if have lspci; then
    echo "  видеокарты:"; lspci 2>/dev/null | grep -Ei 'vga|3d|display' | sed 's/^/    /' || true
  fi
  if have vainfo; then
    echo "  VA-API:"; vainfo 2>/dev/null | grep -m3 -E 'Driver|VAProfileH264|VAProfileHEVC' | sed 's/^/    /' || true
  fi
  if [[ -f $MANIFEST ]]; then echo "  Файлов, созданных скриптом: $(wc -l < "$MANIFEST")"
  else echo "  Скрипт ещё не применялся"; fi
}
if (( STATUS )); then status; exit 0; fi

#--- Root ----------------------------------------------------------------------
if (( EUID != 0 )); then
  [[ -n "$SELF" ]] || die "Запуск из конвейера требует root: curl ... | sudo bash -s -- --apply"
  exec sudo -E bash "$SELF" "$@"
fi

#--- Помощники -----------------------------------------------------------------
# try: никогда не роняет скрипт; tryc: возвращает реальный статус
try(){
  if (( DRY )); then echo "  [план] $*"; return 0; fi
  "$@" || warn "не удалось: $*"
  return 0
}
tryc(){
  if (( DRY )); then echo "  [план] $*"; return 0; fi
  "$@" || { warn "не удалось: $*"; return 1; }
}
dnfi(){
  if (( OFFLINE )); then warn "офлайн: установка пропущена — $*"; return 0; fi
  try dnf install -y --skip-unavailable "$@"
}
# Есть ли интернет (проверка TCP до зеркал Fedora)
net_available(){
  timeout 5 bash -c 'exec 3<>/dev/tcp/mirrors.fedoraproject.org/443' >/dev/null 2>&1
}
have_tty(){ ( : </dev/tty ) 2>/dev/null; }

# Данные провайдера DNS: серверы, адрес и имя для проверки TLS
dns_provider(){
  case "$1" in
    cloudflare)
      DNS_SERVERS="1.1.1.1#cloudflare-dns.com 1.0.0.1#cloudflare-dns.com 2606:4700:4700::1111#cloudflare-dns.com 2606:4700:4700::1001#cloudflare-dns.com"
      DNS_PROBE_IP="1.1.1.1"; DNS_PROBE_HOST="cloudflare-dns.com" ;;
    quad9)
      DNS_SERVERS="9.9.9.9#dns.quad9.net 149.112.112.112#dns.quad9.net 2620:fe::fe#dns.quad9.net 2620:fe::9#dns.quad9.net"
      DNS_PROBE_IP="9.9.9.9"; DNS_PROBE_HOST="dns.quad9.net" ;;
    google)
      DNS_SERVERS="8.8.8.8#dns.google 8.8.4.4#dns.google 2001:4860:4860::8888#dns.google 2001:4860:4860::8844#dns.google"
      DNS_PROBE_IP="8.8.8.8"; DNS_PROBE_HOST="dns.google" ;;
  esac
}

# Вопрос пользователю в консоли (читаем из /dev/tty — работает и при curl | bash)
ask_dns(){
  [[ -z "$DNS_CHOICE" ]] || return 0
  if (( DRY )); then
    step "DNS-over-TLS (по желанию)"
    echo "  [план] при --apply скрипт спросит в консоли, включать ли DNS-over-TLS"
    echo "  [план] (или задайте заранее: --dns=cloudflare|quad9|google|none)"
    DNS_CHOICE="none"; return 0
  fi
  if (( OFFLINE )); then
    warn "офлайн: DNS-over-TLS не предлагается (проверить его без интернета нельзя)"
    DNS_CHOICE="none"; return 0
  fi
  if ! have_tty; then
    warn "Нет терминала для вопроса — DNS не меняется (задайте --dns=cloudflare|quad9|google)"
    DNS_CHOICE="none"; return 0
  fi
  step "DNS-over-TLS (по желанию)"
  {
    echo "  Шифрованный DNS скрывает DNS-запросы от провайдера, но отправляет их выбранной компании."
    echo "    1) Не менять DNS (по умолчанию)"
    echo "    2) Cloudflare 1.1.1.1 — быстрый"
    echo "    3) Quad9 9.9.9.9 — блокирует вредоносные домены"
    echo "    4) Google 8.8.8.8 — стабильный"
  } > /dev/tty
  local ans=""
  read -r -t 120 -p "  Ваш выбор [1-4, Enter = 1]: " ans < /dev/tty || ans=""
  case "$ans" in
    2) DNS_CHOICE="cloudflare" ;;
    3) DNS_CHOICE="quad9" ;;
    4) DNS_CHOICE="google" ;;
    *) DNS_CHOICE="none"; ok "DNS остаётся без изменений" ;;
  esac
}

# Проверка ДО включения: порт 853 и TLS-сертификат. 0 — можно применять.
dns_precheck(){
  local ip=$DNS_PROBE_IP host=$DNS_PROBE_HOST out
  if (( DRY )); then
    echo "  [план] проверка: TCP $ip:853, TLS-сертификат $host"
    return 0
  fi
  if ! timeout 5 bash -c "exec 3<>/dev/tcp/$ip/853" 2>/dev/null; then
    warn "Порт 853 ($ip) недоступен: сеть или провайдер блокируют DNS-over-TLS"
    return 1
  fi
  ok "Порт 853 доступен ($ip)"
  if have openssl; then
    out=$(echo | timeout 10 openssl s_client -connect "$ip:853" -servername "$host" -verify_hostname "$host" 2>/dev/null || true)
    if grep -q 'Verify return code: 0' <<<"$out"; then
      ok "TLS-сертификат $host корректен"
    else
      warn "TLS-сертификат $host не прошёл проверку — DNS не меняем"
      return 1
    fi
  else
    warn "openssl не найден — проверка сертификата пропущена"
  fi
  return 0
}

# Проверка ПОСЛЕ включения: имена разрешаются и TLS-соединение (порт 853) реально
# установилось. Иначе настройка откатывается, чтобы запросы не уходили открыто.
verify_dns(){
  step "Проверка DNS-over-TLS"
  local d i resolved=0 tls=0
  sleep 2
  if have resolvectl; then try resolvectl flush-caches; fi
  for d in example.com iana.org fedoraproject.org; do
    if have resolvectl; then timeout 8 resolvectl query "$d" >/dev/null 2>&1 && resolved=1
    else timeout 8 getent hosts "$d" >/dev/null 2>&1 && resolved=1; fi
  done
  for i in 1 2 3 4 5; do
    if [[ -n "$(ss -Htn state established '( dport = :853 )' 2>/dev/null)" ]]; then tls=1; break; fi
    sleep 1
  done
  if (( resolved && tls )); then
    ok "Имена разрешаются, TLS-соединение с DNS-сервером установлено — DNS-over-TLS работает"
    return 0
  fi
  (( resolved )) || warn "Имена не разрешаются с новыми настройками DNS"
  (( tls ))      || warn "TLS-соединение (порт 853) не установлено — запросы шли бы без шифрования"
  warn "Откатываю настройки DNS"
  rm -f -- "$DNS_FILE"
  if [[ -f $MANIFEST ]]; then sed -i "\|^${DNS_FILE}\$|d" "$MANIFEST"; fi
  try systemctl restart systemd-resolved
  sleep 2
  if have resolvectl && timeout 8 resolvectl query example.com >/dev/null 2>&1; then
    ok "DNS возвращён к прежним настройкам и работает"
  else
    warn "Проверьте DNS вручную: resolvectl status"
  fi
  return 0
}

write_file(){
  local path=$1 content
  content=$(cat)
  if (( DRY )); then
    echo "  [план] создать $path:"; printf '%s\n' "$content" | sed 's/^/        | /'; return 0
  fi
  install -d -m 0755 "$(dirname "$path")" "$STATE_DIR"
  printf '%s\n' "$content" > "$path"
  chmod 0644 "$path"
  grep -qxF "$path" "$MANIFEST" 2>/dev/null || echo "$path" >> "$MANIFEST"
  ok "создан $path"
}
remember(){ # remember FILE VALUE
  (( DRY )) && return 0
  install -d -m 0755 "$STATE_DIR"
  grep -qxF "$2" "$1" 2>/dev/null || echo "$2" >> "$1"
}
sysctl_path(){ printf '/proc/sys/%s' "$(tr . / <<<"$1")"; }
sysctl_record(){
  local k=$1 p; p=$(sysctl_path "$k")
  (( DRY )) && return 0
  [[ -e $p ]] || return 0
  install -d -m 0755 "$STATE_DIR"
  grep -q "^${k//./\\.}=" "$SYSCTL_ORIG" 2>/dev/null || echo "${k}=$(tr '\t' ' ' < "$p")" >> "$SYSCTL_ORIG"
}
SYSCTL_BUF=""
sysctl_add(){
  local k=$1 v=$2
  if [[ ! -e $(sysctl_path "$k") ]]; then warn "sysctl $k недоступен — пропуск"; return 0; fi
  sysctl_record "$k"
  SYSCTL_BUF+="${k} = ${v}"$'\n'
}
reload_all(){
  try systemctl daemon-reload
  try sysctl --system >/dev/null
  try udevadm control --reload
  if have nmcli; then try nmcli general reload conf; fi
  if (( DNS_CHANGED )); then try systemctl restart systemd-resolved; fi
}

# Копия скрипта в /usr/local/sbin: чтобы --undo и --status работали без интернета.
# При запуске через curl копия скачивается с того же адреса и проверяется (bash -n).
install_self(){
  local dst=/usr/local/sbin/fedora-optimize tmp
  if [[ -n "$SELF" ]]; then
    [[ "$(readlink -f "$SELF")" == "$dst" ]] || install -m 0755 "$SELF" "$dst"
  elif (( ! OFFLINE )) && have curl; then
    tmp=$(mktemp)
    if curl -fsSL --max-time 30 "$RAW_URL" -o "$tmp" \
       && head -n1 "$tmp" | grep -q '^#!/usr/bin/env bash' && bash -n "$tmp"; then
      install -m 0755 "$tmp" "$dst"
      rm -f "$tmp"
    else
      rm -f "$tmp"; warn "Не удалось сохранить копию скрипта — для отката используйте: $UNDO_HINT --undo"
      return 0
    fi
  else
    warn "Копия скрипта не сохранена (нет файла/интернета) — для отката: $UNDO_HINT --undo"
    return 0
  fi
  grep -qxF "$dst" "$MANIFEST" 2>/dev/null || echo "$dst" >> "$MANIFEST"
  UNDO_HINT="sudo fedora-optimize"
  ok "Копия скрипта: $dst (откат и статус работают без интернета)"
}

# Всё выполнение — внутри main: bash сначала целиком читает функцию, и команды
# вроде dnf не могут «съесть» остаток скрипта из stdin при curl | bash.
main(){
[[ -t 0 ]] || exec </dev/null

#===============================================================================
# ОТКАТ (откатывает и то, что сделали прежние версии скрипта)
#===============================================================================
if (( UNDO )); then
  step "Откат изменений"
  if [[ -f $MANIFEST ]]; then
    while IFS= read -r f; do
      if [[ -n $f && -e $f ]]; then
        rm -f -- "$f"; ok "удалён $f"
        [[ $f == *resolved.conf.d* ]] && DNS_CHANGED=1
      fi
    done < "$MANIFEST"
  else
    warn "манифест не найден — нечего откатывать"
  fi
  if [[ -f $SYSCTL_ORIG ]]; then
    # ratio-параметры восстанавливаем последними (они обнуляют *_bytes)
    { grep -v 'ratio=' "$SYSCTL_ORIG" || true; grep 'ratio=' "$SYSCTL_ORIG" || true; } |
    while IFS= read -r line; do
      [[ -n $line ]] || continue
      sysctl -w "${line%%=*}=${line#*=}" >/dev/null 2>&1 && ok "восстановлено ${line}" || warn "не восстановлено: ${line}"
    done
  fi
  if [[ -f $SVC_STATE ]]; then
    while IFS= read -r s; do
      [[ -n $s ]] || continue
      systemctl enable "$s" >/dev/null 2>&1 && ok "снова включён $s" || warn "не удалось включить $s"
    done < "$SVC_STATE"
  fi
  if [[ -f $ENABLED_STATE ]]; then
    while IFS= read -r s; do
      [[ -n $s ]] || continue
      systemctl disable --now "$s" >/dev/null 2>&1 && ok "выключен $s (был включён скриптом)" || warn "не удалось выключить $s"
    done < "$ENABLED_STATE"
  fi
  if [[ -f $PROFILE_STATE ]] && have powerprofilesctl; then
    powerprofilesctl set "$(<"$PROFILE_STATE")" >/dev/null 2>&1 && ok "профиль питания возвращён" || true
  fi
  rm -rf "$STATE_DIR"
  reload_all
  warn "Пакеты (RPM Fusion, кодеки, драйверы) не удаляются — откатываются только настройки."
  exit 0
fi

#===============================================================================
# ПРОВЕРКИ И ОПРЕДЕЛЕНИЕ ЖЕЛЕЗА
#===============================================================================
step "Проверка системы"
exec 9>/run/${TAG}.lock
flock -n 9 || die "Скрипт уже запущен"
[[ -r /etc/os-release ]] || die "нет /etc/os-release"
# shellcheck disable=SC1091
. /etc/os-release
[[ "${ID:-}" == "fedora" ]] || die "Это не Fedora (ID=${ID:-?})"
FEDORA_VER="${VERSION_ID:-0}"
[[ "$FEDORA_VER" =~ ^[0-9]+$ ]] || { warn "Нестандартная версия ($FEDORA_VER) — внешние репозитории пропускаются"; FEDORA_VER=""; }
if [[ -n "$FEDORA_VER" ]] && (( FEDORA_VER < 42 )); then die "Fedora $FEDORA_VER слишком старая (нужна 42+)"; fi
have dnf || die "dnf не найден"
if have systemd-detect-virt && systemd-detect-virt --container -q 2>/dev/null; then die "Контейнер: оптимизация хоста здесь не нужна"; fi
IS_VM=0; have systemd-detect-virt && systemd-detect-virt --vm -q 2>/dev/null && IS_VM=1 || true
FREE_MB=$(df --output=avail -BM / | tail -1 | tr -dc '0-9')
(( FREE_MB >= 1024 )) || die "Мало места на / (${FREE_MB} МБ, нужно ≥ 1024)"
IS_LAPTOP=0; compgen -G "/sys/class/power_supply/BAT*" >/dev/null && IS_LAPTOP=1 || true
GPU_INTEL=0; GPU_AMD=0; GPU_NVIDIA=0
for v in /sys/class/drm/card*/device/vendor; do
  [[ -r $v ]] || continue
  case "$(<"$v")" in 0x8086) GPU_INTEL=1 ;; 0x1002) GPU_AMD=1 ;; 0x10de) GPU_NVIDIA=1 ;; esac
done
GPU_LIST=""; (( GPU_INTEL )) && GPU_LIST+="Intel "; (( GPU_AMD )) && GPU_LIST+="AMD "; (( GPU_NVIDIA )) && GPU_LIST+="NVIDIA " || true
ok "Fedora ${FEDORA_VER:-rawhide}, GPU: ${GPU_LIST:-не найдена}"
ok "Тип: $( (( IS_LAPTOP )) && echo ноутбук || echo ПК )$( (( IS_VM )) && echo ', виртуальная машина' )"
(( DRY )) && warn "РЕЖИМ ПЛАНА: ничего не меняется. Для применения добавьте --apply"
case "$NET_MODE" in
  offline) OFFLINE=1 ;;
  online)  OFFLINE=0 ;;
  auto)    if net_available; then OFFLINE=0; else OFFLINE=1; fi ;;
esac
if (( OFFLINE )); then
  warn "ОФЛАЙН-РЕЖИМ: применяются только настройки. Пропускаются: установка пакетов, RPM Fusion, проверка DNS."
  warn "Если интернет есть, а проверка ошиблась — добавьте --online"
else
  ok "Интернет доступен"
fi
if (( DO_NET )); then ask_dns; fi
FAILED_BEFORE=$(systemctl --failed --no-legend 2>/dev/null | wc -l || true)

#===============================================================================
# 1. ИНТЕРНЕТ
#   BBR устойчивее CUBIC к потерям пакетов и высокому пингу (зарубежные
#   серверы, Wi-Fi, мобильный интернет); fq — подходящий для него планировщик.
#   tcp_fastopen — быстрее повторные соединения; mtu_probing — спасает от
#   «чёрных дыр» (VPN, PPPoE); slow_start_after_idle=0 — скорость не падает
#   после паузы; буферы 16 МБ — быстрее на каналах с большим RTT;
#   notsent_lowat — ниже задержка при больших загрузках.
#===============================================================================
if (( DO_NET )); then
  step "Интернет"
  sysctl_add net.ipv4.tcp_fastopen 3
  sysctl_add net.ipv4.tcp_mtu_probing 1
  sysctl_add net.ipv4.tcp_slow_start_after_idle 0
  sysctl_add net.ipv4.tcp_notsent_lowat 131072
  sysctl_add net.core.rmem_max 16777216
  sysctl_add net.core.wmem_max 16777216
  sysctl_add net.ipv4.tcp_rmem "4096 131072 16777216"
  sysctl_add net.ipv4.tcp_wmem "4096 16384 16777216"
  sysctl_add net.core.netdev_max_backlog 16384
  sysctl_add net.core.somaxconn 4096
  if modinfo tcp_bbr >/dev/null 2>&1; then
    write_file /etc/modules-load.d/99-fedora-optimize-bbr.conf <<'EOF'
tcp_bbr
EOF
    try modprobe tcp_bbr
    sysctl_add net.core.default_qdisc fq
    sysctl_add net.ipv4.tcp_congestion_control bbr
  else
    warn "Модуль tcp_bbr недоступен — остаётся стандартный алгоритм"
  fi
  if [[ -n "$SYSCTL_BUF" ]]; then
    printf '%s' "$SYSCTL_BUF" | write_file /etc/sysctl.d/99-fedora-optimize-full.conf
  fi

  # Wi-Fi: на ПК отключаем энергосбережение адаптера — помогает, если есть лаги
  # и скачки пинга по Wi-Fi. На ноутбуках не трогаем (это съедает батарею).
  # Пропустить: --no-wifi
  if (( DO_WIFI && ! IS_LAPTOP && ! IS_VM )) && compgen -G "/sys/class/net/*/wireless" >/dev/null; then
    write_file /etc/NetworkManager/conf.d/99-fedora-optimize-wifi.conf <<'EOF'
[connection]
wifi.powersave = 2
EOF
  fi

  # DNS-over-TLS — только по выбору пользователя (--dns=... или вопрос в консоли).
  # Порядок: проверка порта 853 и сертификата → запись настроек → после перезапуска
  # systemd-resolved проверка, что TLS-соединение реально установилось (иначе откат).
  if [[ -n "$DNS_CHOICE" && "$DNS_CHOICE" != "none" ]]; then
    step "DNS-over-TLS ($DNS_CHOICE)"
    dns_provider "$DNS_CHOICE"
    if (( OFFLINE )); then
      warn "офлайн: проверить DNS-over-TLS нельзя — пропуск (запустите скрипт позже с интернетом)"
    elif (( ! DRY )) && ! systemctl is-active systemd-resolved >/dev/null 2>&1; then
      warn "systemd-resolved не активен — DNS не меняем"
    elif dns_precheck; then
      write_file "$DNS_FILE" <<EOF
[Resolve]
DNS=${DNS_SERVERS}
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Domains=~.
EOF
      DNS_CHANGED=1
    else
      warn "DNS не изменён: проверка не пройдена. Выберите другого провайдера: --dns=quad9 или --dns=google"
    fi
  fi
fi

#===============================================================================
# 2. ВИДЕОКАРТА И ВИДЕО — RPM Fusion, ffmpeg, кодеки, VA-API
#   Урезанный ffmpeg-free в Fedora не декодирует часть форматов (H.264/H.265
#   и др.), а без VA-API видео декодирует процессор: выше нагрузка, нагрев и
#   расход батареи. Для просмотра видео и работы браузера это скорее
#   необходимость, чем оптимизация.
#===============================================================================
ensure_rpmfusion(){
  [[ -n "$FEDORA_VER" ]] || { warn "Нестандартная версия — RPM Fusion пропущен"; return 1; }
  if rpm -q rpmfusion-free-release rpmfusion-nonfree-release >/dev/null 2>&1; then return 0; fi
  if (( OFFLINE )); then warn "офлайн: RPM Fusion не подключён — пропуск"; return 1; fi
  warn "Подключается сторонний репозиторий RPM Fusion"
  try dnf install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA_VER}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA_VER}.noarch.rpm"
  return 0
}

if (( DO_MM )) && (( ! IS_VM )); then
  step "Кодеки и аппаратное декодирование видео"
  if ensure_rpmfusion; then
    dnfi ffmpeg --allowerasing
    dnfi gstreamer1-plugins-good gstreamer1-plugins-ugly gstreamer1-plugin-libav gstreamer1-libav \
         gstreamer1-plugins-bad-freeworld gstreamer1-plugin-openh264 mozilla-openh264 libva-utils vulkan-tools
    if (( GPU_INTEL )); then dnfi intel-media-driver; fi
    if (( GPU_AMD )); then dnfi mesa-va-drivers-freeworld mesa-vdpau-drivers-freeworld --allowerasing; fi
    if (( GPU_NVIDIA && ! DO_NVIDIA )); then
      warn "NVIDIA найдена: проприетарный драйвер ставится флагом --nvidia (нужен учёт Secure Boot)"
    fi
  fi
elif (( DO_MM )); then
  ok "Виртуальная машина — драйверы GPU пропущены"
fi

#===============================================================================
# 3. NVIDIA (--nvidia)
#===============================================================================
if (( DO_NVIDIA )); then
  step "Драйвер NVIDIA"
  if (( ! GPU_NVIDIA )); then
    warn "Видеокарта NVIDIA не найдена — пропуск"
  elif ensure_rpmfusion; then
    dnfi akmod-nvidia xorg-x11-drv-nvidia-cuda libva-nvidia-driver
    SB_STATE=""; if have mokutil; then SB_STATE=$(mokutil --sb-state 2>/dev/null || true); fi
    if grep -qi 'enabled' <<<"$SB_STATE"; then
      warn "Secure Boot ВКЛЮЧЁН: модуль NVIDIA нужно подписать ключом MOK."
      if (( DRY )); then
        echo "  [план] kmodgenca -a && mokutil --import /etc/pki/akmods/certs/public_key.der"
      else
        try kmodgenca -a
        if ( : </dev/tty ) 2>/dev/null; then
          warn "Сейчас будет запрошен пароль (одноразовый) — запомните его для экрана MOK при перезагрузке"
          try mokutil --import /etc/pki/akmods/certs/public_key.der </dev/tty
        else
          warn "Нет терминала для ввода пароля. Выполните вручную: sudo mokutil --import /etc/pki/akmods/certs/public_key.der"
        fi
      fi
    fi
    warn "Подождите ~5 минут, пока соберётся модуль, проверьте: modinfo -F version nvidia — затем перезагрузитесь."
  fi
fi

#===============================================================================
# ПРИМЕНЕНИЕ И ПРОВЕРКА
#===============================================================================
if (( ! DRY )); then
  step "Применение"
  reload_all
  if (( DNS_CHANGED )); then verify_dns; fi
  step "Проверка"
  FAILED_AFTER=$(systemctl --failed --no-legend 2>/dev/null | wc -l || true)
  if (( FAILED_AFTER > FAILED_BEFORE )); then
    warn "Появились упавшие юниты ($FAILED_BEFORE → $FAILED_AFTER): systemctl --failed; откат: $UNDO_HINT --undo"
  else
    ok "Новых упавших юнитов нет"
  fi
  install_self
  status
  if (( DO_NVIDIA )); then ok "Перезагрузка нужна после установки драйвера NVIDIA."; fi
  ok "Готово. Откат: $UNDO_HINT --undo"
else
  step "План составлен"
  echo "  Применить: $RUN_HINT --apply [--nvidia] [--dns=cloudflare|quad9|google] [--offline]"
fi
}

main "$@"
