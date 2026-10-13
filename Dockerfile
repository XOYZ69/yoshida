# syntax=docker/dockerfile:1
# yoshida: website, docs and web editor + optional server-side batch render,
# for home labs. Site at /, docs at /docs/, editor at /editor/.
#
#   docker build -t yoshida .
#   docker run -p 8080:8080 yoshida                     # editor + server render
#   docker run -p 8080:8080 -e YOSHIDA_RENDER=0 yoshida # editor only (browser render)

ARG ZIG_VERSION=0.16.0

# Zig from PyPI (the ziglang package ships the official release binaries and
# works on amd64 and arm64). Downloading the tarball from ziglang.org works too.
FROM python:3.13-alpine AS zig
ARG ZIG_VERSION
RUN pip install --no-cache-dir "ziglang==${ZIG_VERSION}"
WORKDIR /src
COPY build.zig build.zig.zon ./
COPY src ./src
RUN python3 -m ziglang build -Doptimize=ReleaseFast -Dstrip=true \
 && python3 -m ziglang build wasm

FROM node:22-alpine AS web
WORKDIR /src/web
COPY web/package.json web/package-lock.json ./
RUN npm ci
COPY web ./
COPY examples /src/examples
COPY --from=zig /src/zig-out/web/yoshida.wasm public/yoshida.wasm
COPY --from=zig /src/zig-out/web/expr.wasm public/expr.wasm
RUN npm run examples && npm run build

# The website (landing page and docs) at /, with the editor in /editor/, laid
# out like GitHub Pages. The output is plain files, copied into the final
# image. No release pages: those come from GitHub Releases in CI.
# Zola publishes x86_64 and aarch64 Linux builds, matching amd64 and arm64.
FROM debian:bookworm-slim AS site
ARG ZOLA_VERSION=0.23.6
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
 && curl -fsSL "https://github.com/getzola/zola/releases/download/v${ZOLA_VERSION}/zola-v${ZOLA_VERSION}-$(uname -m)-unknown-linux-gnu.tar.gz" | tar xz -C /usr/local/bin
WORKDIR /src/site
COPY site ./
RUN zola build --base-url / --output-dir /public
COPY --from=web /src/web/dist /public/editor

# The binaries are static (no libc), so the final image is just files.
FROM scratch
COPY --from=zig /src/zig-out/bin/yoshida-server /yoshida-server
COPY --from=zig /src/zig-out/bin/yoshida /yoshida
COPY --from=site /public /web
ENV YOSHIDA_WEB=/web \
    YOSHIDA_PORT=8080
EXPOSE 8080
USER 65534:65534
ENTRYPOINT ["/yoshida-server"]
