#!/bin/sh

# Добавляем режим отладки
DEBUG=0
if [ "$1" = "-d" ] || [ "$1" = "--debug" ]; then
  DEBUG=1
  echo "Включен режим отладки"
  set -x
fi

# Функция для вывода сообщений с временной меткой
log_message() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Функция для создания резервных копий
create_backup() {
  BACKUP_DIR="/tmp/router_backup_$(date '+%Y%m%d%H%M%S')"
  log_message "Создание резервной копии настроек в $BACKUP_DIR"
  
  mkdir -p "$BACKUP_DIR"
  
  # Резервное копирование конфигураций
  sysupgrade -b "$BACKUP_DIR/config_backup.tar.gz"
  
  # Резервное копирование отдельных настроек
  if [ -d "/etc/config" ]; then
    cp -r /etc/config "$BACKUP_DIR/config"
  fi
  
  if [ -d "/opt/clash" ]; then
    cp -r /opt/clash "$BACKUP_DIR/clash"
  fi
  
  log_message "Резервное копирование завершено"
}

# Основная часть скрипта
log_message "Начало выполнения скрипта"

echo "Введите ссылку на вашу подписку VPN (например, https://example.com/subscription):"
read -r VPN_SUBSCRIPTION_URL
if [ -z "$VPN_SUBSCRIPTION_URL" ]; then
  log_message "Ссылка на подписку не указана. Используется значение по умолчанию: https://google.com"
  VPN_SUBSCRIPTION_URL="https://google.com"
fi

echo "Введите название для Wi-Fi сетей (без суффикса -5G для 5 ГГц):"
read -r WIFI_NAME
if [ -z "$WIFI_NAME" ]; then
  log_message "Название Wi-Fi не указано. Будет использовано автоматическое название."
  WIFI_NAME=""
fi

echo "Введите пароль для Wi-Fi сетей (минимум 8 символов):"
read -r WIFI_PASSWORD
if [ -z "$WIFI_PASSWORD" ]; then
  log_message "Пароль Wi-Fi не указан. Используется значение по умолчанию: MagicRouter123"
  WIFI_PASSWORD="MagicRouter123"
elif [ ${#WIFI_PASSWORD} -lt 8 ]; then
  log_message "Пароль Wi-Fi слишком короткий. Используется значение по умолчанию: MagicRouter123"
  WIFI_PASSWORD="MagicRouter123"
fi

echo "Введите новый пароль для пользователя root:"
read -r ROOT_PASSWORD
if [ -z "$ROOT_PASSWORD" ]; then
  log_message "Пароль не указан. Используется значение по умолчанию: magicrouter123@"
  ROOT_PASSWORD="magicrouter123@"
fi

echo "Введите название для прокси-провайдера (например, my_vpn_provider):"
read -r PROXY_PROVIDER_NAME
if [ -z "$PROXY_PROVIDER_NAME" ]; then
  log_message "Название прокси-провайдера не указано. Используется значение по умолчанию: t.me/blgdrnvpn_bot"
  PROXY_PROVIDER_NAME="t.me/blgdrnvpn_bot"
fi

echo "Выберите архитектуру ядра:"
echo "1. mipsel_24kc"
echo "2. arm64"
echo "3. Amd64"
while true; do
  read -p "Введите номер архитектуры (1-3): " choice
  case "$choice" in
    1)
      KERNEL="mipsel_24kc"
      break
      ;;
    2)
      KERNEL="arm64"
      break
      ;;
    3)
      KERNEL="Amd64"
      break
      ;;
    *)
      log_message "Неверный выбор. Попробуйте снова."
      ;;
  esac
done

log_message "Выбрана архитектура: $KERNEL"

# Создание резервной копии перед внесением изменений
create_backup

log_message "Установка пароля root..."
if echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd root; then
  log_message "Пароль root успешно изменен"
else
  log_message "Ошибка при изменении пароля root"
fi

log_message "Переименование Wi-Fi сетей..."
if uci show wireless | grep -q "@wifi-iface"; then
  WIFI_IFACE=$(uci show wireless | grep "@wifi-iface" | cut -d "[" -f2 | cut -d "]" -f1 | head -n 1)
  if [ -n "$WIFI_IFACE" ]; then
    WIFI_IFNAME=$(uci get wireless.@wifi-iface[$WIFI_IFACE].ifname)
    if [ -n "$WIFI_IFNAME" ] && [ -e "/sys/class/net/$WIFI_IFNAME/address" ]; then
      if [ -z "$WIFI_NAME" ]; then
        MAC_HASH=$(cat /sys/class/net/$WIFI_IFNAME/address | md5sum | cut -c1-6)
        WIFI_NAME="MagicRouter$MAC_HASH"
        log_message "Сгенерировано автоматическое имя Wi-Fi: $WIFI_NAME"
      fi

      uci set wireless.@wifi-iface[0].ssid="$WIFI_NAME"
      uci set wireless.@wifi-iface[1].ssid="$WIFI_NAME-5G"
      log_message "Wi-Fi сети переименованы в '$WIFI_NAME' и '$WIFI_NAME-5G'"
    else
      log_message "Не удалось получить MAC-адрес Wi-Fi интерфейса."
    fi
  else
    log_message "Wi-Fi интерфейсы не найдены."
  fi
