# k8s-gitops-monorepo

홈랩 Kubernetes 클러스터의 Helm values, 매니페스트, Argo CD Application을 한곳에서 관리하는 GitOps 레포입니다.
클러스터마다 `cluster/<클러스터 이름>/` 폴더를 두고, 그 클러스터에 배포하는 모든 것을 그 아래에 둡니다.

> **public 레포입니다.** 비밀번호·토큰·개인키·kubeconfig·Secret 데이터는 커밋하지 않습니다.
> 인증서 개인키는 cert-manager가 클러스터 안에서만 만듭니다.

## 클러스터

| 클러스터 | 설명 | 명세 |
|---|---|---|
| `home-k8s` | 집 홈랩. kubeadm 4노드(Wi-Fi), Kubernetes v1.36.0, Cilium 1.20.2, Argo CD v3.3.8, Istio 1.30.3 | [cluster/home-k8s/README.md](cluster/home-k8s/README.md) |

## 디렉터리

```
.
├── cluster/
│   └── <cluster>/
│       ├── README.md              # 용도, 구성요소·버전·Argo CD Application 명세
│       ├── argocd/applications/   # Argo CD Application (kubectl apply로 등록)
│       ├── argocd/repositories/   # Argo CD 저장소 등록 Secret (공개 저장소만, 인증 정보 없음)
│       ├── helm/<release>/        # Helm values (Argo CD multi-source의 $values 또는 Helm CLI)
│       ├── manifests/<app>/       # Helm이 아닌 매니페스트 (path 소스 Application)
│       └── node-config/           # 노드(OS) 설정 — Argo CD 미적용, SSH로 설치
├── .claude/agents/                # PR 리뷰·머지 에이전트
└── CLAUDE.md                      # 작성 규칙 (Application, values, 작업 흐름)
```

## 작업 흐름

1. 브랜치를 만들고(`feat/…`, `fix/…`, `chore/…`, `docs/…`, `refactor/…`) 변경 후 PR을 엽니다. main에 직접 push하지 않습니다.
2. `gitops-pr-reviewer` 에이전트가 리뷰하고, 모든 검사를 통과하면 squash 머지합니다.
   ```bash
   cd k8s-gitops-monorepo && claude
   > gitops-pr-reviewer로 PR <번호> 리뷰하고 머지해줘
   ```
   검사: 변경 범위, 비밀값, YAML 문법, 차트 버전 고정, Application 규칙, `helm template`, 서버 dry-run, values 주석, 클러스터 README 갱신.
3. 머지 후 클러스터에 적용합니다. 방법은 각 클러스터 README의 "작업 흐름"을 봅니다.

## 새 클러스터 추가

1. `cluster/<새 이름>/`을 만들고 같은 구조(`argocd/`, `helm/`, `manifests/`, `README.md`)를 둡니다.
2. Application의 `path`와 `$values` 경로는 `cluster/<새 이름>/...`로 씁니다.
3. 클러스터마다 자기 Argo CD를 두는 동안은 앱 이름을 그대로 씁니다. Argo CD 하나가 여러 클러스터를 관리하게 되면 앱 이름에 클러스터 접두사를 붙이거나 클러스터별 AppProject로 구분합니다.
4. 위 "클러스터" 표에 추가합니다.
