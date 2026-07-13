# Document Management

`CLAUDE.md`, `README.md`, `PLAN.md`, `.claude/agents/` 서브에이전트, 루트 `.gitignore` 등 공유 문서/설정은 `dev` 브랜치에서 관리한다.

# Git Commit Convention

커밋 메시지는 Conventional Commits 표준을 따른다: `<type>: <description>`

- `feat:` 새로운 기능 추가
- `fix:` 버그 수정
- `docs:` 문서 변경
- `style:` 코드 포맷팅, 세미콜론 등 (로직 변경 없음)
- `refactor:` 리팩토링 (기능 변경 없음)
- `test:` 테스트 추가/수정
- `chore:` 빌드, 설정 등 기타 변경

커밋 메시지의 설명 부분은 한국어로 작성한다.

커밋 후, 그리고 브랜치 merge 후의 push는 별도 허가 요청 없이 바로 수행한다.

# PR Policy

`dev` → `main` PR을 올릴 때는 `CLAUDE.md`, `.claude/` 등 Claude 관련 파일은 제외하고 올린다.

`backend`와 `frontend` 브랜치 간에는 직접 merge하지 않는다.

- `milleion`(백엔드 담당)은 2026-07-13부터 `backend` 브랜치 대신 `dev`에서 직접 작업한다(`backend`는 그 시점 상태로 병합·보존되어 더 이상 갱신하지 않음). 별도 병합 절차 없이 `dev`에 바로 커밋·push한다.
- `ireyhye`(프론트엔드 담당)는 계속 `frontend` 브랜치에서 작업하고, `frontend` → `dev` PR로 `dev`에 통합한다.

# Branch Sync

작업 중 로컬이 `origin/<branch>`보다 뒤처진 것을 발견하면, `git fetch origin`을 실행한 뒤 `git pull origin <branch>`로 로컬을 최신화한다. `dev`에서 커밋하기 전에는 항상 이 확인을 먼저 수행한다.

`ireyhye`가 작업한 `frontend`가 PR로 `dev`에 들어와 로컬 `dev`가 갱신된 경우, `milleion`은 그 변경을 반영하기 위해 다시 `git pull origin dev`로 최신화하면 된다(별도 병합 대상 브랜치 없음).
