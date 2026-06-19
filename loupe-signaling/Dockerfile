FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
# The static marketing site (index.html, privacy, imprint, css, js, favicon) is shipped
# next to the compiled JS so the runtime container can serve it via the /site router.
COPY site ./site
RUN npm run build && mkdir -p dist/site && cp -R site/. dist/site/

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force
COPY --from=build /app/dist ./dist
USER node
EXPOSE 8080
CMD ["node", "dist/server.js"]
