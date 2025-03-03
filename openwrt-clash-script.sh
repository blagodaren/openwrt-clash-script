#!/bin/sh
# Скрипт для обновления и установки компонентов SSClash и mihomo на OpenWRT

# 1. Запрос ссылки на подписку VPN
echo "Введите ссылку на вашу подписку VPN (например, https://example.com/subscription):"
read -r VPN_SUBSCRIPTION_URL
if [ -z "$VPN_SUBSCRIPTION_URL" ]; then
  echo "Ссылка на подписку не указана. Используется значение по умолчанию: https://google.com"
  VPN_SUBSCRIPTION_URL="https://google.com"
fi

# 2. Выбор архитектуры ядра
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
      echo "Неверный выбор. Попробуйте снова."
      ;;
  esac
done

echo "Выбрана архитектура: $KERNEL"

# 3. Настройка пароля root
echo "Установка пароля root..."
echo -e "magicrouter123@\nmagicrouter123@" | passwd root

# 4. Переименование Wi-Fi сетей
echo "Переименование Wi-Fi сетей..."
if uci show wireless | grep -q "@wifi-iface"; then
  WIFI_IFACE=$(uci show wireless | grep "@wifi-iface" | cut -d "[" -f2 | cut -d "]" -f1 | head -n 1)
  if [ -n "$WIFI_IFACE" ]; then
    WIFI_IFNAME=$(uci get wireless.@wifi-iface[$WIFI_IFACE].ifname)
    if [ -n "$WIFI_IFNAME" ] && [ -e "/sys/class/net/$WIFI_IFNAME/address" ]; then
      MAC_HASH=$(cat /sys/class/net/$WIFI_IFNAME/address | md5sum | cut -c1-6)
      SSID="MagicRouter$MAC_HASH"

      uci set wireless.@wifi-iface[0].ssid="$SSID"
      uci set wireless.@wifi-iface[1].ssid="$SSID-5G"
    else
      echo "Не удалось получить MAC-адрес Wi-Fi интерфейса."
    fi
  else
    echo "Wi-Fi интерфейсы не найдены."
  fi
else
  echo "Wi-Fi интерфейсы не найдены. Пропускаю настройку Wi-Fi."
fi

# 5. Настройка мощности сигнала Wi-Fi и паролей
echo "Настройка мощности сигнала Wi-Fi и паролей..."
for iface in $(uci show wireless | grep "@wifi-iface" | cut -d "[" -f2 | cut -d "]" -f1); do
  uci set wireless.@wifi-iface[$iface].txpower=20 # Максимальная мощность
  uci set wireless.@wifi-iface[$iface].key="MagicRouter123"
  uci set wireless.@wifi-iface[$iface].encryption="psk2"
done
uci commit wireless
wifi reload

# 6. Удаление ненужных пакетов
echo "Удаление ненужных пакетов..."
opkg remove --force-depends banip adblock watchcat https-dns-proxy ruantiblock nextdns podkop

# 7. Настройка интерфейса Luci (язык и тема)
echo "Настройка web-панели..."
uci set luci.main.lang="ru"
uci set luci.main.mediaurlbase="/luci-static/argon"
uci commit luci

# 8. Отключение интерфейса wan6 и настройка DNS для wan
echo "Настройка сетевых интерфейсов и DNS..."
uci set network.wan6.disabled=1
uci set network.wan.peerdns=0
uci del_list network.wan.dns 1>/dev/null 2>&1
uci add_list network.wan.dns='1.1.1.1'
uci add_list network.wan.dns='1.0.0.1'
uci add_list network.wan.dns='8.8.4.4'
uci add_list network.wan.dns='8.8.8.8'
uci commit network
/etc/init.d/network restart

# 9. Обновление opkg и установка необходимых пакетов
echo "Обновление opkg и установка kmod-nft-tproxy и curl..."
opkg update && opkg install kmod-nft-tproxy curl

