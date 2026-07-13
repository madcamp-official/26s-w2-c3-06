-- 누적 경험치 컬럼 용어를 EXP로 통일: User.xp -> User.exp (RENAME으로 기존 데이터 보존)
ALTER TABLE "User" RENAME COLUMN "xp" TO "exp";
