#!/bin/sh
# lab 노드에서 실행. worker-node-02의 PoC 덤프를 받아 온다. 원본이 비어도 사본이 지워지지 않게 --delete를 쓰지 않는다.
set -eu
. /etc/infralens-backup-pull.conf   # SRC=<사용자>@192.168.50.112  키는 ~/.ssh/id_ed25519
D=/var/lib/infralens-poc-backup
rsync -a -e "ssh -o BatchMode=yes" "$SRC:" "$D/"
new=$(find "$D" -name 'infralens-*.dump' -mtime -2 | wc -l)
[ "$new" -gt 0 ] || { echo "최근 덤프 없음, 정리 안 함"; exit 1; }
find "$D/daily" -name 'infralens-*.dump' -mtime +8 -delete
find "$D/weekly" -name 'infralens-*.dump' -mtime +30 -delete 2>/dev/null || true
