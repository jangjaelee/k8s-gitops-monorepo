# home-k8s

집 홈랩 Kubernetes 클러스터 `home-k8s`의 플랫폼 구성요소 명세입니다. 이 폴더에는 이 클러스터에 배포하는 모든 것을 둡니다.
구성요소의 버전이나 Argo CD Application이 바뀌면 **같은 PR에서 이 문서도 갱신합니다**(리뷰 에이전트 검사 9번).

> 이 폴더 안 파일 주석에 적은 경로(`helm/...`, `manifests/...`, `argocd/applications/...`)는 이 폴더 기준입니다.
> Application의 `path`와 `$values` 경로는 레포 루트 기준(`cluster/home-k8s/...`)입니다.

## 클러스터

| 항목 | 값 |
|---|---|
| 구성 | kubeadm, 4노드(control-plane 1 + worker 3), Ubuntu 24.04, 모든 노드 Wi-Fi(192.168.50.0/24) |
| Kubernetes | v1.36.0 |
| 컨테이너 런타임 | containerd 2.3.6 |
| CNI | Cilium 1.20.2 — kube-proxy 대체, VXLAN, LB IPAM + L2 announcement, Local Redirect Policy |
| GitOps | Argo CD v3.3.8 (chart argo-cd 9.5.4, `https://argocd.awx.kr`, Google 로그인) |
| Service mesh | Istio 1.30.3 sidecar 모드 + istio-cni, revision `1-30-3`(tag `default`) |
| Ingress | Gateway API v1.5.1 (Istio 구현), Gateway `istio-system/istio-gateway` |
| 인증서 | cert-manager v1.20.2 + 사설 CA(`ClusterIssuer/homelab-ca`) |
| 스토리지 | local-path-provisioner v0.0.37 (기본 StorageClass `local-path`, Retain) |

## 폴더 구성

```
cluster/home-k8s/
├── README.md                  # 이 문서 (구성요소·버전·Application 명세)
├── argocd/
│   ├── applications/          # Argo CD Application (kubectl apply로 등록)
│   └── repositories/          # Argo CD 저장소 등록 Secret (공개 저장소만, 인증 정보 없음)
├── helm/<release>/            # Helm values (Argo CD multi-source의 $values 또는 Helm CLI)
├── manifests/<app>/           # Helm이 아닌 매니페스트 (path 소스 Application)
└── node-config/               # 노드(OS) 설정 — Argo CD 미적용, SSH로 설치
```

## 구성요소 명세

### Helm CLI로 관리 (Argo CD 미관리)

CNI나 Argo CD가 망가져도 Argo CD 없이 복구할 수 있게 Helm CLI로 직접 적용합니다.

| Release | 네임스페이스 | 차트 | 앱 버전 | values |
|---|---|---|---|---|
| cilium | kube-system | cilium/cilium 1.20.2 | 1.20.2 | `helm/cilium/values.yaml` |
| argocd | argo-cd | argo/argo-cd 9.5.4 | v3.3.8 | `helm/argocd/values.yaml` |

### Argo CD Application

모든 앱: `metadata.namespace: argo-cd`, automated sync(prune, selfHeal), `ServerSideApply=true`.

| Application | Project | 네임스페이스 | 소스(차트·버전 / 경로) | 앱 버전 | 이 레포의 values·매니페스트 | 비고 |
|---|---|---|---|---|---|---|
| gateway-api-crds | system | (cluster) | github.com/kubernetes-sigs/gateway-api `config/crd/standard` @ v1.5.1 | v1.5.1 | — | prune 끔 |
| cilium-lb | system | (cluster) | 이 레포 path @ main | — | `manifests/cilium-lb/` | LB IP 풀 .200–.220, L2 정책 |
| local-path-provisioner | system | local-path-storage | github.com/rancher/local-path-provisioner `deploy/chart` @ v0.0.37 | v0.0.37 | `helm/local-path-provisioner/values.yaml` | 기본 StorageClass |
| cert-manager | system | cert-manager | jetstack/cert-manager v1.20.2 | v1.20.2 | Application inline values | |
| cert-manager-issuers | system | cert-manager | 이 레포 path @ main | — | `manifests/cert-manager-issuers/` | 사설 CA `homelab-ca` |
| istio-base | system | istio-system | istio/base 1.30.3 | 1.30.3 | `helm/istio-base/values.yaml` | `defaultRevision: 1-30-3` |
| istio-cni | system | istio-system | istio/cni 1.30.3 | 1.30.3 | `helm/istio-cni/values.yaml` | Cilium 체이닝 |
| istiod-1-30-3 | system | istio-system | istio/istiod 1.30.3 | 1.30.3 | `helm/istiod-1-30-3/values.yaml` | revision `1-30-3`, tag `default` |
| gateways | system | istio-system | 이 레포 path @ main | proxyv2 1.30.3 | `manifests/gateways/` | Gateway, 인증서, HTTP→HTTPS 리다이렉트 |
| argocd-config | system | argo-cd | 이 레포 path @ main | — | `manifests/argocd/` | HTTPRoute `argocd.awx.kr` |
| argo-rollouts | system | argo-rollouts | argo/argo-rollouts 2.43.8 | v1.10.1 | `helm/argo-rollouts/values.yaml` | Gateway API 플러그인 v0.17.0 |
| kyverno | system | kyverno | kyverno/kyverno 3.9.1 | v1.19.1 | `helm/kyverno/values.yaml` | 엔진, `ServerSideDiff=true` |
| kyverno-policies | system | kyverno | kyverno/kyverno-policies 3.9.1 + 이 레포 path | v1.19.1 | `helm/kyverno-policies/values.yaml`, `manifests/kyverno-policies/` | PSS restricted 17개 + 모범 사례 2개, **모두 Audit**, `ServerSideDiff=true` |
| node-local-dns | system | kube-system | deliveryhero/node-local-dns 2.9.2 (OCI) + 이 레포 path | k8s-dns-node-cache 1.26.7 | `helm/node-local-dns/values.yaml`, `manifests/node-local-dns/` | Cilium LRP |
| vault | system | vault | hashicorp/vault 0.34.1 + 이 레포 path | Vault 2.0.4 | `helm/vault/values.yaml`, `manifests/vault/` | raft 단일 노드, 자동 unseal CronJob |
| kube-state-metrics | system | kube-system | prometheus-community/kube-state-metrics 7.4.0 | v2.19.0 | 기본값 | |
| metric-server | o11y | kube-system | metrics-server/metrics-server 3.13.0 | v0.8.0 | Application parameters | |
| kube-prometheus-stack | o11y | prometheus-operator | prometheus-community/kube-prometheus-stack 84.1.0 | operator v0.90.1 | `helm/prometheus-operator/values.yaml` | |

