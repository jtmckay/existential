FROM node:lts-alpine
RUN apk add --no-cache su-exec
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev && npm cache clean --force
COPY server.js entrypoint.sh ./
RUN chmod +x entrypoint.sh
EXPOSE 8800
ENTRYPOINT ["./entrypoint.sh"]
