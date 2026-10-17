#!/bin/bash
# Mac에서 실행: ./install.sh k8s-master-01 k8s-worker-01 ...
set -euo pipefail
cd "$(dirname "$0")"
for h in "$@"; do
  echo "== $h"
  scp -q wifi-promisc.sh wifi-promisc.service 90-wifi-promisc "$h":/tmp/
  ssh "$h" 'set -e
    sudo install -o root -g root -m 0755 /tmp/wifi-promisc.sh /usr/local/sbin/wifi-promisc.sh
    sudo install -o root -g root -m 0644 /tmp/wifi-promisc.service /etc/systemd/system/wifi-promisc.service
    sudo install -o root -g root -m 0755 /tmp/90-wifi-promisc /etc/NetworkManager/dispatcher.d/90-wifi-promisc
    rm -f /tmp/wifi-promisc.sh /tmp/wifi-promisc.service /tmp/90-wifi-promisc
    sudo systemctl daemon-reload
    sudo systemctl enable --now wifi-promisc.service
    systemctl is-active wifi-promisc.service
    for p in /sys/class/net/wl*; do i=$(basename $p); echo "$i $(ip -d link show $i | grep -o "promiscuity [0-9]*")"; done'
done
