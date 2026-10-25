# RIG-CAR

RIG-CAR is a responsive Flutter web workbench for turning a car model into a
configurable Godot 4 vehicle rig. The first slice provides a complete rigging
flow: import a `.glb` / `.gltf` model, choose a geometry preset, map steering
and traction across four wheels, tune physics values, and export a Godot scene,
controller script, and editable JSON configuration.

The viewport is a procedural preview in this first slice. The imported model
filename and rig settings are carried into the export files; the next slice can
replace the preview with a live GLB renderer and inspect the model's node tree.

## Stack

- Flutter `3.47.5`
- Dart `3.13.4`
- Material 3
- GitHub Pages deployment

## Local setup

```bash
flutter pub get
flutter run -d chrome
```

The package is named `rig_car` because Dart package names use underscores. The
product and repository name are `RIG-CAR` / `rig-car`.

## Checks

```bash
make test
make analyze
make build-web
```

## Export flow

1. Open **Import model** and choose a `.glb` or `.gltf` asset.
2. Select a starting geometry preset.
3. Open **Rig wheels** and set steering, traction, and drivetrain behavior.
4. Open **Tune physics** and adjust mass, engine force, tire grip, suspension,
   and center of mass.
5. Open **Export to Godot** and download `rig_car.tscn`, `rig_car.gd`, and
   `rig_car_config.json`.

The generated scene uses a `VehicleBody3D` root with four `VehicleWheel3D`
nodes. Replace the placeholder collision shape and add the imported mesh under
the generated root in Godot.

## Docker

```bash
docker build -t rig-car .
docker run --rm -p 8080:80 rig-car
```

Open `http://localhost:8080`.

## Live deployment

The GitHub Pages workflow deploys every push to `main`:

https://liokingo2024-prog.github.io/rig-car/