else
  log_message "Wi-Fi интерфейсы не найдены. Пропускаю настройку Wi-Fi."
fi

log_message "Настройка мощности сигнала Wi-Fi и паролей..."
for iface in $(uci show wireless | grep "@wifi-iface" | cut -d "[" -f2 | cut -d "]" -f1); do
  uci set wireless.@wifi-iface[$iface].txpower=20
  uci set wireless.@wifi-iface[$iface].key="$WIFI_PASSWORD"
  uci set wireless.@wifi-iface[$iface].encryption="psk2"
  log_message "Настроен Wi-Fi интерфейс $iface: мощность=20, шифрование=psk2"
done
uci commit wireless
log_message "Перезагрузка Wi-Fi..."
if wifi reload; then
  log_message "Wi-Fi успешно перезагружен"
else
  log_message "Ошибка при перезагрузке Wi-Fi"
fi

log_message "Настройка web-панели..."
uci set luci.main.lang="ru"
uci set luci.main.mediaurlbase="/luci-static/argon"
uci commit luci
log_message "Web-панель настроена: язык=ru, тема=argon"

log_message "Настройка сетевых интерфейсов и DNS..."
uci set network.wan6.disabled=1
uci set network.wan.peerdns=0
uci del_list network.wan.dns 1>/dev/null 2>&1
uci add_list network.wan.dns='1.1.1.1'
uci add_list network.wan.dns='1.0.0.1'
uci add_list network.wan.dns='8.8.4.4'
uci add_list network.wan.dns='8.8.8.8'
uci commit network
log_message "Перезапуск сетевых интерфейсов..."
if /etc/init.d/network restart; then
  log_message "Сетевые интерфейсы успешно перезапущены"
else
  log_message "Ошибка при перезапуске сетевых интерфейсов"
fi

log_message "Обновление opkg и установка необходимых пакетов..."
if opkg update; then
  log_message "База пакетов успешно обновлена"
else
  log_message "Ошибка при обновлении базы пакетов"
fi

if opkg install kmod-nft-tproxy curl; then
  log_message "Пакеты kmod-nft-tproxy и curl успешно установлены"
else
  log_message "Ошибка при установке пакетов kmod-nft-tproxy и curl"
fi

log_message "Получение и установка luci-app-ssclash..."
releasessclash=$(curl -s -L https://github.com/zerolabnet/SSClash/releases/latest | grep "title>Release" | cut -d " " -f 4 | cut -d "v" -f 2)
if [ -n "$releasessclash" ]; then
  log_message "Найдена версия SSClash: $releasessclash"
  curl -L https://github.com/zerolabnet/ssclash/releases/download/v$releasessclash/luci-app-ssclash_${releasessclash}-1_all.ipk -o /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk
  if [ -f "/tmp/luci-app-ssclash_${releasessclash}-1_all.ipk" ]; then
    log_message "Установка пакета luci-app-ssclash..."
    if opkg install /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk; then
      log_message "Пакет luci-app-ssclash успешно установлен"
    else
      log_message "Ошибка при установке пакета luci-app-ssclash"
    fi
    rm -f /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk
  else
    log_message "Ошибка при загрузке пакета luci-app-ssclash"
  fi
else
  log_message "Не удалось получить актуальную версию SSClash"
fi

log_message "Остановка сервиса clash..."
if service clash stop; then
  log_message "Сервис clash успешно остановлен"
else
  log_message "Ошибка при остановке сервиса clash или сервис не был запущен"
fi

log_message "Получение версии mihomo..."
releasemihomo=$(curl -s -L https://github.com/MetaCubeX/mihomo/releases/latest | grep "title>Release" | cut -d " " -f 4)
if [ -n "$releasemihomo" ]; then
  log_message "Найдена версия mihomo: $releasemihomo"
else
  log_message "Не удалось получить актуальную версию mihomo. Используется версия по умолчанию."
  releasemihomo="v1.18.0"
fi

log_message "Загрузка бинарника для $KERNEL..."
case "$KERNEL" in
  arm64)
    curl -L https://github.com/MetaCubeX/mihomo/releases/download/$releasemihomo/mihomo-linux-arm64-$releasemihomo.gz -o /tmp/clash.gz
    ;;
  mipsel_24kc)
    curl -L https://github.com/MetaCubeX/mihomo/releases/download/$releasemihomo/mihomo-linux-mipsle-softfloat-$releasemihomo.gz -o /tmp/clash.gz
    ;;
  Amd64)
    curl -L https://github.com/MetaCubeX/mihomo/releases/download/$releasemihomo/mihomo-linux-amd64-compatible-$releasemihomo.gz -o /tmp/clash.gz
    ;;
