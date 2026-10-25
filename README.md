# RIG-CAR

A responsive Flutter web dashboard for managing a vehicle fleet. The starter
experience includes a fleet overview, vehicle search, category filters, and
responsive layouts for desktop and mobile screens.

## Stack

- Flutter `3.47.5`
- Dart `3.13.4`
- Material 3
- Web-first deployment with Nginx

## Local setup

Install Flutter `3.47.5`, then run:

```bash
flutter pub get
flutter run -d chrome
```

The project name is `rig_car` because Dart package names use underscores. The
repository and product name remain `rig-car` / `RIG-CAR`.

## Checks

The single offline test command is:

```bash
make test
```

Additional local checks:

```bash
make analyze
make build-web
```

## Docker

Build and run the production web image without installing Flutter locally:

```bash
docker build -t rig-car .
docker run --rm -p 8080:80 rig-car
```

Open `http://localhost:8080`.

## Deploy

The deployable artifact is `build/web`. It can be served by any static web
host. For a container deployment, publish the image built by the Docker
command above to your registry and deploy it on port `80`.