### Argo CD 저장소 등록

| 파일 | 저장소 | 용도 |
|---|---|---|
| `argocd/repositories/deliveryhero-oci.yaml` | `ghcr.io/deliveryhero/helm-charts` (OCI, 공개) | node-local-dns 차트 |

## 외부 노출

모든 외부 접속은 Istio Gateway 하나(LB IP `192.168.50.200`)로 들어옵니다. DNS A 레코드는 hosting.co.kr에 등록합니다.

```
Client ──► 192.168.50.200 (Cilium LB IPAM, L2 ARP)
            └─► Service istio-system/istio-gateway-istio (LoadBalancer, Istio 자동 생성)
                 └─► Gateway istio-system/istio-gateway  (:80 HTTP, :443 HTTPS, 호스트별 listener)
                      └─► HTTPRoute ─► Service ─► Pod
```

| 호스트 | Listener | 인증서(istio-system) | HTTPRoute | 백엔드 |
|---|---|---|---|---|
| `home.awx.kr`, `www.home.awx.kr` | `http`, `https` | `istio-gateway-tls` | 앱별 | 테스트용, HTTP 허용 |
| `vault.awx.kr` | `https-vault` | `vault-gateway-tls` | `vault/vault` | `vault:8200` |
| `argocd.awx.kr` | `https-argocd` | `argocd-gateway-tls` | `argo-cd/argocd-server` | `argocd-server:80`(`server.insecure`) |

- `vault.awx.kr`, `argocd.awx.kr`는 :80 요청을 https로 301 리다이렉트합니다(`manifests/gateways/http-redirect.yaml`).
- LB IP `192.168.50.201–220`은 비어 있습니다(풀 `home-pool`).

## 작업 흐름

1. 브랜치를 만들고 PR을 엽니다. `gitops-pr-reviewer` 에이전트가 리뷰하고 squash 머지합니다.
2. 머지 후 적용합니다. 명령은 레포 루트에서 실행합니다.
   - 새 Application 또는 Application 파일 변경: `kubectl apply -f cluster/home-k8s/argocd/applications/<app>.yaml`
   - 기존 앱의 values·매니페스트 변경: Argo CD가 main을 자동 동기화합니다.
   - Cilium·Argo CD (Helm CLI)
     ```bash
     helm upgrade cilium cilium/cilium -n kube-system --version 1.20.2 -f cluster/home-k8s/helm/cilium/values.yaml --force-conflicts --wait
     kubectl -n kube-system rollout restart ds/cilium     # ConfigMap만 바뀐 경우
     helm upgrade argocd argo/argo-cd -n argo-cd --version 9.5.4 -f cluster/home-k8s/helm/argocd/values.yaml --force-conflicts --wait
     ```
     버전을 올릴 때는 `--version`, values 파일 첫 줄 주석, 이 문서를 함께 바꿉니다. Argo CD 업그레이드는 Helm hook 대기 때문에 20분쯤 걸립니다.

## 처음부터 올릴 때

레포 루트에서 실행합니다(`C=cluster/home-k8s`).

