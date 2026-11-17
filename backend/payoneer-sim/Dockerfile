# Payoneer sandbox simulator for Vendra — no npm dependencies (uses Node's built-in SQLite)
FROM node:24-alpine
WORKDIR /app
COPY package.json ./
COPY src ./src
ENV PORT=4343 DATA_DIR=/data NODE_NO_WARNINGS=1
VOLUME /data
EXPOSE 4343
HEALTHCHECK --interval=3s --timeout=3s --retries=20 CMD wget -q -O /dev/null http://127.0.0.1:4343/health || exit 1
CMD ["node", "src/server.js"]
