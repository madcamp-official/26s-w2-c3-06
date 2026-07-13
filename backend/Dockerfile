# 백엔드 런타임 이미지 (스캐폴드 단계).
# 배포 통합 시 PLAN "배포 및 DB 운영"대로 앞단에 Flutter web build 스테이지를 붙여
# 정적 파일을 Express가 함께 서빙하는 멀티스테이지로 확장한다.
FROM node:22-slim AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

FROM node:22-slim AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npx prisma generate && npm run build

FROM node:22-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
COPY --from=build /app/prisma ./prisma
COPY package.json ./
EXPOSE 3000
# 배포 시 startup 훅에서 `prisma migrate deploy` 실행 후 서버 기동
CMD ["node", "dist/index.js"]
