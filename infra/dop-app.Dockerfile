# A skeleton — the dop-app image (a React/Vite frontend, served by nginx).
# To be finalized once Replit delivers the frontend.
# An example (TODO):
# FROM node:20-alpine AS build
# WORKDIR /app
# COPY package*.json ./
# RUN npm ci
# COPY . .
# RUN npm run build
#
# FROM nginx:alpine
# COPY --from=build /app/dist /usr/share/nginx/html
# EXPOSE 80
FROM nginx:alpine
RUN echo 'dop-app: a skeleton — awaiting the frontend build' > /usr/share/nginx/html/index.html
