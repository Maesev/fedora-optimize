# fedora-optimize

**[🇷🇺 Русский](#ru)** | **[🇬🇧 English](#en)**

<a id="ru"></a>

## 🇷🇺 Русский

Настройка **интернета, видеокарты и видео** для **Fedora Workstation 42–45** одной командой.

- **Безопасно по умолчанию:** без флага `--apply` скрипт только показывает план и ничего не меняет.
- **Откат:** `--undo` возвращает исходные значения.
- **Работает без интернета:** `--offline` применяет только настройки; режим определяется автоматически.
- **Железо определяется само:** Intel / AMD / NVIDIA, ноутбук / ПК, виртуальная машина.

### Что входит

| Раздел | Что делает | Нужно ли |
|---|---|---|
| **Кодеки и VA-API** | RPM Fusion, полный ffmpeg, кодеки, аппаратное декодирование видео для Intel и AMD | если смотрите видео или пользуетесь браузером — это скорее необходимость, чем оптимизация |
| **Драйвер NVIDIA** (`--nvidia`) | драйвер из RPM Fusion с учётом Secure Boot | если у вас карта NVIDIA |
| **Wi-Fi без энергосбережения** (только ПК) | отключает powersave адаптера | если есть лаги и скачки пинга по Wi-Fi (отключается флагом `--no-wifi`) |
| **Настройки интернета** | BBR + fq, TCP-буферы, быстрые повторные соединения | для загрузок и зарубежных серверов |
| **DNS-over-TLS** | шифрованный DNS | по вашему выбору, с проверкой |

Больше скрипт **ничего не меняет** (память, диск, загрузка, службы, игры — не затрагиваются).

---

### Быстрый старт

Применить:

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | sudo bash -s -- --apply
```

Сначала посмотреть, что будет сделано (ничего не меняется):

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | sudo bash
```

С драйвером NVIDIA:

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | sudo bash -s -- --apply --nvidia
```

Только видео и видеокарта (без настроек интернета) или только интернет (без кодеков):

```bash
... | sudo bash -s -- --apply --no-network
... | sudo bash -s -- --apply --no-multimedia
```

Перезагрузка нужна только после установки драйвера NVIDIA.

> **Зачем `-s -- --apply`?** При запуске через конвейер аргументы нужно передать оболочке: `bash -s -- <аргументы>`. Без `--apply` скрипт работает в режиме плана — это защита от случайного запуска.

#### Сначала прочитать скрипт

Запуск чужого кода с правами root требует доверия. Посмотрите скрипт до запуска:

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | less
```

или скачайте, изучите и запустите локально:

```bash
curl -fsSLO https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh
less fedora-optimize.sh
sudo bash fedora-optimize.sh --apply
```

---

### Без интернета (офлайн)

Скачайте файл заранее и запустите локально:

```bash
sudo bash fedora-optimize.sh --apply --offline
```

Режим включается **автоматически**, если нет доступа к зеркалам Fedora. Если проверка ошиблась, а интернет есть — добавьте `--online`.

| Работает офлайн | Пропускается офлайн |
|---|---|
| BBR, TCP-буферы, Wi-Fi powersave | установка пакетов: RPM Fusion, кодеки, драйверы |
| | DNS-over-TLS (без сети его не проверить) |

После `--apply` копия скрипта сохраняется в `/usr/local/sbin/fedora-optimize`, поэтому **откат и статус работают без интернета**:

```bash
sudo fedora-optimize --undo
fedora-optimize --status
```

---

### Флаги

| Флаг | Что делает |
|---|---|
| `--apply` | применить изменения (без него — только план) |
| `--undo` | откатить всё, что сделал скрипт |
| `--status` | показать текущие значения (root не нужен) |
| `--nvidia` | драйвер NVIDIA из RPM Fusion с учётом Secure Boot |
| `--dns=ИМЯ` | DNS-over-TLS: `cloudflare`, `quad9`, `google` или `none`. Без флага скрипт **спросит в консоли** (по умолчанию — не менять) |
| `--no-dns` | не спрашивать про DNS (то же, что `--dns=none`) |
| `--no-wifi` | не отключать энергосбережение Wi-Fi на ПК |
| `--no-network` | пропустить настройки интернета (останутся кодеки и видео) |
| `--no-multimedia` | пропустить RPM Fusion, кодеки и VA-API (останутся настройки интернета) |
| `--offline` / `--online` | принудительно офлайн / считать, что интернет есть |

Пример:

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | sudo bash -s -- --apply --nvidia --dns=quad9
```

---

### Подробности

#### Кодеки и VA-API
| Настройка | Зачем |
|---|---|
| **RPM Fusion + полный ffmpeg** | в Fedora «урезанный» ffmpeg-free: часть форматов (H.264/H.265 и др.) не играет |
| **VA-API**: `intel-media-driver` (Intel), freeworld-драйверы Mesa (AMD) | аппаратное декодирование видео: ниже нагрузка на CPU, меньше нагрев и расход батареи |
| gstreamer-плагины, openh264 | видео и аудио в браузерах и приложениях GNOME |

В виртуальных машинах этот раздел пропускается.

#### Драйвер NVIDIA (`--nvidia`)
`akmod-nvidia` + CUDA + VA-API. При включённом Secure Boot скрипт готовит подпись модуля (`kmodgenca` + `mokutil`): попросит одноразовый пароль, который нужно ввести на синем экране MOK при перезагрузке. Драйвер без флага `--nvidia` не ставится, чтобы вы не остались без графики из-за Secure Boot. После установки подождите ~5 минут, пока соберётся модуль (`modinfo -F version nvidia`), затем перезагрузитесь.

#### Настройки интернета
| Настройка | Зачем |
|---|---|
| **BBR + fq** | устойчивее CUBIC к потерям и высокому пингу: зарубежные серверы, Wi-Fi, мобильный интернет |
| `tcp_fastopen`, `tcp_mtu_probing`, `tcp_slow_start_after_idle=0` | быстрее повторные соединения, нет «чёрных дыр» MTU (VPN, PPPoE), скорость не падает после паузы |
| буферы 16 МБ, `notsent_lowat`, `somaxconn` | выше скорость на каналах с большим RTT, ниже задержка |
| Wi-Fi без энергосбережения (только ПК) | меньше пинг; на ноутбуках не трогается |

Ключи sysctl, которых нет в вашем ядре, пропускаются.

#### DNS-over-TLS: по вашему выбору и с проверкой

Это **необязательная** настройка. При `--apply` скрипт спросит в консоли (работает и при `curl | sudo bash`):

```
1) Не менять DNS (по умолчанию)
2) Cloudflare 1.1.1.1
3) Quad9 9.9.9.9
4) Google 8.8.8.8
```

Чтобы не отвечать вручную: `--dns=cloudflare|quad9|google` (включить) или `--dns=none` / `--no-dns` (не менять). Без терминала и без интернета вопрос не задаётся, DNS остаётся прежним.

Проверки:
1. **До включения:** доступен ли порт 853 и корректен ли TLS-сертификат сервера. Если нет (например, провайдер блокирует DoT), DNS **не меняется**.
2. **После включения:** разрешаются ли имена и **действительно ли установилось TLS-соединение** с DNS-сервером. Если нет, настройки автоматически откатываются, чтобы запросы не уходили открыто на чужой сервер.

---

### Защита и откат

- Без `--apply` — только план.
- Скрипт не правит системные файлы Fedora, а создаёт свои `99-fedora-optimize-full*` в каталогах `*.d`.
- Исходные значения sysctl запоминаются и восстанавливаются при `--undo`.
- Перед применением проверяются: Fedora 42+, наличие `dnf`, свободное место (≥ 1 ГБ), не контейнер, нет второго запущенного экземпляра.
- После применения сравнивается число упавших systemd-юнитов; если оно выросло — будет предупреждение.
- `--undo` не удаляет установленные пакеты (RPM Fusion, кодеки, драйверы) — только настройки. Он также откатывает настройки, сделанные прежними, более широкими версиями скрипта.

### Компромиссы

- BBR и большие буферы на быстром домашнем интернете почти не дают выигрыша.
- Отключённое энергосбережение Wi-Fi увеличивает энергопотребление адаптера.
- DNS-over-TLS отправляет DNS-запросы выбранному провайдеру (Cloudflare / Quad9 / Google).
- RPM Fusion — сторонний репозиторий (не входит в Fedora).

### Вопросы

**Вопрос про DNS не принимает ввод (цифра «уходит» в терминал: `bash: 3: команда не найдена`).**
Такое было в ранней версии: при `curl | sudo bash` ввод не доходил до скрипта. В текущей версии скрипт сам находит ваш терминал; если вопрос всё равно не принимает ответ, он через 60 секунд оставит DNS без изменений и подскажет запуск в таком виде (ввод работает всегда):
`sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh)" -- --apply`.
Можно также заранее указать провайдера и не отвечать на вопрос: `--dns=quad9`.

