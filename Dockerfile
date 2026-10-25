FROM debian:bookworm-slim AS builder

ARG FLUTTER_VERSION=3.47.5
ENV FLUTTER_HOME=/opt/flutter
ENV PATH="${FLUTTER_HOME}/bin:${FLUTTER_HOME}/bin/cache/dart-sdk/bin:${PATH}"

RUN apt-get update \
    && apt-get install --no-install-recommends -y \
      ca-certificates \
      curl \
      git \
      unzip \
      xz-utils \
    && rm -rf /var/lib/apt/lists/* \
    && curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o /tmp/flutter.tar.xz \
    && mkdir -p /opt \
    && tar -xJf /tmp/flutter.tar.xz -C /opt \
    && rm /tmp/flutter.tar.xz \
    && git config --global --add safe.directory /opt/flutter \
    && flutter config --enable-web \
    && flutter precache --web

WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .
RUN flutter build web --release

FROM nginx:1.29-alpine AS runtime
COPY --from=builder /app/build/web /usr/share/nginx/html
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
