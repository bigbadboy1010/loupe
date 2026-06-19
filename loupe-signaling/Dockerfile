FROM node:20-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
# The static marketing site (index.html, privacy, imprint, css, js, favicon) is shipped
# next to the compiled JS so the runtime container can serve it via the /site router.
COPY site ./site
# Make the static site readable by the non-root `node` user that runs in the
# runtime image. We chmod to 0644 so node can read each file; the build also
# re-applies this inside the runtime stage below.
RUN find site -type f -exec chmod 0644 {} + && find site -type d -exec chmod 0755 {} +
RUN npm run build && mkdir -p dist/site && cp -R site/. dist/site/

FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force
COPY --from=build /app/dist ./dist
# Ship the static site to /app/site so resolveSiteDir() finds it at the
# expected path in both dev (tsx watch) and prod (this runtime image).
COPY --from=build /app/site ./site
# Re-apply world-readable permissions: the build stage may have left files
# with stricter modes, and Docker COPY preserves the source permissions.
RUN find /app/site -type f -exec chmod 0644 {} + && find /app/site -type d -exec chmod 0755 {} +
USER node
EXPOSE 8080
CMD ["node", "dist/server.js"]