**`Запуск из конвейера требует root`.**
Добавьте `sudo` перед `bash`: `curl ... | sudo bash -s -- --apply`.

**`raw.githubusercontent.com` недоступен.**
Скачайте файл с другого источника (или клонируйте репозиторий) и запустите локально:
`git clone https://github.com/Maesev/fedora-optimize && sudo bash fedora-optimize/fedora-optimize.sh --apply`.

**Пакет не найден в Fedora 44/45.**
Некоторые пакеты RPM Fusion могут называться иначе. Недоступные пакеты пропускаются с предупреждением, остальное устанавливается.

**Как проверить результат?**
`fedora-optimize --status` — алгоритм TCP, DNS, видеокарты и VA-API.

**Как вернуть всё как было?**
`sudo fedora-optimize --undo` (или `curl -fsSL URL | sudo bash -s -- --undo`).

### Отказ от ответственности

Скрипт вносит изменения на уровне системы. Используйте на свой риск, предварительно изучив его код и вывод режима плана. Перед установкой драйвера NVIDIA сделайте резервную копию важных данных.

---

<a id="en"></a>

## 🇬🇧 English

**Networking, GPU and video** setup for **Fedora Workstation 42–45** in one command.

- **Safe by default:** without `--apply` the script only prints a plan and changes nothing.
- **Reversible:** `--undo` restores the original values.
- **Works offline:** `--offline` applies settings only; it is also detected automatically.
- **Hardware-aware:** detects Intel / AMD / NVIDIA, laptop / desktop, virtual machines.

