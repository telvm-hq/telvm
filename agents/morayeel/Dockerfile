# Pin npm playwright to the same line as the base image (avoid browser binary skew).
FROM mcr.microsoft.com/playwright:v1.49.1-jammy

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY run.mjs ./

ENV TARGET_URL=http://morayeel_lab:8080/
ENV OUT_DIR=/artifacts/run

ENTRYPOINT ["node", "/app/run.mjs"]
