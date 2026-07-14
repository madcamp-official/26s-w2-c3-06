#!/bin/sh
# Railway 등 파일 업로드가 불가능한 배포 환경을 위한 진입점.
# FIREBASE_SERVICE_ACCOUNT_JSON(서비스 계정 JSON 전체 문자열)이 있으면 파일로 풀어써서
# GOOGLE_APPLICATION_CREDENTIALS가 그 파일을 가리키게 한다. 로컬처럼 이미
# GOOGLE_APPLICATION_CREDENTIALS가 유효한 파일 경로를 가리키고 있다면 아무 것도 하지 않는다.
set -e

if [ -n "$FIREBASE_SERVICE_ACCOUNT_JSON" ]; then
  # dash(node:22-slim의 /bin/sh)의 echo는 \n 등 백슬래시 이스케이프를 실제 개행으로
  # 해석해버려 private_key 안의 \n이 진짜 제어 문자로 바뀌며 JSON이 깨진다.
  # printf '%s'는 이스케이프를 해석하지 않으므로 원본 문자열을 그대로 보존한다.
  printf '%s' "$FIREBASE_SERVICE_ACCOUNT_JSON" > /app/backend/firebase-service-account.json
  export GOOGLE_APPLICATION_CREDENTIALS=/app/backend/firebase-service-account.json
fi

npx prisma migrate deploy
exec node dist/index.js