### What's included

| Part | What it does | Do you need it |
|---|---|---|
| **Codecs and VA-API** | RPM Fusion, full ffmpeg, codecs, hardware video decoding for Intel and AMD | if you watch video or use a browser — this is more of a necessity than an optimization |
| **NVIDIA driver** (`--nvidia`) | driver from RPM Fusion, Secure Boot aware | if you have an NVIDIA card |
| **Wi-Fi without power saving** (desktops only) | turns off adapter power saving | if you get lag and ping spikes over Wi-Fi (skip with `--no-wifi`) |
| **Network tuning** | BBR + fq, TCP buffers, faster repeat connections | for downloads and overseas servers |
| **DNS-over-TLS** | encrypted DNS | your choice, with verification |

The script changes **nothing else** (memory, disk, boot, services, gaming are not touched).

---

### Quick start

Apply:

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | sudo bash -s -- --apply
```

Preview what would be done (nothing is changed):

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | sudo bash
```

With the NVIDIA driver:

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | sudo bash -s -- --apply --nvidia
```

Video and GPU only (no network tuning), or network tuning only (no codecs):

```bash
... | sudo bash -s -- --apply --no-network
... | sudo bash -s -- --apply --no-multimedia
```

A reboot is needed only after installing the NVIDIA driver.

> **Why `-s -- --apply`?** When the script is piped into `bash`, arguments must be passed as `bash -s -- <arguments>`. Without `--apply` the script runs in plan mode — a safeguard against accidental runs.

#### Read the script first

Running code as root requires trust. Review the script before running it:

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | less
```

or download, read, then run it locally:

```bash
curl -fsSLO https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh
less fedora-optimize.sh
sudo bash fedora-optimize.sh --apply
```

---

### Offline use

Download the file in advance and run it locally:

```bash
sudo bash fedora-optimize.sh --apply --offline
```

Offline mode is enabled **automatically** when the Fedora mirrors are unreachable. If the check is wrong and you do have internet, add `--online`.