esac

log_message "Распаковка и установка clash..."
if [ -f "/tmp/clash.gz" ]; then
  mkdir -p /opt/clash/bin
  if gunzip -c /tmp/clash.gz > /opt/clash/bin/clash; then
    chmod +x /opt/clash/bin/clash
    log_message "Clash успешно установлен"
  else
    log_message "Ошибка при распаковке clash"
  fi
  rm -f /tmp/clash.gz
else
  log_message "Ошибка: файл /tmp/clash.gz не найден"
fi

# Настройка брандмауэра для работы с Clash
log_message "Настройка брандмауэра для Clash..."
# Добавление правил для прозрачного прокси
uci -q delete firewall.clash_tproxy
uci set firewall.clash_tproxy="include"
uci set firewall.clash_tproxy.type="script"
uci set firewall.clash_tproxy.path="/etc/firewall.clash"
uci set firewall.clash_tproxy.family="any"
uci set firewall.clash_tproxy.reload="1"
uci commit firewall

# Создание скрипта для настройки брандмауэра
cat << 'EOF' > /etc/firewall.clash
#!/bin/sh

# IP для адресации трафика на Clash
CLASH_DNS_PORT=7874
CLASH_TPROXY_PORT=7894
BYPASS_IPSET="bypass"

# Очистка старых правил
iptables -t nat -D PREROUTING -p tcp -j CLASH_TCP 2>/dev/null
iptables -t nat -F CLASH_TCP 2>/dev/null
iptables -t nat -X CLASH_TCP 2>/dev/null
iptables -t mangle -D PREROUTING -j CLASH_UDP 2>/dev/null
iptables -t mangle -F CLASH_UDP 2>/dev/null
iptables -t mangle -X CLASH_UDP 2>/dev/null

ipset -exist destroy $BYPASS_IPSET

# Создание нового набора для обхода
ipset -exist create $BYPASS_IPSET hash:net

# Добавление локальных сетей в обходной список
ipset -exist add $BYPASS_IPSET 0.0.0.0/8
ipset -exist add $BYPASS_IPSET 10.0.0.0/8
ipset -exist add $BYPASS_IPSET 127.0.0.0/8
ipset -exist add $BYPASS_IPSET 169.254.0.0/16
ipset -exist add $BYPASS_IPSET 172.16.0.0/12
ipset -exist add $BYPASS_IPSET 192.168.0.0/16
ipset -exist add $BYPASS_IPSET 224.0.0.0/4
ipset -exist add $BYPASS_IPSET 240.0.0.0/4
ipset -exist add $BYPASS_IPSET 198.18.0.0/16

# Создание цепочек правил
iptables -t nat -N CLASH_TCP
iptables -t nat -A CLASH_TCP -p tcp -m set --match-set $BYPASS_IPSET dst -j RETURN
iptables -t nat -A CLASH_TCP -p tcp -j REDIRECT --to-port $CLASH_DNS_PORT -m comment --comment "DNS Hijack"
iptables -t nat -A PREROUTING -p tcp -j CLASH_TCP

# UDP правила
iptables -t mangle -N CLASH_UDP
iptables -t mangle -A CLASH_UDP -p udp -m set --match-set $BYPASS_IPSET dst -j RETURN
iptables -t mangle -A CLASH_UDP -p udp -j TPROXY --on-port $CLASH_TPROXY_PORT --tproxy-mark 1
iptables -t mangle -A PREROUTING -j CLASH_UDP

# Маршрут для перенаправленного трафика
ip rule add fwmark 1 table 100
ip route add local default dev lo table 100
EOF

chmod +x /etc/firewall.clash

# Применение правил брандмауэра
log_message "Применение правил брандмауэра..."
if /etc/init.d/firewall restart; then
  log_message "Правила брандмауэра успешно применены"
else
  log_message "Ошибка при применении правил брандмауэра"
fi

if [ -x "/opt/clash/bin/clash" ]; then
  log_message "Запуск сервиса clash..."
  if service clash start; then
    log_message "Сервис clash успешно запущен"
  else
    log_message "Ошибка при запуске сервиса clash"
  fi
else
  log_message "Бинарник clash не найден. Убедитесь, что он был установлен корректно."
fi

