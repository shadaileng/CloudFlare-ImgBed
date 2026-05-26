FROM node:22-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl python3 make g++ && \
    update-ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY package.json package-lock.json ./
RUN npm install --omit=dev && \
    apt-get purge -y --auto-remove python3 make g++ && \
    rm -rf /root/.npm /tmp/*

COPY . .

RUN mkdir -p /data && chown -R node:node /app /data

USER node

ENV PORT=7860
ENV DATA_DIR=/data
EXPOSE 7860

CMD ["node", "--import", "./deploy/server/register.mjs", "deploy/server/index.js"]