| Works offline | Skipped offline |
|---|---|
| BBR, TCP buffers, Wi-Fi power saving | package installation: RPM Fusion, codecs, drivers |
| | DNS-over-TLS (can't be verified without a network) |

After `--apply`, a copy of the script is saved to `/usr/local/sbin/fedora-optimize`, so **undo and status work without internet**:

```bash
sudo fedora-optimize --undo
fedora-optimize --status
```

---

### Flags

| Flag | Description |
|---|---|
| `--apply` | apply changes (without it — plan only) |
| `--undo` | revert everything the script changed |
| `--status` | show current values (no root needed) |
| `--nvidia` | NVIDIA driver from RPM Fusion, Secure Boot aware |
| `--dns=NAME` | DNS-over-TLS: `cloudflare`, `quad9`, `google` or `none`. Without the flag the script **asks in the console** (default: leave DNS unchanged) |
| `--no-dns` | don't ask about DNS (same as `--dns=none`) |
| `--no-wifi` | don't turn off Wi-Fi power saving on desktops |
| `--no-network` | skip network tuning (codecs and video remain) |
| `--no-multimedia` | skip RPM Fusion, codecs and VA-API (network tuning remains) |
| `--offline` / `--online` | force offline / assume internet is available |

Example:

```bash
curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh | sudo bash -s -- --apply --nvidia --dns=quad9
```

---

### Details

#### Codecs and VA-API
| Setting | Why |
|---|---|
| **RPM Fusion + full ffmpeg** | Fedora ships a trimmed-down ffmpeg-free: some formats (H.264/H.265, etc.) don't play |
| **VA-API**: `intel-media-driver` (Intel), Mesa freeworld drivers (AMD) | hardware video decoding: lower CPU load, less heat, better battery life |
| gstreamer plugins, openh264 | video and audio in browsers and GNOME apps |

This part is skipped inside virtual machines.

#### NVIDIA driver (`--nvidia`)
`akmod-nvidia` + CUDA + VA-API. With Secure Boot enabled the script prepares module signing (`kmodgenca` + `mokutil`): it asks for a one-time password that you must enter on the blue MOK screen at reboot. The driver is not installed without `--nvidia`, so you don't end up without graphics because of Secure Boot. After installation wait ~5 minutes for the module to build (`modinfo -F version nvidia`), then reboot.

#### Network tuning
| Setting | Why |
|---|---|
| **BBR + fq** | more resilient than CUBIC to packet loss and high latency: overseas servers, Wi-Fi, mobile internet |
| `tcp_fastopen`, `tcp_mtu_probing`, `tcp_slow_start_after_idle=0` | faster repeat connections, no MTU "black holes" (VPN, PPPoE), no speed drop after idle |
| 16 MB buffers, `notsent_lowat`, `somaxconn` | higher throughput on high-RTT links, lower latency |
| Wi-Fi power saving off (desktops only) | lower latency; laptops are left untouched |

sysctl keys that don't exist in your kernel are skipped.

#### DNS-over-TLS: your choice, with verification

This is **optional**. With `--apply` the script asks in the console (works with `curl | sudo bash` too):

```
1) Leave DNS unchanged (default)
2) Cloudflare 1.1.1.1
3) Quad9 9.9.9.9
4) Google 8.8.8.8
```

To skip the question: `--dns=cloudflare|quad9|google` (enable) or `--dns=none` / `--no-dns` (leave unchanged). With no terminal or no internet the question is not asked and DNS stays as it was.

Checks:
1. **Before enabling:** is port 853 reachable and is the server's TLS certificate valid? If not (e.g. your ISP blocks DoT), DNS is **left unchanged**.
2. **After enabling:** do names resolve and is a **TLS connection to the DNS server really established**? If not, the settings are rolled back automatically so queries don't leak in plaintext to a third-party server.

---

### Safety and undo

- Without `--apply` — plan only.
- The script does not modify Fedora's own files; it only creates its own `99-fedora-optimize-full*` files in `*.d` directories.
- Original sysctl values are recorded and restored by `--undo`.
- Pre-flight checks: Fedora 42+, `dnf` present, free disk space (≥ 1 GB), not a container, no other instance running.
- After applying, the number of failed systemd units is compared; a warning is shown if it grew.
- `--undo` does not remove installed packages (RPM Fusion, codecs, drivers) — only settings. It also reverts settings made by earlier, broader versions of the script.

### Trade-offs

- BBR and large buffers give little on a fast home connection.
- Disabled Wi-Fi power saving increases the adapter's power consumption.
- DNS-over-TLS sends your DNS queries to the chosen provider (Cloudflare / Quad9 / Google).
- RPM Fusion is a third-party repository (not part of Fedora).

### FAQ

**The DNS question doesn't accept input (the digit "leaks" into the shell: `bash: 3: command not found`).**
An early version had this problem: with `curl | sudo bash` the input never reached the script. The current version finds your terminal itself; if the question still doesn't take an answer, it leaves DNS unchanged after 60 seconds and suggests running it like this (input always works):
`sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/Maesev/fedora-optimize/main/fedora-optimize.sh)" -- --apply`.
You can also pick the provider up front and skip the question: `--dns=quad9`.

**`Запуск из конвейера требует root` (pipeline requires root).**
Put `sudo` before `bash`: `curl ... | sudo bash -s -- --apply`.

**`raw.githubusercontent.com` is unreachable.**
Get the file from another source (or clone the repository) and run it locally:
`git clone https://github.com/Maesev/fedora-optimize && sudo bash fedora-optimize/fedora-optimize.sh --apply`.

**A package is not found on Fedora 44/45.**
Some RPM Fusion packages may be named differently. Unavailable packages are skipped with a warning; everything else is installed.

**How do I check the result?**
`fedora-optimize --status` — TCP algorithm, DNS, GPUs and VA-API.

**How do I revert everything?**
`sudo fedora-optimize --undo` (or `curl -fsSL URL | sudo bash -s -- --undo`).

### Disclaimer

The script makes system-level changes. Use at your own risk, after reviewing its code and the plan-mode output. Back up important data before installing the NVIDIA driver.