log_message "Настройка конфигурации Clash..."
cat << EOF > /opt/clash/config.yaml
mode: rule
ipv6: false
log-level: error
allow-lan: false
tproxy-port: 7894
unified-delay: true
tcp-concurrent: true
external-controller: 0.0.0.0:9090
external-ui: ./xd

dns:
  enable: true
  listen: 0.0.0.0:7874
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  nameserver:
    - https://dns10.quad9.net/dns-query
    - https://dns.aa.net.uk/dns-query
  fake-ip-filter-mode: blacklist
  fake-ip-filter:
    - '*.lan'
    - '*.local'
    - +.msftconnecttest.com
    - +.3gppnetwork.org

keep-alive-idle: 15
keep-alive-interval: 15

proxy-providers:
  $PROXY_PROVIDER_NAME:
    type: http
    url: "$VPN_SUBSCRIPTION_URL"
    interval: 86400
    proxy: DIRECT
    header:
      User-Agent:
        - "Clash/v$releasessclash"
        - "mihomo/$releasemihomo"
    health-check:
      enable: true
      url: http://cp.cloudflare.com/generate_204
      interval: 300
      timeout: 5000
      lazy: true
      expected-status: 204

proxy-groups:
  - name: Автовыбор
    type: fallback
    include-all: true
    url: http://gstatic.com/generate_204
    expected-status: 204
    interval: 300
    lazy: true
    icon: https://fastly.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Available.png
    use:
      - $PROXY_PROVIDER_NAME
      
  - name: Ручной выбор
    type: select
    include-all: true
    url: http://gstatic.com/generate_204
    expected-status: 204
    interval: 300
    lazy: true
    icon: https://fastly.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Proxy.png
    use:
      - $PROXY_PROVIDER_NAME

rule-providers:
  ru-bundle:
    type: http
    behavior: domain
    format: mrs
    url: https://github.com/legiz-ru/mihomo-rule-sets/raw/main/ru-bundle/rule.mrs
    path: ./ru-bundle/rule.mrs
    interval: 86400
  oisd_big:
    type: http
    behavior: domain
    format: mrs
    url: https://github.com/legiz-ru/mihomo-rule-sets/raw/main/oisd/big.mrs
    path: ./oisd/big.mrs
    interval: 86400
  discord-domain:
    behavior: classical
    type: http
    url: "https://raw.githubusercontent.com/fildunsky/clash_discord/refs/heads/main/discord-domain.yaml"
    interval: 86400
    path: ./ruleset/discord-domain.yaml
  discord-ip:
    behavior: classical
    type: http
    url: "https://raw.githubusercontent.com/fildunsky/clash_discord/refs/heads/main/discord-ip.yaml"
    interval: 86400
    path: ./ruleset/discord-ip.yaml
  whatsapp:
    behavior: classical
    type: http
    url: "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/refs/heads/master/rule/Clash/Whatsapp/Whatsapp.yaml"
    interval: 86400
    path: ./ruleset/whatsapp.yaml

rules:
  - RULE-SET,oisd_big,REJECT
  - DOMAIN-SUFFIX,3gppnetwork.org,DIRECT
  - DOMAIN-SUFFIX,mts.ru,DIRECT
  - DOMAIN-SUFFIX,megafon.ru,DIRECT
  - DOMAIN-SUFFIX,chatgpt.com,Автовыбор
  - RULE-SET,whatsapp,DIRECT
  - RULE-SET,discord-domain,Автовыбор
  - RULE-SET,discord-ip,Автовыбор
  - PROCESS-NAME,com.bigwinepot.nwdn.international,Автовыбор
  - DOMAIN-SUFFIX,googleads.g.doubleclick.net,REJECT
  - DOMAIN-SUFFIX,www.googleadservices.com,REJECT
  - DOMAIN-SUFFIX,operator.chatgpt.com,Автовыбор
  - PROCESS-NAME,com.openai.chatgpt,Автовыбор
  - PROCESS-NAME,Discord.exe,Автовыбор
  - PROCESS-NAME,Cursor.exe,Автовыбор
  - DOMAIN-SUFFIX,sora.com,Автовыбор
  - RULE-SET,ru-bundle,Автовыбор
  - MATCH,DIRECT
EOF

log_message "Скрипт завершил работу успешно!"
echo "==================================="
echo "Настройка роутера завершена. Сводная информация:"
echo "Wi-Fi SSID: $WIFI_NAME и $WIFI_NAME-5G"
echo "Wi-Fi пароль: $WIFI_PASSWORD"
echo "Версия Clash: $releasessclash"
echo "Версия Mihomo: $releasemihomo"
echo "Резервная копия: да"
echo "Настройка брандмауэра: да"
echo "==================================="
echo "Теперь вы можете подключиться к роутеру через Wi-Fi или веб-интерфейс."