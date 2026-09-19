[디렉터리 목적]
secure_boot/                프로젝트 최상위. git 레포.
custom/files/               직접 수정/작성한 파일의 원본. zephyrproject 내부 경로 구조를 그대로 미러링. git 관리 대상.
custom/files.list           관리 대상 경로 목록 (zephyrproject 기준 상대경로).
custom/apply.sh             files/ 의 내용을 zephyrproject 내 원래 위치로 복사 (덮어쓰기)
custom/collect.sh           files.list 의 경로를 zephyrproject 에서 files/ 로 수집
zephyrproject/              west workspace (zephyr, mcuboot, modules, build 등). git 제외. west로 복원.

[새 PC 세팅 순서]
1. git clone <레포> ~/secure_boot
2. cd ~/secure_boot
3. west init --mr v3.7.2 zephyrproject
4. cd zephyrproject && west update
5. ~/secure_boot/custom/apply.sh
6. .venv 생성 및 requirements 설치, west zephyr-export

[평소 작업 순서]
- 작업 후: custom/collect.sh -> secure_boot에서 git add custom, commit, push
- 다른 PC: git pull -> custom/apply.sh
- west update 실행 -> custom/apply.sh 재실행

[새 파일 추가 시]
1. 파일을 custom/files/ 아래 같은 상대경로로 mv
2. files.list에 경로 한 줄 추가
3. custom/apply.sh 실행($ ./apply.sh)

[주의사항]
- apply.sh는 zephyrproject 쪽 같은 이름 파일을 덮어쓴다. 수정한 게 있으면 apply 전에 collect.sh 먼저.
- files.list: 한 줄에 경로 하나, 끝에 / 붙이지 않기, 주석(#)과 빈 줄 넣지 않기.
- 수정은 zephyrproject 쪽에서 하고, commit 전에 반드시 collect.sh 실행 (안 하면 git에 최신본이 안 올라감).
- zephyrproject/, .venv/, build*/ 는 .gitignore에 있어야 함.
- 두 PC의 zephyr 버전은 v3.7.2로 통일할 것 (빌드 사이즈 차이 방지).
- 삭제한 파일은 동기화되지 않음 (양쪽에서 직접 삭제).
