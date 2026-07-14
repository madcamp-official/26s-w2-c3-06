# 통합 배포 이미지 (PLAN "배포 및 DB 운영 > 빌드 방식" 참고).
# 1단계에서 Flutter web을 빌드하고, 런타임 이미지에 backend/src/index.ts가 기대하는
# 상대 경로(backend/dist에서 두 단계 위 + frontend/build/web)로 결과물을 배치해
# 백엔드가 프론트 정적 파일을 함께 서빙하게 한다. 빌드 컨텍스트는 리포 루트여야 한다.

# ---- 백엔드 의존성 ----
FROM node:22-slim AS backend-deps
WORKDIR /app/backend
COPY backend/package.json backend/package-lock.json* ./
RUN npm ci

# ---- 백엔드 빌드 ----
FROM node:22-slim AS backend-build
WORKDIR /app/backend
# node:*-slim에는 OpenSSL이 없어 Prisma가 엔진 바이너리 타깃을 잘못 잡는다(생성 시점과
# 실행 시점 둘 다 필요 — 여기선 `prisma generate`가 올바른 엔진을 받게 하기 위함).
RUN apt-get update -y && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*
COPY --from=backend-deps /app/backend/node_modules ./node_modules
COPY backend/ .
RUN npx prisma generate && npm run build

# ---- 프론트 빌드 (Flutter web) ----
FROM ghcr.io/cirruslabs/flutter:stable AS frontend-build
WORKDIR /app/frontend
COPY frontend/ .
RUN flutter pub get && flutter build web --release

# ---- 런타임 ----
FROM node:22-slim AS runtime
WORKDIR /app/backend
ENV NODE_ENV=production
# 실행 시점에도 Prisma 쿼리 엔진이 링크할 OpenSSL이 필요하다(위 backend-build와 동일 이유).
RUN apt-get update -y && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*
COPY --from=backend-build /app/backend/node_modules ./node_modules
COPY --from=backend-build /app/backend/dist ./dist
COPY --from=backend-build /app/backend/prisma ./prisma
COPY --from=backend-build /app/backend/package.json ./package.json
COPY --from=frontend-build /app/frontend/build/web /app/frontend/build/web
COPY backend/docker-entrypoint.sh ./docker-entrypoint.sh
RUN chmod +x ./docker-entrypoint.sh

EXPOSE 3000
ENTRYPOINT ["./docker-entrypoint.sh"]
