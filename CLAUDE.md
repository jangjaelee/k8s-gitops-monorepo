# k8s-gitops-monorepo

홈랩 Kubernetes 클러스터의 Helm values, 매니페스트, Argo CD Application을 모두 이 레포로 관리한다. 클러스터별로 `cluster/<클러스터 이름>/` 아래에 둔다.
클러스터 운영 메모(노드, 접속, 작업 이력)는 로컬 `~/Workspace/Alex/my-k8s/CLAUDE.md`에 있다.

**이 레포는 public이다.** 비밀번호, 토큰, 개인키, kubeconfig, Secret 데이터는 절대 커밋하지 않는다.

## 디렉터리

| 경로 | 내용 |
|---|---|
| `cluster/<cluster>/README.md` | 그 클러스터의 용도, 구성요소·버전·Argo CD Application 명세. **구성요소를 추가·변경·삭제하면 같은 PR에서 갱신한다** |
| `cluster/<cluster>/helm/<release>/values.yaml` | Helm values. 첫 줄 주석에 chart 이름·버전과 연결된 Argo CD 앱을 적는다 |
| `cluster/<cluster>/manifests/<app>/` | Helm이 아닌 일반 매니페스트. `path` 소스 Argo CD 앱이 가리킨다 |
| `cluster/<cluster>/argocd/applications/<app>.yaml` | Argo CD `Application`. 클러스터에는 `kubectl apply -f`로 등록한다 |
| `cluster/<cluster>/argocd/repositories/<name>.yaml` | Argo CD 저장소 등록 Secret(예: OCI Helm). **공개 저장소만, 인증 정보는 절대 넣지 않는다** |
| `cluster/<cluster>/node-config/` | 노드 OS 설정(Argo CD 미적용, SSH로 설치) |
| `.claude/agents/` | PR 리뷰·머지 에이전트 |

현재 클러스터(이름 = kubectl context)
- `home-k8s`: 집 홈랩, kubeadm 5노드, Cilium 1.20.2, Argo CD v3.5.5
- `rancher-desktop`: 로컬 Mac의 Rancher Desktop, k3s 단일 노드(arm64), Flannel·ServiceLB, Argo CD v3.5.5

- `cluster/<cluster>/` 안의 파일 주석에 적는 경로(`helm/...`, `manifests/...`, `argocd/applications/...`)는 그 클러스터 폴더 기준이다.
- Application의 `path`와 `$values` 경로는 레포 루트 기준이라 `cluster/<cluster>/...`로 시작한다.

## Argo CD Application 규칙

- `metadata.namespace: argo-cd`, `project`: 시스템 구성요소는 `system`, 관측은 `o11y`
- Helm 차트: `targetRevision`은 정확한 버전으로 고정한다(`*`, 범위, `latest` 금지)
- values는 multi-source로 참조한다: 차트 소스 + `ref: values`(이 레포, `main`) → `$values/cluster/<cluster>/helm/<release>/values.yaml`
- 이 레포의 매니페스트를 가리키는 `path`: `cluster/<cluster>/manifests/<app>`
- `syncOptions`에 `ServerSideApply=true`. 네임스페이스를 만들어야 하면 `CreateNamespace=true`
- 컨트롤러가 런타임에 바꾸는 필드(webhook caBundle, failurePolicy 등)는 `ignoreDifferences` + `RespectIgnoreDifferences=true`
- 앱 이름은 Argo CD 인스턴스(`argo-cd` 네임스페이스) 안에서 유일해야 한다. 지금은 클러스터마다 자기 Argo CD가 있어 접두사를 붙이지 않는다. Argo CD 하나가 여러 클러스터를 관리하게 되면 `<cluster>-<app>` 이름이나 클러스터별 AppProject로 구분한다.

## Argo CD로 관리하지 않는 것

CNI나 Argo CD가 망가져도 Argo CD 없이 복구할 수 있게 Helm CLI로 직접 적용한다. values 파일 첫 줄 주석에 차트·버전을 적는다. 명령은 레포 루트에서 해당 클러스터 context로 실행한다.
rancher-desktop은 k3s 기본 구성요소(Flannel, CoreDNS, ServiceLB, local-path-provisioner, metrics-server)를 그대로 쓰고 레포로 관리하지 않는다.

- Cilium(home-k8s만, `cluster/home-k8s/helm/cilium/values.yaml`)
  `helm upgrade cilium cilium/cilium -n kube-system --version <고정> -f cluster/home-k8s/helm/cilium/values.yaml --force-conflicts`
  ConfigMap만 바뀌면 `kubectl -n kube-system rollout restart ds/cilium`이 필요하다.
- Argo CD(`cluster/<cluster>/helm/argocd/values.yaml`)
  `helm upgrade argocd argo/argo-cd -n argo-cd --version <고정> -f cluster/<cluster>/helm/argocd/values.yaml --force-conflicts`

## 작업 흐름

1. 작업 단위마다 브랜치(`feat/…`, `fix/…`, `chore/…`, `refactor/…`)를 만들고 PR을 연다. main에 직접 push하지 않는다.
2. 리뷰와 머지는 `gitops-pr-reviewer` 에이전트가 한다(`.claude/agents/gitops-pr-reviewer.md`).
3. 머지된 뒤에 클러스터에 적용한다(Argo CD 앱 등록 또는 Helm CLI). 적용 결과는 `my-k8s/TASKS.md` 작업 기록에 남긴다.
