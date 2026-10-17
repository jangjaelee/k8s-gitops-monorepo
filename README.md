# k8s-gitops-monorepo

집 홈랩 Kubernetes 클러스터의 Helm values, 매니페스트, Argo CD Application을 한곳에서 관리하는 GitOps 레포입니다.

> **public 레포입니다.** 비밀번호·토큰·개인키·kubeconfig·Secret 데이터는 커밋하지 않습니다.
> 인증서 개인키는 cert-manager가 클러스터 안에서만 만듭니다.

## 클러스터

| 항목 | 값 |
|---|---|
| 구성 | kubeadm, 4노드(control-plane 1 + worker 3), Ubuntu 24.04, 모든 노드 Wi-Fi(192.168.50.0/24) |
| Kubernetes | v1.36.0 |
| CNI | Cilium 1.20.2 — kube-proxy 대체, VXLAN, LB IPAM + L2 announcement |
| GitOps | Argo CD v3.3.8 (chart argo-cd 9.5.4) |
| Service mesh | Istio 1.30.3 sidecar 모드 + istio-cni, revision `1-30-3`(tag `default`) |
| Ingress | Gateway API v1.5.1 (Istio 구현) |
| 인증서 | cert-manager v1.20.2 + 사설 CA(`ClusterIssuer/homelab-ca`) |

## 트래픽 흐름

```
Client ──► 192.168.50.200 (Cilium LB IPAM, L2 ARP)
            └─► Service istio-system/istio-gateway-istio (LoadBalancer, Istio 자동 생성)
                 └─► Gateway istio-system/istio-gateway  (:80 HTTP, :443 HTTPS)
                      └─► HTTPRoute ─► 앱 Pod (istio-proxy sidecar, mTLS)
```

| LoadBalancer IP | 서비스 |
|---|---|
| 192.168.50.200 | Istio Gateway (`istio-system/istio-gateway-istio`) — `home.awx.kr`, `www.home.awx.kr`, `vault.awx.kr`, `argocd.awx.kr`(Google 로그인) |
| 192.168.50.201–220 | 미사용 (풀 `home-pool`) |

## 디렉터리

```
.
├── argocd/applications/   # Argo CD Application (kubectl apply로 등록)
├── argocd/repositories/   # Argo CD 저장소 등록 Secret (공개 저장소만, 인증 정보 없음)
├── helm/<release>/        # Helm values (Argo CD multi-source의 $values 또는 Helm CLI)
├── manifests/<app>/       # Helm이 아닌 매니페스트 (path 소스 Application)
├── node-config/           # 노드(OS) 설정 — Argo CD 미적용, SSH로 설치
├── .claude/agents/        # PR 리뷰·머지 에이전트
└── CLAUDE.md              # 작성 규칙 (Application, values, 작업 흐름)
```

## 구성 요소

| 이름 | 종류 | 소스 | 배포 방식 |
|---|---|---|---|
| cilium | chart cilium 1.20.2 | `helm/cilium/values.yaml` | Helm CLI |
| argocd | chart argo-cd 9.5.4 | `helm/argocd/values.yaml` | Helm CLI |
| argocd-config | Argo CD HTTPRoute(argocd.awx.kr → Gateway) | `manifests/argocd/` | Argo CD |
| cilium-lb | LB IP 풀, L2 정책 | `manifests/cilium-lb/` | Argo CD |
| local-path-provisioner | StorageClass `local-path`(기본, Retain) — GitHub 차트 v0.0.37 | `helm/local-path-provisioner/values.yaml` | Argo CD |
| gateway-api-crds | Gateway API CRD v1.5.1 standard | 공식 저장소 `config/crd/standard`(태그 v1.5.1) | Argo CD |
| cert-manager | chart cert-manager v1.20.2 | Application inline values | Argo CD |
| cert-manager-issuers | 사설 CA ClusterIssuer | `manifests/cert-manager-issuers/` | Argo CD |
| istio-base | chart base 1.30.3 | `helm/istio-base/values.yaml` | Argo CD |
| istio-cni | chart cni 1.30.3 | `helm/istio-cni/values.yaml` | Argo CD |
| istiod-1-30-3 | chart istiod 1.30.3, revision `1-30-3` | `helm/istiod-1-30-3/values.yaml` | Argo CD |
| gateways | Gateway API Gateway, 인증서 | `manifests/gateways/` | Argo CD |
| vault | chart vault 0.34.1 (Vault 2.0.4), raft 단일 노드, 자동 unseal CronJob, `vault.awx.kr` | `helm/vault/values.yaml`, `manifests/vault/` | Argo CD |
| node-local-dns | chart deliveryhero/node-local-dns 2.9.2 (OCI) + CiliumLocalRedirectPolicy | `helm/node-local-dns/values.yaml`, `manifests/node-local-dns/` | Argo CD |
| argo-rollouts | chart argo-rollouts 2.43.8 (v1.10.1) + Gateway API 플러그인 v0.17.0 | `helm/argo-rollouts/values.yaml` | Argo CD |
| kyverno | chart kyverno 3.9.1 (v1.19.1) — 엔진만, 시스템 네임스페이스는 webhook 제외 | `helm/kyverno/values.yaml` | Argo CD |
| kube-prometheus-stack | chart 84.1.0 | `helm/prometheus-operator/values.yaml` | Argo CD |
| kube-state-metrics | chart 7.4.0 | 기본값 | Argo CD |
| metric-server | chart metrics-server 3.13.0 | Application parameters | Argo CD |

