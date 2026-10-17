# node-config

쿠버네티스 리소스가 아닌 **노드(OS) 설정**입니다. Argo CD가 적용하지 않으며, 각 노드에 SSH로 설치합니다.

| 폴더 | 내용 | 설치 |
|---|---|---|
| `wifi-promisc/` | 모든 Wi-Fi 인터페이스(`wl*`)에 promiscuous 모드를 켜는 systemd 유닛 + NetworkManager dispatcher | `./wifi-promisc/install.sh <SSH 호스트...>` |
| `wifi-bssid-lock/` | iwlwifi 노드(master, worker-03)의 Wi-Fi를 한 AP에 고정해 주기 스캔을 멈춤(Cilium 장치 정보 손상 → LB 불통 방지) | `./wifi-bssid-lock/lock.sh <SSH 호스트> <BSSID>` |

## wifi-promisc가 필요한 이유

worker-01/02의 Broadcom `brcmfmac` 드라이버는 promiscuous 모드가 꺼져 있으면 노드 IP가 아닌 주소(Cilium LB IP)의 ARP 요청을 받지 못합니다.
그러면 이 노드가 L2 announcement lease를 잡았을 때 LoadBalancer IP가 응답하지 않습니다. 4노드 모두 같은 설정으로 맞춥니다.

- 부팅 시: `wifi-promisc.service` (oneshot)
- Wi-Fi 재연결 시: `/etc/NetworkManager/dispatcher.d/90-wifi-promisc`
- 확인: `ip -d link show <wl*> | grep promiscuity` → `1`
