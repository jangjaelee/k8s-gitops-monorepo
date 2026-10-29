#!/bin/bash
# 사용: cluster/home-k8s/node-config/etcd-backup/install.sh
# master-node-01에 스크립트·systemd 타이머를 깔고, worker-node-02를 사본 받는 곳으로 준비한 뒤 한 번 돌린다.
# 사본용 SSH 키는 master에서 만들고 개인키는 master 밖으로 나오지 않는다(공개키만 옮김).
set -euo pipefail
cd "$(dirname "$0")"
MASTER=linux@192.168.50.101
COPY=linux@192.168.50.112
COPY_IP=192.168.50.112

scp -q etcd-backup.sh etcd-backup.service etcd-backup.timer "$MASTER:/tmp/"
ssh "$MASTER" 'sudo install -m 755 /tmp/etcd-backup.sh /usr/local/sbin/etcd-backup.sh
  sudo install -m 644 /tmp/etcd-backup.service /tmp/etcd-backup.timer /etc/systemd/system/
  rm -f /tmp/etcd-backup.sh /tmp/etcd-backup.service /tmp/etcd-backup.timer
  sudo install -d -m 700 /root/.ssh
  sudo test -f /root/.ssh/etcd-backup_ed25519 || sudo ssh-keygen -q -t ed25519 -N "" -C etcd-backup@master-node-01 -f /root/.ssh/etcd-backup_ed25519'

PUB=$(ssh "$MASTER" 'sudo cat /root/.ssh/etcd-backup_ed25519.pub')
LINE="command=\"/usr/bin/rrsync -wo /var/backups/etcd-master\",restrict $PUB"
ssh "$COPY" "sudo install -d -m 700 /var/backups/etcd-master /root/.ssh
  sudo grep -qF '$PUB' /root/.ssh/authorized_keys 2>/dev/null || echo '$LINE' | sudo tee -a /root/.ssh/authorized_keys >/dev/null"

# master root가 worker-node-02 호스트 키를 미리 알게 한다(BatchMode라 처음 접속에서 묻지 못함)
ssh "$MASTER" "sudo ssh-keygen -F $COPY_IP -f /root/.ssh/known_hosts >/dev/null 2>&1 || ssh-keyscan -t ed25519 $COPY_IP 2>/dev/null | sudo tee -a /root/.ssh/known_hosts >/dev/null"

ssh "$MASTER" 'sudo systemctl daemon-reload && sudo systemctl enable --now etcd-backup.timer && sudo systemctl start etcd-backup.service
  sudo journalctl -u etcd-backup.service -n 20 --no-pager -o cat; systemctl list-timers etcd-backup.timer --no-pager'
