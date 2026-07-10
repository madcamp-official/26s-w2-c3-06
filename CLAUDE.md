# Document Management

`CLAUDE.md`, `README.md`, `.claude/agents/` 서브에이전트 등 공유 문서는 `dev` 브랜치에서만 관리한다. 다른 브랜치(`main`, `backend` 등)에는 커밋하지 않는다.

# Git Commit Convention

커밋 메시지는 Conventional Commits 표준을 따른다: `<type>: <description>`

- `feat:` 새로운 기능 추가
- `fix:` 버그 수정
- `docs:` 문서 변경
- `style:` 코드 포맷팅, 세미콜론 등 (로직 변경 없음)
- `refactor:` 리팩토링 (기능 변경 없음)
- `test:` 테스트 추가/수정
- `chore:` 빌드, 설정 등 기타 변경

커밋 후, 그리고 브랜치 merge 후의 push는 별도 허가 요청 없이 바로 수행한다.

# PR Policy

`dev` → `main` PR을 올릴 때는 `CLAUDE.md`, `.claude/` 등 Claude 관련 파일은 제외하고 올린다.

# Branch Sync

`dev`를 merge하기 전에 항상 `git fetch origin`을 실행하고, 로컬 `dev`가 `origin/dev`보다 뒤처져 있으면 `git pull origin dev`를 실행한다.

`dev`가 수정될 때마다(커밋 후) git user identity(`git config user.name`)에 따라 branch를 선택하여 merge하고 push한다:
- `milleion`인 경우: `dev`를 `backend`에만 merge한 후 push
- `ireyhye`인 경우: `dev`를 `frontend`에만 merge한 후 push
