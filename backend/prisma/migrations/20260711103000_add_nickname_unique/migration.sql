-- AlterTable: 닉네임 전역 유일 제약 추가
CREATE UNIQUE INDEX "User_nickname_key" ON "User"("nickname");
