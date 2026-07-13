# Document Management

`CLAUDE.md`, `README.md`, `PLAN.md`, `.claude/agents/` 서브에이전트, 루트 `.gitignore` 등 공유 문서/설정은 `dev` 브랜치에서만 관리한다. 다른 브랜치(`main`, `backend` 등)에는 커밋하지 않는다.

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

`backend`와 `frontend` 브랜치 간에는 직접 merge하지 않는다. 각각의 작업은 `backend` → `dev` PR, `frontend` → `dev` PR로 `dev`를 거쳐 통합한다.

# Branch Sync

작업 중 어떤 브랜치에서든 로컬이 `origin/<branch>`보다 뒤처진 것을 발견하면, `git fetch origin`을 실행한 뒤 `git pull origin <branch>`로 로컬을 최신화한다.

`dev`를 merge하기 전에는 항상 위 확인을 먼저 수행한다.

`dev`가 변경될 때마다 — 직접 커밋한 경우든, 위 pull로 인해 로컬 `dev`가 갱신된 경우든 — git user identity(`git config user.name`)에 따라 branch를 선택하여 merge하고 push한다:
- `milleion`인 경우: `dev`를 `backend`에만 merge한 후 push
- `ireyhye`인 경우: `dev`를 `frontend`에만 merge한 후 push
