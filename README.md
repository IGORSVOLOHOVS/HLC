# hlc

HLC, Height Layer Calculation, calculates and visualises the height of each
deposited layer during 3D printing by Wire Arc Additive Manufacturing (WAAM). It
reads the robot's poses and a laser line scanner's profiles, turns them into a
point cloud in world coordinates, and plots the height distribution of the wall
as it grows.

![Real wall](docs/image_real_wall.png)
![Scanned wall](docs/image_scanned_wall.png)

## What it does

- Synchronises robot and laser rows by their timestamps.
- Watches a folder for new scan pairs, `RobotCoordinateN.csv` and
  `LaserCoordinateN.csv`, and processes each pair as it arrives.
- Fits the base plane from the first scan, filters the point cloud against the
  workspace, and interpolates a height grid.
- Plots the point cloud, the current height distribution and its change from the
  previous layer in one GLMakie window.

![Height distribution of a bad bead](docs/image.png)

## What is here

- `src/main.jl` starts the application: `src/hlc.jl` (module `HLC`) asks for a
  folder with a native dialog and monitors it, `src/calc/` (module `Calc`) does
  the geometry, and `src/plot/` (module `Plot`) draws.
- `config.yaml` holds the laser calibration, the base plane and the plot settings.
- `python/` is a Python version of the same pipeline, with `requirements.txt`.
- `test/` holds `runtests.jl` and helper scripts; `test/README.md` describes the
  manual check: start the application and copy the scan pairs into the watched
  folder one by one.
- `plantuml/` holds the use case, component, class and monitoring diagrams.
- `metrics_collector.jl` counts lines, structs and functions in the Julia code.
- `docs/` holds the course project write-up as a PDF and the images above.

## Running it

Julia with CSV, Colors, DataFrames, GLMakie, Makie, Interpolations,
NativeFileDialog, Optim, OrderedCollections, ScatteredInterpolation and YAML in
its environment:

```bash
julia src/main.jl
```

The scans themselves are not in the repository: `*.csv` is ignored.

## What does not work yet

- There is no `Project.toml`, so the dependencies are pinned nowhere and
  `Pkg.test` cannot run.
- `test/runtests.jl` does `using ..Calculation`, a module the code does not
  define, so the suite fails before its first test.

## Working on it

This repository is taken as one that ships no program. `.\recipe.ps1` is still its
whole interface: `.\recipe.ps1 test` runs pytest and ruff over `.claude`, and
nothing over the Julia or Python code, because the standard names no tools for
Julia. `.\recipe.ps1 info` prints the metadata. The other verbs print
`nothing to <verb>`. `CLAUDE.md` holds the rules.

`CourceProject3` is the private coursework copy of this work. The two are not
copies of each other: this one has the write-up PDF, the wall images and a
`.gitignore` the other lacks, and five files differ between them. This one is
the fuller version.

## Licence

MIT. See [LICENSE](LICENSE).

## Lab requirements

This repository complies with [revision 4.0.0](http://127.0.0.1:3000/igors-lab/software-requirements/src/tag/v4.0.0/BEST_REQUIREMENTS.md) of the lab requirements, except R-02 (#7), R-09 (#8), R-13 (#9), R-37 (#10), R-41 (#11), R-42 (#12).
