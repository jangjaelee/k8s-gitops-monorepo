# wifi-bssid-lock

Intel `iwlwifi` 노드(master-node-01 `wlo1`, worker-node-03 `wlp3s0`)의 Wi-Fi 연결을 한 AP(BSSID)에 고정해 **주기 Wi-Fi 스캔을 멈춥니다.**

## 왜 필요한가

- NetworkManager는 같은 SSID의 AP가 여러 대(AiMesh)면 로밍 대상을 찾으려고 약 2분마다 백그라운드 스캔을 합니다.
- 스캔이 끝날 때 커널(cfg80211 WEXT 호환)이 **MTU·MAC이 빠진 RTM_NEWLINK**를 보내고, Cilium이 이 메시지로 장치 정보를 덮어씁니다.
  - `cilium-dbg shell -- db/show devices`에서 `wl*`가 MTU 0, HWAddr 빈 값, OperStatus unknown이 됩니다.
- Cilium은 이 장치를 L3 장치로 보고 L2 헤더를 다시 쓰지 않습니다. 그래서 이 노드가 L2 announcement lease를 잡으면, 다른 노드 Pod의 응답이 VXLAN inner MAC(원격 Pod eth0 / lxc) 그대로 Wi-Fi로 나가 클라이언트에 닿지 않습니다. 결과적으로 LB IP가 응답하지 않습니다.
- `brcmfmac`(worker-01/02)는 이 문제가 없습니다.

## 적용 (2026-10-17)

| 노드 | 연결 | 고정 BSSID |
|---|---|---|
| master-node-01 | LJJ-50G | `FC:34:97:2E:B7:CC` |
| worker-node-03 | LJJ-50G | `FC:34:97:2E:B7:CC` |

```bash
./lock.sh k8s-worker-03 FC:34:97:2E:B7:CC   # 4분 자동 되돌림 타이머를 건 뒤 적용
kubectl -n kube-system delete pod -l k8s-app=cilium --field-selector spec.nodeName=<노드>   # 장치 정보 다시 읽기
```

- 확인
  - 스캔 없음: `iw event -t | grep scan`
  - 장치 정보: `db/show devices`에서 `wl*`가 MTU 1500·MAC 정상
  - LB: lease를 그 노드로 옮긴 뒤 `curl https://vault.awx.kr/v1/sys/health`
- 해제: `./lock.sh <호스트> --unlock`
- BSSID 고르기: `nmcli -f IN-USE,BSSID,SSID,SIGNAL dev wifi list` (지금 연결된 AP, 신호가 센 AP)

## 단점

- 로밍을 하지 않습니다. 고정한 AP(AiMesh 노드)가 꺼지거나 바뀌면 그 노드는 Wi-Fi에 붙지 못합니다. 이때는 콘솔에서 `nmcli con mod LJJ-50G 802-11-wireless.bssid ""`로 해제합니다.
- AP를 교체하면 BSSID가 바뀌니 다시 적용합니다.
