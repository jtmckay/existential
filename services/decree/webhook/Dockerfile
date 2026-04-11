FROM node:lts-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm install --omit=dev && npm cache clean --force
COPY server.js ./
EXPOSE 8800
CMD ["node", "server.js"]
