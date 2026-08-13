# syntax=docker/dockerfile:1

# bump: xeve /XEVE_VERSION=([\d.]+)/ https://github.com/mpeg5/xeve.git|*
# bump: xeve after ./hashupdate Dockerfile XEVE $LATEST
# bump: xeve link "CHANGELOG" https://github.com/mpeg5/xeve/releases/tag/v$LATEST
ARG XEVE_VERSION=0.5.1
ARG XEVE_URL="https://github.com/mpeg5/xeve/archive/refs/tags/v$XEVE_VERSION.tar.gz"
ARG XEVE_SHA256=238c95ddd1a63105913d9354045eb329ad9002903a407b5cf1ab16bad324c245

# Must be specified
ARG ALPINE_VERSION

FROM alpine:${ALPINE_VERSION} AS base

FROM base AS download
ARG XEVE_URL
ARG XEVE_SHA256
ARG WGET_OPTS="--retry-on-host-error --retry-on-http-error=429,500,502,503 -nv"
WORKDIR /tmp
RUN \
  apk add --no-cache --virtual download \
    coreutils wget tar && \
  wget $WGET_OPTS -O xeve.tar.gz "$XEVE_URL" && \
  echo "$XEVE_SHA256  xeve.tar.gz" | sha256sum --status -c - && \
  mkdir xeve && \
  tar xf xeve.tar.gz -C xeve --strip-components=1 && \
  rm xeve.tar.gz && \
  apk del download

FROM base AS build
COPY --from=download /tmp/xeve/ /tmp/xeve/
ARG TARGETPLATFORM
ARG XEVE_VERSION
WORKDIR /tmp/xeve
RUN \
  case ${TARGETPLATFORM} in \
    linux/arm/v*) \
      mkdir -p /usr/local/lib/pkgconfig /usr/local/include /usr/local/lib/xeve && \
      touch /usr/local/lib/pkgconfig/xeve.pc && \
      touch /usr/local/lib/libxeve.a && \
      touch /usr/local/include/xeve.h && \
      exit 0 \
    ;; \
  esac && \
  apk add --no-cache --virtual build \
    build-base cmake pkgconf && \
  echo v$XEVE_VERSION > version.txt && \
  sed -i 's/mc_filter_bilin/xevem_mc_filter_bilin/' src_main/sse/xevem_mc_sse.c && \
  mkdir build && cd build && \
  cmake \
    -G"Unix Makefiles" \
    -DARM="$(if [ $(uname -m) = aarch64 ]; then echo TRUE; else echo FALSE; fi)" \
    -DCMAKE_BUILD_TYPE=Release \
    .. && \
  make -j$(nproc) install && \
  ln -sf /usr/local/lib/xeve/libxeve.a /usr/local/lib/libxeve.a && \
  pkg-config --exists --modversion --path xeve && \
  ar -t /usr/local/lib/libxeve.a && \
  readelf -h /usr/local/lib/libxeve.a && \
  apk del build

FROM scratch
ARG XEVE_VERSION
COPY --from=build /usr/local/lib/pkgconfig/xeve.pc /usr/local/lib/pkgconfig/xeve.pc
COPY --from=build /usr/local/lib/libxeve.a /usr/local/lib/libxeve.a
COPY --from=build /usr/local/include/ /usr/local/include/
