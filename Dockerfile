# syntax=docker/dockerfile:1
# yoshida: web editor + optional server-side batch render, for home labs.
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
RUN npm run examples && npm run build

# The binaries are static (no libc), so the final image is just files.
FROM scratch
COPY --from=zig /src/zig-out/bin/yoshida-server /yoshida-server
COPY --from=zig /src/zig-out/bin/yoshida /yoshida
COPY --from=web /src/web/dist /web
ENV YOSHIDA_WEB=/web \
    YOSHIDA_PORT=8080
EXPOSE 8080
USER 65534:65534
ENTRYPOINT ["/yoshida-server"]
