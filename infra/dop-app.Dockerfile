# Esqueleto — imagem do dop-app (frontend React/Vite, servido por nginx).
# A ser finalizado quando o Replit entregar o frontend.
# Exemplo (TODO):
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
RUN echo 'dop-app: esqueleto — aguardando build do frontend' > /usr/share/nginx/html/index.html