1. Cilium: `helm install cilium cilium/cilium -n kube-system --version 1.20.2 -f $C/helm/cilium/values.yaml`
2. Argo CD: `helm install argocd argo/argo-cd -n argo-cd --create-namespace --version 9.5.4 -f $C/helm/argocd/values.yaml`
3. Application 등록 순서
   ```bash
   A=$C/argocd/applications
   kubectl apply -f $A/gateway-api-crds.yaml
   kubectl apply -f $A/cilium-lb.yaml
   kubectl apply -f $A/local-path-provisioner.yaml
   kubectl apply -f $A/cert-manager.yaml
   kubectl apply -f $A/cert-manager-issuers.yaml
   kubectl apply -f $A/istio-base.yaml
   kubectl apply -f $A/istio-cni.yaml
   kubectl apply -f $A/istiod-1-30-3.yaml
   kubectl apply -f $A/gateways.yaml
   kubectl apply -f $A/argocd-config.yaml
   kubectl apply -f $A/argo-rollouts.yaml
   kubectl apply -f $A/kyverno.yaml -f $A/kyverno-policies.yaml   # 정책은 엔진(CRD) 다음
   kubectl apply -f $C/argocd/repositories/deliveryhero-oci.yaml -f $A/node-local-dns.yaml   # Cilium localRedirectPolicies 필요
   kubectl apply -f $A/vault.yaml       # 이후 vault operator init + Secret vault-unseal-keys 생성
   kubectl apply -f $A/kube-state-metrics.yaml -f $A/metric-server.yaml -f $A/kube-prometheus-stack.yaml
   ```
4. 노드 설정: `$C/node-config/wifi-promisc/install.sh <SSH 호스트...>`

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

새 HTTPS 전용 호스트는 Gateway에 호스트별 listener와 인증서(`manifests/gateways/`)를 추가하고, `http-redirect.yaml`의 hostnames에도 넣습니다.

## 사설 CA 신뢰 등록 (브라우저 경고 없애기)

```bash
kubectl -n cert-manager get secret homelab-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > homelab-root-ca.crt
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain homelab-root-ca.crt   # macOS
```

## Argo CD

- 접속 `https://argocd.awx.kr`. CLI는 Gateway가 HTTP/1.1로 받으므로 `argocd login argocd.awx.kr --grpc-web`.
- Google 로그인: OIDC 직접 연동(Dex 미사용). OAuth 클라이언트는 GCP 프로젝트 `alex-space-0001`, 동의 화면 Testing(테스트 사용자만 로그인).
- client secret은 레포 밖 Secret `argo-cd/argocd-oidc-google`(키 `clientSecret`, 라벨 `app.kubernetes.io/part-of=argocd`)에 둡니다.
  ```bash
  kubectl -n argo-cd create secret generic argocd-oidc-google --from-literal=clientSecret="$(jq -r .web.client_secret client_secret_*.json)"
  kubectl -n argo-cd label secret argocd-oidc-google app.kubernetes.io/part-of=argocd
  ```
- RBAC: `policy.default`는 빈 값(권한 없음). 관리자는 `helm/argocd/values.yaml`의 `policy.csv`에 이메일로 추가합니다.

## Kyverno 정책 (Audit)

- 위반해도 막지 않고 PolicyReport만 남깁니다. 시스템 네임스페이스(kube-system, argo-cd, istio-system, cert-manager, kyverno 등)는 검사하지 않습니다.
  - admission: kyverno 앱의 webhook namespaceSelector / background 스캔: 각 정책의 `matchConditions`(차트 `vpolExclude`). ValidatingPolicy의 background 스캔에는 엔진 `resourceFilters`가 적용되지 않아 두 곳에 같은 목록을 둡니다.
- 정책: Pod Security Standards restricted(baseline 포함) 17개(`helm/kyverno-policies/values.yaml`) + 모범 사례 `disallow-latest-tag`, `require-requests-limits`(`manifests/kyverno-policies/`)
- 리포트 확인
  ```bash
  kubectl get policyreport -A                                  # 네임스페이스별 pass/fail 요약
  kubectl get policyreport -n <ns> -o yaml | yq '.results[] | select(.result=="fail") | [.policy, .resources[0].name, .message]'
  ```
- 차단 전환은 정책 단위로 합니다: 차트 정책은 values의 `validationFailureActionByPolicy`, 직접 만든 정책은 `validationActions: [Deny]`.

## Vault

- 접속 `https://vault.awx.kr`. 로그인 방식 Userpass(관리자 정책 `admin`) 또는 Token.
- auth method, 정책, 사용자는 Vault API로 설정하며 레포에 없습니다. unseal key와 root token도 레포 밖에 보관합니다.

## 알려진 제약

- **Wi-Fi 노드와 L2 announcement**: worker-01/02(Broadcom `brcmfmac`)는 promiscuous 모드가 꺼져 있으면 LB IP의 ARP 요청을 받지 못해, 모든 노드에 `wifi-promisc.service`를 둡니다(`node-config/wifi-promisc/`).
- 사설 CA 인증서이므로 CA를 신뢰 등록하지 않은 기기에서는 인증서 경고가 납니다.