Cilium과 Argo CD는 Argo CD로 관리하지 않습니다. CNI나 Argo CD가 망가졌을 때 Argo CD 없이 복구할 수 있게 Helm CLI로 직접 적용합니다.

## 작업 흐름

1. 브랜치를 만들고(`feat/…`, `fix/…`, `chore/…`, `docs/…`) 변경 후 PR을 엽니다. main에 직접 push하지 않습니다.
2. `gitops-pr-reviewer` 에이전트가 리뷰하고, 모든 검사를 통과하면 squash 머지합니다.
   ```bash
   cd k8s-gitops-monorepo && claude
   > gitops-pr-reviewer로 PR <번호> 리뷰하고 머지해줘
   ```
   검사: 변경 범위, 비밀값, YAML 문법, 차트 버전 고정, Application 규칙, `helm template`, 서버 dry-run, values 주석.
3. 머지 후 적용합니다.
   - 새 Application: `kubectl apply -f argocd/applications/<app>.yaml`
   - 기존 Argo CD 앱의 values·매니페스트 변경: Argo CD가 main을 자동 동기화
   - Cilium·Argo CD (Helm CLI)
     ```bash
     helm upgrade cilium cilium/cilium -n kube-system --version 1.20.2 -f helm/cilium/values.yaml --force-conflicts --wait
     kubectl -n kube-system rollout restart ds/cilium     # ConfigMap만 바뀐 경우
     helm upgrade argocd argo/argo-cd -n argo-cd --version 9.5.4 -f helm/argocd/values.yaml --force-conflicts --wait
     ```
     버전을 올릴 때는 `--version`과 values 파일 첫 줄 주석을 함께 바꿉니다.

## 새 클러스터에 처음부터 올릴 때

1. Cilium: `helm install cilium cilium/cilium -n kube-system --version 1.20.2 -f helm/cilium/values.yaml`
2. Argo CD 설치 후 `gateway-api-crds` 앱으로 Gateway API CRD v1.5.1 설치 (4번 첫 줄)
3. Argo CD: `helm install argocd argo/argo-cd -n argo-cd --create-namespace --version 9.5.4 -f helm/argocd/values.yaml`
4. Application 등록 순서
   ```bash
   kubectl apply -f argocd/applications/gateway-api-crds.yaml
   kubectl apply -f argocd/applications/cilium-lb.yaml
   kubectl apply -f argocd/applications/local-path-provisioner.yaml
   kubectl apply -f argocd/applications/cert-manager.yaml
   kubectl apply -f argocd/applications/cert-manager-issuers.yaml
   kubectl apply -f argocd/applications/istio-base.yaml
   kubectl apply -f argocd/applications/istio-cni.yaml
   kubectl apply -f argocd/applications/istiod-1-30-3.yaml
   kubectl apply -f argocd/applications/gateways.yaml
   kubectl apply -f argocd/applications/argocd-config.yaml
   kubectl apply -f argocd/applications/argo-rollouts.yaml
   kubectl apply -f argocd/applications/kyverno.yaml
   kubectl apply -f argocd/repositories/deliveryhero-oci.yaml -f argocd/applications/node-local-dns.yaml   # Cilium localRedirectPolicies 필요
   kubectl apply -f argocd/applications/vault.yaml       # 이후 vault operator init + Secret vault-unseal-keys 생성
   kubectl apply -f argocd/applications/kube-state-metrics.yaml -f argocd/applications/metric-server.yaml -f argocd/applications/kube-prometheus-stack.yaml
   ```

## 앱을 Gateway에 붙이기

```yaml
# 네임스페이스에 sidecar 주입 (Istio revision 1-30-3)
apiVersion: v1
kind: Namespace
metadata:
  name: my-app
  labels:
    istio.io/rev: 1-30-3
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: my-app
  namespace: my-app
spec:
  parentRefs:
    - name: istio-gateway
      namespace: istio-system
  hostnames: ["home.awx.kr"]
  rules:
    - backendRefs:
        - name: my-app
          port: 80
```

## 사설 CA 신뢰 등록 (브라우저 경고 없애기)

```bash
kubectl -n cert-manager get secret homelab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > homelab-root-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain homelab-root-ca.crt   # macOS
```

## Argo CD Google 로그인

- OIDC 직접 연동(Dex 미사용). OAuth 클라이언트는 GCP 프로젝트 `alex-space-0001`, 동의 화면 Testing(테스트 사용자만 로그인).
- client secret은 레포 밖 Secret `argo-cd/argocd-oidc-google`(키 `clientSecret`, 라벨 `app.kubernetes.io/part-of=argocd`)에 둡니다.
  ```bash
  kubectl -n argo-cd create secret generic argocd-oidc-google --from-literal=clientSecret="$(jq -r .web.client_secret client_secret_*.json)"
  kubectl -n argo-cd label secret argocd-oidc-google app.kubernetes.io/part-of=argocd
  ```
- RBAC: `policy.default`는 빈 값(권한 없음). 관리자는 `helm/argocd/values.yaml`의 `policy.csv`에 이메일로 추가합니다.

## 알려진 제약

- **Wi-Fi 노드와 L2 announcement**: worker-01/02(Broadcom `brcmfmac`)는 promiscuous 모드가 꺼져 있으면 LB IP의 ARP 요청을 받지 못해, 모든 노드에 `wifi-promisc.service`를 둡니다(`node-config/wifi-promisc/`).
- 사설 CA 인증서이므로 CA를 신뢰 등록하지 않은 기기에서는 인증서 경고가 납니다.
