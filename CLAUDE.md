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

# Merge Policy

`dev` → `main`은 GitHub PR을 올리지 않고 **로컬에서 직접 `git merge`한 뒤 바로 push**한다(`git checkout main && git merge dev --no-ff` 방식). 병합 시 `CLAUDE.md`, `.claude/`, `PLAN.md` 등 Claude 작업용/내부 문서는 `git rm --cached`로 제외하고 커밋한다.

- 백엔드·프론트엔드 모두 `dev` 브랜치에서 함께 작업한다. `milleion`(백엔드 담당)·`ireyhye`(프론트엔드 담당) 모두 별도 병합 절차 없이 `dev`에 바로 커밋·push한다.

# Working Branch

기능/버그 수정 작업은 `dev`가 아니라 **`dev-2`**에서 진행한다. `dev-2`는 `dev`에서 분기한 작업용 브랜치이며, `CLAUDE.md`/`README.md`/`PLAN.md`/`.claude/agents/` 등 공유 문서만 예외적으로 `dev`에 직접 커밋한다(Document Management 항목 참고). `dev-2`에서 커밋하기 전에는 **`git branch --show-current`로 현재 브랜치가 `dev-2`인지 반드시 먼저 확인**한다 — 같은 워킹 디렉토리를 다른 세션이 동시에 쓰면서 브랜치가 바뀌어 있을 수 있다. `dev-2`는 `origin/dev`를 upstream으로 추적하지 않도록 유지해 실수로 `dev`에 push되는 일을 막는다.

# Branch Sync

작업 중 로컬이 `origin/dev`보다 뒤처진 것을 발견하면, `git fetch origin`을 실행한 뒤 `dev`를 최신화하고 `dev-2`에 반영(rebase 또는 merge)한다. `dev-2`에서 커밋하기 전에는 항상 이 확인과 위 Working Branch 항목의 브랜치 확인을 먼저 수행한다.
