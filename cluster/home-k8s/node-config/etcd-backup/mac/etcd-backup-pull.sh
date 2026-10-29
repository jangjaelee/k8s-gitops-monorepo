#!/bin/bash
# 맥에서 master-node-01의 etcd 백업을 당겨 온다(launchd kr.awx.etcd-backup-pull이 매일 09:30에 실행, 잠들어 놓쳤으면 깨어날 때).
# Apple 기본 ssh·rsync만 쓴다(비 Apple 바이너리는 맥 "로컬 네트워크" 권한 문제로 LAN 연결이 막힐 수 있음).
set -euo pipefail
DEST="$HOME/Workspace/Alex/my-k8s/backups/etcd"   # 레포 밖. 모든 Secret·CA 개인키가 들어 있음
KEEP_DAYS=14
mkdir -p "$DEST"; chmod 700 "$DEST"
/usr/bin/rsync -a -e "/usr/bin/ssh -o BatchMode=yes -o ConnectTimeout=10" --rsync-path="sudo rsync" \
  linux@192.168.50.101:/var/backups/etcd/ "$DEST/"
chmod 600 "$DEST"/* 2>/dev/null || true
find "$DEST" -maxdepth 1 -type f -mtime +$((KEEP_DAYS - 1)) -delete
echo "$(date '+%F %T') 당김: $(ls "$DEST" | grep -c '^etcd-.*\.db$')개, 최신 $(ls -t "$DEST"/etcd-*.db | head -1 | xargs basename)"
