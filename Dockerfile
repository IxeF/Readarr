# syntax=docker/dockerfile:1

# Stage 1: Builder
FROM mcr.microsoft.com/dotnet/sdk:6.0-alpine AS builder

ARG VERSION
ARG BRANCH=develop
ARG BUILD_CONFIGURATION=Release

# Build dependencies (ALL original)
RUN apk add --no-cache \
    bash \
    git \
    icu-libs \
    nodejs \
    yarn \
    coreutils \
    curl \
    unzip \
    jq

WORKDIR /src

COPY . .

# Update version info if VERSION is set
RUN if [ -n "$VERSION" ]; then \
        sed -i "s/<AssemblyVersion>[0-9.*]\+<\/AssemblyVersion>/<AssemblyVersion>$VERSION<\/AssemblyVersion>/g" src/Directory.Build.props && \
        sed -i "s/<AssemblyConfiguration>[\$()A-Za-z-]\+<\/AssemblyConfiguration>/<AssemblyConfiguration>${BRANCH}<\/AssemblyConfiguration>/g" src/Directory.Build.props && \
        sed -i "s/<string>10.0.0.0<\/string>/<string>$VERSION<\/string>/g" distribution/osx/Readarr.app/Contents/Info.plist; \
    fi

RUN chmod +x build.sh && ./build.sh --all

# Stage 2: Runtime
FROM alpine:3.22

ARG VERSION
ARG BRANCH=develop
ARG PackageOwner=IxeF
ARG PackageRepo=Readarr
ARG PUID=1000
ARG PGID=1000

ENV COMPlus_EnableDiagnostics=0 \
    READARR__UPDATE__BRANCH=${BRANCH} \
    PUID=${PUID} \
    PGID=${PGID} \
    UMASK_SET=002

# Runtime dependencies (ALL original plus extras if needed)
RUN apk add --no-cache \
    bash \
    ca-certificates \
    catatonit \
    coreutils \
    icu-libs \
    libintl \
    nano \
    sqlite-libs \
    tzdata \
    curl \
    unzip \
    jq

# Directories
RUN mkdir -p /app/bin /config /AudioBooks

# Copy built app
COPY --from=builder /src/_artifacts/linux-musl-x64/net6.0/Readarr /app/bin/

# Remove updater
RUN rm -rf /app/bin/Readarr.Update

# Create user and fix ownership/permissions
RUN addgroup -g ${PGID} appgroup && \
    adduser -D -u ${PUID} -G appgroup appuser && \
    chown -R appuser:appgroup /app /config /AudioBooks && \
    chmod -R 775 /app /config /AudioBooks

# Create package info
RUN printf "UpdateMethod=docker\nBranch=%s\nPackageVersion=%s\nPackageAuthor=[%s](https://github.com/%s)\nPackageOwner=%s\nPackageRepo=%s\n" \
    "${READARR__UPDATE__BRANCH}" "${VERSION}" "${PackageOwner}" "${PackageOwner}" "${PackageOwner}" "${PackageRepo}" > /app/package_info

# Switch to non-root
USER appuser:appgroup
WORKDIR /config
VOLUME ["/config", "/AudioBooks"]

# Run Readarr directly
ENTRYPOINT ["/app/bin/Readarr/Readarr"]
