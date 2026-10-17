#!/bin/bash
# Mac에서 실행: ./lock.sh <SSH 호스트> <BSSID>      예) ./lock.sh k8s-worker-03 FC:34:97:2E:B7:CC
#            ./lock.sh <SSH 호스트> --unlock       고정 해제(로밍·주기 스캔 복원)
# NetworkManager Wi-Fi 연결을 한 AP(BSSID)에 고정해 주기 스캔을 멈춘다. 이유는 README.md.
# 안전장치: 변경 전에 4분 뒤 원래대로 되돌리는 타이머를 걸고, 재접속을 확인한 뒤에만 해제한다.
set -euo pipefail
h=${1:?SSH host}; b=${2:?BSSID or --unlock}
[ "$b" = "--unlock" ] && b=""

conn=$(ssh "$h" 'dev=$(ls /sys/class/net | grep "^wl" | head -1); nmcli -t -f NAME,DEVICE con show --active | awk -F: -v d="$dev" "\$2==d{print \$1}"')
[ -n "$conn" ] || { echo "활성 Wi-Fi 연결을 못 찾음"; exit 1; }
old=$(ssh "$h" "nmcli -g 802-11-wireless.bssid con show '$conn' | tr -d '\\\\'")
echo "== $h  연결=$conn  현재 bssid=${old:-없음}  → ${b:-없음}"

ssh "$h" "sudo systemctl stop wifi-bssid-rollback.timer 2>/dev/null || true
  sudo systemd-run --unit=wifi-bssid-rollback --on-active=240 /bin/sh -c \"nmcli con mod '$conn' 802-11-wireless.bssid '$old' && nmcli con up '$conn'\" >/dev/null
  sudo systemd-run --unit=wifi-bssid-apply --on-active=3 /bin/sh -c \"nmcli con mod '$conn' 802-11-wireless.bssid '$b' && nmcli con up '$conn'\" >/dev/null"

sleep 15
for i in $(seq 1 20); do
  if ssh -o ConnectTimeout=4 "$h" "nmcli -g 802-11-wireless.bssid con show '$conn' | tr -d '\\\\' | grep -qix '${b:-}' && iw dev \$(ls /sys/class/net | grep '^wl' | head -1) link | grep -q Connected" 2>/dev/null; then
    ssh "$h" 'sudo systemctl stop wifi-bssid-rollback.timer; iw dev $(ls /sys/class/net | grep "^wl" | head -1) link | head -1'
    echo "적용 완료, 되돌림 타이머 해제. 다음: 이 노드의 cilium-agent 재시작"
    exit 0
  fi
  sleep 5
done
echo "재접속 확인 실패 — 4분 타이머가 원래 설정으로 되돌린다"; exit 1
