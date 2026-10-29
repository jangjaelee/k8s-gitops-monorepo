# etcd-backup

home-k8s는 control plane이 master-node-01 한 대뿐이라, 이 노드가 고장 나면 etcd를 백업에서 복원해야 합니다.
이 폴더는 etcd 스냅샷과 `/etc/kubernetes`를 매일 백업하고, 다른 노드와 맥에 사본을 두는 설정입니다.

**백업 파일에는 모든 Secret 값과 클러스터 CA 개인키가 들어 있습니다.** root 700/600으로만 두고, 레포·채팅·이슈에 절대 올리지 않습니다.

## 구성

| 위치 | 내용 | 보존 |
|---|---|---|
| master-node-01 `/var/backups/etcd/` | `etcd-YYYYmmdd-HHMM.db`(스냅샷), `kubernetes-etc-YYYYmmdd-HHMM.tar.gz`(PKI·kubeconfig·static Pod 매니페스트) | 14일 |
| worker-node-02 `/var/backups/etcd-master/` | master와 같은 내용(rsync `--delete`) | 14일 |
| 맥 `~/Workspace/Alex/my-k8s/backups/etcd/` | master에서 당겨 온 사본(레포 밖) | 14일 |

- master: `etcd-backup.timer`가 매일 **03:10**에 `/usr/local/sbin/etcd-backup.sh`를 실행합니다(놓치면 부팅 뒤 실행, `Persistent=true`).
  etcd 이미지에 셸이 없어 `crictl exec`로 컨테이너 안의 `etcdctl snapshot save`·`etcdutl snapshot status`를 씁니다.
- worker-node-02: master root의 전용 키(`/root/.ssh/etcd-backup_ed25519`)만 받고, `authorized_keys`의 `rrsync -wo`로 `/var/backups/etcd-master`에 쓰기만 허용합니다.
- 맥: launchd `kr.awx.etcd-backup-pull`이 매일 **09:30**에 Apple 기본 `ssh`·`rsync`로 당겨 옵니다(맥이 잠들어 있었으면 깨어날 때).

## 설치

레포 루트에서 실행합니다.

```bash
cluster/home-k8s/node-config/etcd-backup/install.sh          # master·worker-node-02 설치 + 한 번 실행
cluster/home-k8s/node-config/etcd-backup/mac/install-mac.sh  # 맥 launchd 등록 + 한 번 실행
```

## 확인

```bash
ssh linux@192.168.50.101 'systemctl list-timers etcd-backup.timer; sudo journalctl -u etcd-backup.service -n 20 -o cat'
ssh linux@192.168.50.112 'sudo ls -lh /var/backups/etcd-master'
tail ~/Library/Logs/etcd-backup-pull.log
```

## 복원(master-node-01, 같은 IP·호스트 이름)

etcd 멤버는 `master-node-01`, 피어 주소는 `https://192.168.50.101:2380`입니다. 노드를 새로 깔았다면 kubeadm·kubelet·containerd를 같은 판(1.36.0)으로 먼저 설치하고 `kubeadm init`은 하지 않습니다.

1. 노드를 새로 깔았으면 `/etc/kubernetes`를 되돌립니다: `sudo tar -C / -xzf kubernetes-etc-<시각>.tar.gz`
2. control plane을 멈춥니다: `sudo mkdir -p /root/manifests.off && sudo mv /etc/kubernetes/manifests/*.yaml /root/manifests.off/` 뒤 `sudo crictl ps`에서 etcd·kube-apiserver가 사라질 때까지 기다립니다.
3. 스냅샷을 새 데이터 디렉터리로 복원합니다(호스트에 etcdutl이 없으면 etcd 이미지로 실행):
   ```bash
   sudo ctr -n k8s.io images pull registry.k8s.io/etcd:3.6.8-0
   sudo ctr -n k8s.io run --rm --mount type=bind,src=/var/lib,dst=/var/lib,options=rbind:rw \
     --mount type=bind,src=/var/backups/etcd,dst=/backup,options=rbind:ro \
     registry.k8s.io/etcd:3.6.8-0 etcd-restore etcdutl snapshot restore /backup/etcd-<시각>.db \
     --data-dir /var/lib/etcd-restore --name master-node-01 \
     --initial-cluster master-node-01=https://192.168.50.101:2380 \
     --initial-advertise-peer-urls https://192.168.50.101:2380
   ```
4. 데이터 디렉터리를 바꿉니다: `sudo mv /var/lib/etcd /var/lib/etcd.old-$(date +%Y%m%d%H%M) && sudo mv /var/lib/etcd-restore /var/lib/etcd`
5. control plane을 되돌립니다: `sudo mv /root/manifests.off/*.yaml /etc/kubernetes/manifests/`
6. 확인: `kubectl --context home-k8s get nodes`, `kubectl get pods -A`, Argo CD 앱 상태. 스냅샷 이후 바뀐 것은 Argo CD가 레포 기준으로 다시 맞춥니다(레포 밖 kubectl 변경은 사라질 수 있음).

스냅샷 시각 이후의 변경(최대 하루)은 잃습니다. 큰 변경 직전에는 `sudo systemctl start etcd-backup.service`로 한 번 더 받습니다.
