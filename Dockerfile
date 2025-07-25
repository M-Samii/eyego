FROM node:18-slim
WORKDIR /app
COPY src/package.json .
RUN npm install
COPY src/ .
EXPOSE 3000
CMD ["npm", "start"]