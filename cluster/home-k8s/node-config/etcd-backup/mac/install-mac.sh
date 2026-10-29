#!/bin/bash
# 사용: cluster/home-k8s/node-config/etcd-backup/mac/install-mac.sh  (맥에서, 레포 안에서 실행)
set -euo pipefail
REPO=$(cd "$(dirname "$0")/../../../../.." && pwd)
P="$HOME/Library/LaunchAgents/kr.awx.etcd-backup-pull.plist"
sed -e "s|__REPO__|$REPO|" -e "s|__HOME__|$HOME|g" "$(dirname "$0")/kr.awx.etcd-backup-pull.plist" > "$P"
launchctl bootout "gui/$(id -u)" "$P" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$P"
launchctl kickstart -k "gui/$(id -u)/kr.awx.etcd-backup-pull"
