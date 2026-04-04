# syntax=docker/dockerfile:1

# Stage 1: Builder
FROM mcr.microsoft.com/dotnet/sdk:6.0-alpine AS builder

ARG VERSION
ARG BRANCH=develop
ARG BUILD_CONFIGURATION=Release

# Build dependencies
RUN apk add --no-cache \
    bash \
    git \
    icu-libs \
    nodejs \
    yarn \
    coreutils

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

ARG TARGETARCH
ARG VERSION
ARG BRANCH=develop
ARG PackageOwner=IxeF
ARG PackageRepo=Readarr

ENV COMPlus_EnableDiagnostics=0 \
    READARR__UPDATE__BRANCH=${BRANCH} \
    PUID=1000 \
    PGID=1000

# Install runtime dependencies
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
    && mkdir -p /app/bin /config /AudioBooks

# Copy built Readarr from builder stage
COPY --from=builder /src/_artifacts/linux-musl-x64/net6.0/Readarr /app/bin/

# Remove updater if not needed
RUN rm -rf /app/bin/Readarr.Update

# Set ownership and permissions
RUN addgroup -g ${PGID} appgroup && \
    adduser -D -u ${PUID} -G appgroup appuser && \
    chown -R appuser:appgroup /app /config /AudioBooks && \
    chmod -R 775 /app /config /AudioBooks

# Create package_info dynamically
RUN printf "UpdateMethod=docker\nBranch=%s\nPackageVersion=%s\nPackageAuthor=[%s](https://github.com/%s)\nPackageOwner=%s\nPackageRepo=%s\n" \
    "${READARR__UPDATE__BRANCH}" "${VERSION}" "${PackageOwner}" "${PackageOwner}" "${PackageOwner}" "${PackageRepo}" > /app/package_info

USER appuser:appgroup
WORKDIR /config
VOLUME ["/config", "/AudioBooks"]

# Run Readarr directly
ENTRYPOINT ["/app/bin/Readarr"]
