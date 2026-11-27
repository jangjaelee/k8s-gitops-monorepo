# kube-apiserver 감사 로그 (M58 ④, 2026-11-27 PM 승인)

master-node-01에 SSH로 설치한다(Argo CD 미적용). 적용하면 kube-apiserver static Pod가 다시 시작돼 API가 약 30~60초 끊긴다(제어 평면 1대) → :35 창에서.

1. `/etc/kubernetes/manifests/kube-apiserver.yaml` 백업(`/root/kube-apiserver.yaml.bak-<날짜>`, manifests 폴더 밖)
2. `audit-policy.yaml` → `/etc/kubernetes/audit-policy.yaml`, `mkdir -p /var/log/kubernetes/audit`
3. kube-apiserver 플래그: `--audit-policy-file=/etc/kubernetes/audit-policy.yaml`, `--audit-log-path=/var/log/kubernetes/audit/audit.log`, `--audit-log-maxsize=100`, `--audit-log-maxbackup=20`, `--audit-log-maxage=7`
4. hostPath 마운트 2개: `/etc/kubernetes/audit-policy.yaml`(File, readOnly), `/var/log/kubernetes/audit`(DirectoryOrCreate)
5. 확인: apiserver Ready, `audit.log` 쌓임, Loki `{job="kube-apiserver-audit"}` 조회

되돌리기: 1의 백업을 manifests로 복원(kubelet이 자동 재시작). 양: 11-27 측정 제외 뒤 약 15 req/s → 하루 약 130만 건·1.3GB 원본, 노드 파일 상한 2GB, Loki 압축 약 130MB/일.
