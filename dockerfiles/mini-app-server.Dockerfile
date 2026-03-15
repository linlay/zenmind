FROM node:22-alpine

WORKDIR /app

COPY mini-app-server/package.json mini-app-server/pnpm-lock.yaml* ./
RUN npm install

COPY mini-app-server/ ./

ENV HOST=0.0.0.0
ENV PORT=11948

EXPOSE 11948

CMD ["npm", "start"]
