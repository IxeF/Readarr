# stage 1: builder
FROM mcr.microsoft.com/dotnet/sdk:6.0-alpine AS builder
 
ARG VERSION
ARG BRANCH=develop
ARG BUILD_CONFIGURATION=Release
 
# install build and runtime dependencies
RUN apk add --no-cache \
    bash \
    git \
    icu-libs \
    nodejs \
    yarn \
    coreutils
 
WORKDIR /src
 
# copy source code
COPY . .
 
# update version information
RUN if [ -n "$VERSION" ]; then \
        sed -i "s/<AssemblyVersion>[0-9.*]\+<\/AssemblyVersion>/<AssemblyVersion>$VERSION<\/AssemblyVersion>/g" src/Directory.Build.props && \
        sed -i "s/<AssemblyConfiguration>[\$()A-Za-z-]\+<\/AssemblyConfiguration>/<AssemblyConfiguration>${BRANCH}<\/AssemblyConfiguration>/g" src/Directory.Build.props && \
        sed -i "s/<string>10.0.0.0<\/string>/<string>$VERSION<\/string>/g" distribution/osx/Readarr.app/Contents/Info.plist; \
    fi
 
# build everything (backend, frontend, packages)
RUN chmod +x build.sh && ./build.sh --all
 
# stage 2: final runtime image
FROM docker.io/library/alpine:3.22
 
ARG TARGETARCH
ARG VENDOR
ARG VERSION
ARG BRANCH=develop
ARG PackageOwner=faustvii
ARG PackageRepo=readarr
# fix: declare PUID/PGID so they resolve at build time
ARG PUID=1000
ARG PGID=1000
 
ENV COMPlus_EnableDiagnostics=0 \
    READARR__UPDATE__BRANCH=${BRANCH}
 
USER root
WORKDIR /app
 
# install runtime dependencies and create required directories
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
    && mkdir -p /app/bin /config /AudioBooks \
    && chown -R root:root /app && chmod -R 755 /app
 
# copy the packaged application from the builder stage
COPY --from=builder /src/_artifacts/linux-musl-x64/net6.0/Readarr /app/bin/
 
# remove updater if not needed
RUN rm -rf /app/bin/Readarr.Update
 
# create user and fix ownership/permissions
RUN addgroup -g ${PGID} appgroup && \
    adduser -D -u ${PUID} -G appgroup appuser && \
    chown -R appuser:appgroup /app /config /AudioBooks && \
    chmod -R 775 /app /config /AudioBooks
 
# create package_info dynamically
RUN printf "UpdateMethod=docker\nBranch=%s\nPackageVersion=%s\nPackageAuthor=[%s](https://github.com/%s)\nPackageOwner=%s\nPackageRepo=%s\n" "${READARR__UPDATE__BRANCH}" "${VERSION}" "${VENDOR}" "${VENDOR}" "${PackageOwner}" "${PackageRepo}" > /app/package_info
 
# copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
 
USER appuser:appgroup
WORKDIR /config
VOLUME ["/config"]
 
ENTRYPOINT ["/usr/bin/catatonit", "--", "/entrypoint.sh"]
