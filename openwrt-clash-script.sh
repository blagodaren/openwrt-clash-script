#!/bin/sh
# Скрипт для обновления и установки компонентов SSClash и mihomo на OpenWRT

# 1. Выбор архитектуры ядра
echo "Выберите архитектуру ядра:"
select KERNEL in mipsel_24kc arm64 Amd64; do
  case "$KERNEL" in
    mipsel_24kc|arm64|Amd64)
      echo "Выбрана архитектура: $KERNEL"
      break
      ;;
    *)
      echo "Неверный выбор. Попробуйте снова."
      ;;
  esac
done

# 2. Настройка пароля root
echo "Установка пароля root..."
echo -e "magicrouter123@\nmagicrouter123@" | passwd root

# 3. Переименование Wi-Fi сетей
echo "Переименование Wi-Fi сетей..."
MAC_HASH=$(cat /sys/class/net/$(uci get wireless.@wifi-iface[0].ifname)/address | md5sum | cut -c1-6)
SSID="MagicRouter$MAC_HASH"

uci set wireless.@wifi-iface[0].ssid="$SSID"
uci set wireless.@wifi-iface[1].ssid="$SSID-5G"

# 4. Настройка мощности сигнала Wi-Fi и паролей
echo "Настройка мощности сигнала Wi-Fi и паролей..."
for iface in $(uci show wireless | grep "@wifi-iface" | cut -d "[" -f2 | cut -d "]" -f1); do
  uci set wireless.@wifi-iface[$iface].txpower=20 # Максимальная мощность
  uci set wireless.@wifi-iface[$iface].key="MagicRouter123"
  uci set wireless.@wifi-iface[$iface].encryption="psk2"
done
uci commit wireless
wifi reload

# 5. Удаление ненужных пакетов
echo "Удаление ненужных пакетов..."
opkg remove banip adblock watchcat https-dns-proxy ruantiblock nextdns podkop

# 6. Настройка интерфейса Luci (язык и тема)
echo "Настройка web-панели..."
uci set luci.main.lang="ru"
uci set luci.main.mediaurlbase="/luci-static/argon"
uci commit luci

# 7. Отключение интерфейса wan6 и настройка DNS для wan
echo "Настройка сетевых интерфейсов и DNS..."
uci set network.wan6.disabled=1
uci set network.wan.peerdns=0
# Удаляем возможные предыдущие DNS-серверы
uci del_list network.wan.dns 1>/dev/null 2>&1
uci add_list network.wan.dns='1.1.1.1'
uci add_list network.wan.dns='1.0.0.1'
uci add_list network.wan.dns='8.8.4.4'
uci add_list network.wan.dns='8.8.8.8'
uci commit network
/etc/init.d/network restart

# 8. Обновление opkg и установка необходимых пакетов
echo "Обновление opkg и установка kmod-nft-tproxy и curl..."
opkg update && opkg install kmod-nft-tproxy curl

# 9. Получение версии и установка luci-app-ssclash
echo "Получение и установка luci-app-ssclash..."
releasessclash=$(curl -s -L https://github.com/zerolabnet/SSClash/releases/latest | grep "title>Release" | cut -d " " -f 4 | cut -d "v" -f 2)
curl -L https://github.com/zerolabnet/ssclash/releases/download/v$releasessclash/luci-app-ssclash_${releasessclash}-1_all.ipk -o /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk
opkg install /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk
rm -f /tmp/luci-app-ssclash_${releasessclash}-1_all.ipk

# 10. Остановка сервиса clash
echo "Остановка сервиса clash..."
service clash stop

# 11. Получение версии mihomo
echo "Получение версии mihomo..."
releasemihomo=$(curl -s -L https://github.com/MetaCubeX/mihomo/releases/latest | grep "title>Release" | cut -d " " -f 4)

# 12. Загрузка бинарного файла в зависимости от выбранной архитектуры
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

# 13. Распаковка и установка бинарника clash
echo "Распаковка и установка clash..."
mkdir -p /opt/clash/bin
gunzip -c /tmp/clash.gz > /opt/clash/bin/clash
chmod +x /opt/clash/bin/clash
rm -f /tmp/clash.gz

# 14. Обновление конфигурационного файла /opt/clash/config.yaml
echo "Настройка конфигурации Clash..."
cat << 'EOF' > /opt/clash/config.yaml
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
    url: "https://google.com"
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