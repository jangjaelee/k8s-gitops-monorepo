# infralens-backup-pull

PoC DB 덤프의 클러스터 밖 사본. lab 노드(192.168.50.115)가 worker-node-02(192.168.50.112)에서 매일 02:40에 받아 간다. 키·주소 설정 파일은 레포에 넣지 않는다.

덤프에는 암호화된 자격 증명과 비밀번호 해시가 들어 있어 비밀처럼 다룬다. 권한 제한은 양쪽에 둔다.

## worker-node-02

1. 사용자 `infralens-backup`을 만들고 비밀번호를 잠근다. 덤프 폴더에 ACL로 읽기만 준다(`setfacl -R -m u:infralens-backup:rX`, daily·weekly에 기본 ACL). gid 999는 노드에서 systemd-journal이라 그룹에 넣지 않는다.
2. `authorized_keys`에 lab의 공개 키를 한 줄로 넣는다. 읽기 전용, 덤프 폴더 하나만:
   `command="rrsync -ro <infralens-db-backup PVC의 local-path 경로>",restrict ssh-ed25519 ...`

## lab 노드

1. 사용자 `infralens-backup`, 폴더 `/var/lib/infralens-poc-backup`(소유 그 사용자, 700), 그 사용자의 ed25519 키를 만든다. 개인 키는 노드 밖으로 옮기지 않는다.
2. `/etc/infralens-backup-pull.conf`에 `SRC=infralens-backup@192.168.50.112`. 그 사용자의 `known_hosts`에 worker-node-02 호스트 키를 `ssh-keyscan -t ed25519 192.168.50.112`로 넣고, 지문을 worker-node-02의 `/etc/ssh/ssh_host_ed25519_key.pub`와 대조한다(BatchMode라 없으면 실패).
3. 스크립트를 `/usr/local/bin/`(755), service·timer를 `/etc/systemd/system/`에 넣고 `systemctl enable --now infralens-backup-pull.timer`.

되돌리기: timer를 끄고 파일·사용자·`authorized_keys` 줄을 지운다.
