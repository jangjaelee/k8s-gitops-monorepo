#!/bin/bash
# home-k8s etcd 백업(master-node-01에서 root로 실행). etcd-backup.timer가 매일 03:10에 돌린다.
# 1) etcd 스냅샷 2) /etc/kubernetes(PKI·kubeconfig·static Pod 매니페스트)와 kubelet 설정·인증서 tar 3) 14일 넘은 것 지움 4) worker-node-02로 사본
# 결과물에는 모든 Secret과 CA 개인키가 들어 있다. root 700/600으로만 두고 레포에는 절대 넣지 않는다.
set -euo pipefail

DEST=/var/backups/etcd
KEEP_DAYS=14
COPY_TO=root@192.168.50.112                 # worker-node-02. authorized_keys의 rrsync가 /var/backups/etcd-master에만 쓰게 막는다
COPY_KEY=/root/.ssh/etcd-backup_ed25519
CRI=(crictl --runtime-endpoint unix:///run/containerd/containerd.sock)
ETCDCTL_TLS=(--endpoints=https://127.0.0.1:2379
  --cacert=/etc/kubernetes/pki/etcd/ca.crt
  --cert=/etc/kubernetes/pki/etcd/server.crt
  --key=/etc/kubernetes/pki/etcd/server.key)

TS=$(date +%Y%m%d-%H%M)
install -d -m 700 "$DEST"

id=$("${CRI[@]}" ps --name '^etcd$' -q 2>/dev/null | head -1)
[ -n "$id" ] || { echo "etcd 컨테이너를 찾지 못함" >&2; exit 1; }

# etcd 이미지에는 셸이 없어 컨테이너가 마운트한 /var/lib/etcd(hostPath)에 쓰고 호스트에서 옮긴다
TMP=/var/lib/etcd/backup-$TS.db
trap 'rm -f "$TMP"' EXIT
"${CRI[@]}" exec "$id" etcdctl "${ETCDCTL_TLS[@]}" snapshot save "$TMP"
"${CRI[@]}" exec "$id" etcdutl snapshot status "$TMP" -w table   # 깨진 스냅샷이면 여기서 실패

install -m 600 "$TMP" "$DEST/etcd-$TS.db"
# 노드를 새로 깔았을 때 kubeadm init 없이 kubelet이 static Pod를 다시 띄우려면 kubelet 설정·클라이언트 인증서도 필요하다
tar -C / -czf "$DEST/kubernetes-etc-$TS.tar.gz" etc/kubernetes \
  var/lib/kubelet/config.yaml var/lib/kubelet/kubeadm-flags.env var/lib/kubelet/pki
chmod 600 "$DEST/kubernetes-etc-$TS.tar.gz"

find "$DEST" -maxdepth 1 -type f -mtime +$((KEEP_DAYS - 1)) -delete

rsync -a --delete -e "ssh -i $COPY_KEY -o BatchMode=yes -o ConnectTimeout=10" "$DEST/" "$COPY_TO:"
echo "백업 완료: $DEST/etcd-$TS.db ($(du -h "$DEST/etcd-$TS.db" | cut -f1)), 사본 worker-node-02:/var/backups/etcd-master"
