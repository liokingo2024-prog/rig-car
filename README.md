# RIG-CAR Auto-Rigger & Fleet Library

RIG-CAR is an automated, Mixamo-style 3D car rigging workbench and fleet library for Godot 4.
Browse and export pre-calibrated vehicles (Sports, Off-Road, Utility, Electric), or drop any
`.glb` or `.gltf` vehicle asset into the browser to auto-detect wheels, axles, body, and drivetrain
with an interactive 3D wireframe preview and human-assist review.

## Features

- **Pre-rigged Vehicle Fleet**: Browse ready-to-use car rigs (Apex GT, Vanguard 4x4, Phantom Hyper-EV, Titan Cargo, RallyCross RS, Metro Shuttle) with instant Godot 4 export or workbench tuning.
- **Mixamo-style Auto-Rigger**: One-click "Rig Your Car" flow to upload custom 3D car models.
- **Binary GLB/glTF parser**: decodes nodes, transforms, meshes, primitives, and accessors directly in the browser.
- **Auto-detection heuristics**: detects 4 wheels by name, position, and symmetry; isolates the car body mesh; estimates vehicle mass and archetype.
- **Interactive 3D wireframe viewport**: orbit, zoom, pan, camera presets (ISO, Front, Side, Top), 3D ground grid, and 3D wheel/CoM markers.
- **Mixamo-style human assist**: review auto-detected wheel slots (FL, FR, RL, RR) and reassign any misidentified nodes via dropdown selector.
- **Real-coordinate Godot 4 export**:
  - `rig_car.tscn`: `VehicleBody3D` with exact world positions for all 4 `VehicleWheel3D` nodes.
  - `rig_car.gd`: Input and engine controller script.
  - `rig_car_config.json`: Rig parameters and telemetry.

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

## Checks

```bash
make test
make analyze
make build-web
```

## Workflow

1. **Upload & Scan**: Drop a `.glb` or `.gltf` model. RIG-CAR parses the scene graph and detects vehicle geometry.
2. **Review Detections (Human Assist)**: Inspect the 3D wireframe and confirm or reassign FL, FR, RL, and RR wheel nodes.
3. **Tune Physics**: Adjust vehicle mass, engine force, tire grip, suspension stiffness, and center of mass height.
4. **Export to Godot**: Download `rig_car.tscn`, `rig_car.gd`, and `rig_car_config.json`.

## Docker

```bash
docker build -t rig-car .
docker run --rm -p 8080:80 rig-car
```

Open `http://localhost:8080`.

## Live deployment

The GitHub Pages workflow deploys every push to `main`:

https://liokingo2024-prog.github.io/rig-car/