# 10. Получение версии и установка luci-app-ssclash
echo "Получение и установка luci-app-ssclash..."
releasessclash=$(curl -s -L https://github.com/zerolabnet/SSClash/releases/latest | grep "title>Release" | cut -d " " -f 4 | cut -d "v" -f 2)
curl -L https://github.com/zerolabnet/ssclash/releases/download/v$releasessclash/luci-app-ssclash_${releasessclash}-1_all.ipk -o /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk
opkg install /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk
rm -f /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk

# 11. Остановка сервиса clash
echo "Остановка сервиса clash..."
service clash stop

# 12. Получение версии mihomo
echo "Получение версии mihomo..."
releasemihomo=$(curl -s -L https://github.com/MetaCubeX/mihomo/releases/latest | grep "title>Release" | cut -d " " -f 4)

# 13. Загрузка бинарного файла в зависимости от выбранной архитектуры
echo "Загрузка бинарника для $KERNEL..."
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

# 14. Распаковка и установка бинарника clash
echo "Распаковка и установка clash..."
mkdir -p /opt/clash/bin
gunzip -c /tmp/clash.gz > /opt/clash/bin/clash
chmod +x /opt/clash/bin/clash
rm -f /tmp/clash.gz

# 15. Запуск сервиса clash
if [ -x "/opt/clash/bin/clash" ]; then
  echo "Запуск сервиса clash..."
  service clash start
else
  echo "Бинарник clash не найден. Убедитесь, что он был установлен корректно."
fi

# 16. Обновление конфигурационного файла /opt/clash/config.yaml
echo "Настройка конфигурации Clash..."
cat << EOF > /opt/clash/config.yaml
# основные настройки
mode: rule # режим работы по правилам
ipv6: false # выключаем IPv6, т.к. он может мешать работе
log-level: error # уровень предупреждений в журнале событий
allow-lan: false # если поставить true, можно открыть SOCKS5 прокси для ваших устройств
tproxy-port: 7894 # порт прозрачного прокси
unified-delay: true # все серверы пингуются по два раза, показывая лучшую скорость
tcp-concurrent: true # многопотоковый режим (ускоряет работу)
external-controller: 0.0.0.0:9090 # адрес Dashboard панели Clash
external-ui: ./xd # папка, в которую Clash скачает файлы панели MetaCubeXD

# Блок настройки DNS
dns:
  enable: true
  listen: 0.0.0.0:7874
  ipv6: false
  enhanced-mode: fake-ip # особый режим работы Clash, использует поддельные DNS для ускорения работы, есть dns кеш, у некоторых программ и сервисов с ним могут быть сложности, если будет мешать, можно добавить исключения или полностью его отключить
  fake-ip-range: 198.18.0.1/16 # специальный диапазон ненастоящих IP адресов
  default-nameserver:
    - 1.1.1.1
    - 8.8.8.8
  nameserver:
    - https://dns10.quad9.net/dns-query
    - https://dns.aa.net.uk/dns-query
  fake-ip-filter-mode: blacklist
  fake-ip-filter:
    - '*.lan' # исключает внутренние домены .lan из fake-ip режима
    - '*.local'
    - +.msftconnecttest.com # чтобы Windows не показывал глобус вместо Wifi
    - +.3gppnetwork.org # для работы voWifi в телефонах

keep-alive-idle: 15
keep-alive-interval: 15

proxy-providers:
  t.me/VPN_Router_Best:
    type: http
    url: "$VPN_SUBSCRIPTION_URL"
    interval: 86400
    proxy: DIRECT
    header:
      User-Agent:
        - "Clash/v1.18.10"
        - "mihomo/1.18.10"
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
      - t.me/VPN_Router_Best
      
  - name: Ручной выбор
    type: select
    include-all: true
    url: http://gstatic.com/generate_204
    expected-status: 204
    interval: 300
    lazy: true
    icon: https://fastly.jsdelivr.net/gh/Koolson/Qure@master/IconSet/Color/Proxy.png
    use:
      - t.me/VPN_Router_Best

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

echo "Скрипт завершил работу."