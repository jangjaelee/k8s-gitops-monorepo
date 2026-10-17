#!/bin/sh
# 모든 Wi-Fi 인터페이스(wl*)에 promiscuous 모드를 켠다.
# 이유: brcmfmac(worker-01/02)는 promisc가 꺼져 있으면 노드 IP가 아닌 주소(Cilium LB VIP)의
#       ARP 요청을 받지 못한다. 4노드 모두 같은 설정으로 맞춘다. (my-k8s/CLAUDE.md 참고)
for path in /sys/class/net/wl*; do
  [ -e "$path" ] || continue
  ip link set "$(basename "$path")" promisc on
done
