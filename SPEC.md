# HLC - Software Requirements Specification

Reverse-engineered from the code at commit `8c54e5b` on 2026-11-18. Every
requirement describes behaviour that the code implements; the source is given
as `path:line`. Nothing here was run except one call of the Python port's
`Config.save_config` on a scratch copy (FR-30): Julia is not installed on the
machine that wrote this document, so "Verification" names a test that exists,
not one that was seen to pass. The project hub is [`docs/README.md`](docs/README.md).

<!-- jira-sync:start -->
Jira: KAN-84

## Tasks

This list is one ticket in Jira project KAN, [KAN-84](https://igorsvolohovs.atlassian.net/browse/KAN-84). Each line is a checkbox there: tick it in Jira and the sync ticks it here; add a checkbox there and it is appended here. Done items are the features described in section 3; open items are what the project declares but the code does not do yet.

- [x] Start-up (section 3.1) <!-- spec-start-up -->
- [x] Monitoring (section 3.2) <!-- spec-monitoring -->
- [x] Input parsing (section 3.3) <!-- spec-input-parsing -->
- [x] Point cloud (section 3.4) <!-- spec-point-cloud -->
- [x] Base plane (first processed index) (section 3.5) <!-- spec-base-plane-first-processed-index -->
- [x] Layer heights (index 2 and later) (section 3.6) <!-- spec-layer-heights-index-2-and-later -->
- [x] Plots (section 3.7) <!-- spec-plots -->
- [x] Configuration, utilities and the Python port (section 3.8) <!-- spec-configuration-utilities-and-the-python-port -->
- [ ] Robot and laser rows are synchronised by their timestamps (declared, not implemented) <!-- spec-robot-and-laser-rows-are-synchronised-by-their-tim -->
- [ ] `config.yaml` holds plot settings (declared, not implemented) <!-- spec-config-yaml-holds-plot-settings -->
- [ ] Plane fitted from points at the edges of the cloud (declared, not implemented) <!-- spec-plane-fitted-from-points-at-the-edges-of-the-cloud -->
- [ ] `plane.exist` marks a computed plane (declared, not implemented) <!-- spec-plane-exist-marks-a-computed-plane -->
- [ ] 2D scattered interpolation (declared, not implemented) <!-- spec-2d-scattered-interpolation -->
- [ ] Automated test suite (declared, not implemented) <!-- spec-automated-test-suite -->
- [ ] Manual test via `julia HLC.jl` (declared, not implemented) <!-- spec-manual-test-via-julia-hlc-jl -->
- [ ] Hardware: Windows 10/11, 8 GB RAM, x64, 1 GB disk (declared, not implemented) <!-- spec-hardware-windows-10-11-8-gb-ram-x64-1-gb-disk -->
- [ ] Automatic correction of the robot or welding (declared, not implemented) <!-- spec-automatic-correction-of-the-robot-or-welding -->

<!-- jira-sync:end -->

## 1. Purpose and scope

HLC calculates and plots the height of deposited layers in Wire Arc Additive
Manufacturing from robot poses and laser line scanner profiles written to CSV
files (`README.md:3-7`).

In scope:

- The Julia application in `src/`: folder selection, polling, geometry, file
  output and plots.
- `config.yaml` and the CSV formats the application reads and writes.
- The Python port in `python/` (section 3.8).
- `metrics_collector.jl` and the scripts in `test/`.

Out of scope:

- Acquisition: the software that writes `RobotCoordinate{N}.csv` and
  `LaserCoordinate{N}.csv` is not in the repository.
- Acting on the process (moving the robot, changing welding parameters): named
  by the write-up as future work (`docs/Application development ... WAAM method.pdf`, p. 5).
- The lab tooling (`recipe.ps1`, `.claude/`, `.gitea/`), apart from NFR-8.

## 2. Context

| Actor or system | Role | Source |
| --- | --- | --- |
| Employee | Additive Lab employee who monitors printing; selects the folder and reads the plots | PDF p. 8; `plantuml/Use case diagram.wsd` |
| Robot and laser scanner software | Writes numbered CSV pairs into the watched folder. Not part of this code; inferred from the file names the code waits for | `src/hlc.jl:92-102` |
| Native folder dialog | NativeFileDialog `pick_folder()` | `src/hlc.jl:197` |
| GLMakie / OpenGL window | Figure sized to the primary monitor | `src/plot/plot.jl:9-16` |
| File system | Input CSV, `config.yaml`, output CSV | sections 4 and 5 |

Runtime environment: Julia, version not stated in any file. The write-up
declares Windows 10/11 desktops (PDF p. 7). The Python port runs on CPython with
tkinter and matplotlib (`python/hlc.py:6`, `18-19`).

## 3. Functional requirements

### 3.1 Start-up

- **FR-1.** The system shall open a native folder dialog and exit with a console
  message when the user cancels it.
  Source: `src/hlc.jl:193-203`. Verification: no test.
- **FR-2.** The system shall log an error and exit when the selected path is not
  a directory.
  Source: `src/hlc.jl:206-214`. Verification: no test.
- **FR-3.** The system shall delete the subfolders `layers` and `current_height`
  of the selected folder if they exist, and create them empty.
  Source: `src/hlc.jl:30-38`. Verification: no test.
- **FR-4.** The system shall load `config.yaml` before the monitoring loop
  and build the laser calibration pose from `calibration.x, y, z, a, b, c`. The
  pose and `plane.scans` are kept from this load; the `Calc` functions re-read
  the file on every call for the other values.
  Source: `src/hlc.jl:79-84`, `139`; `src/calc/plane.jl:78`, `107`, `139`;
  `src/calc/heiht.jl:155`, `259`, `364`, `431`, `470`. Verification: no test.

### 3.2 Monitoring

- **FR-5.** The system shall, at start, count the complete pairs
  `RobotCoordinate{k}.csv` + `LaserCoordinate{k}.csv` for k = 1, 2, ... up to the
  first missing one, and treat them as already seen without processing them;
  only the highest of them is processed, when the next pair appears (FR-7).
  Source: `src/hlc.jl:45-66`. Verification: no test.
- **FR-6.** The system shall check for the complete pair with the next index and,
  if it is missing, sleep 2 seconds before checking again.
  Source: `src/hlc.jl:92-102`, `163-168`, `219`. Verification: no test.
- **FR-7.** When the pair with index N+1 is complete, the system shall process
  pair N (if N > 0) and check the following index without sleeping.
  Source: `src/hlc.jl:102-161`. Verification: manual procedure `test/README.md`.
- **FR-8.** The system shall stop monitoring when the watched folder no longer
  exists, and on Ctrl+C print a shutdown message; any other error shall be
  logged and rethrown.
  Source: `src/hlc.jl:87-90`, `172-182`. Verification: no test.

### 3.3 Input parsing

- **FR-9.** The system shall read a robot CSV into `RobotRow` values from the
  columns `TimeReceived, X, Y, Z, RX, RY, RZ`, using the epoch for an unparsable
  time (with a warning) and, when a number cannot be parsed, the epoch and NaN
  for all six numbers (with an error log).
  Source: `src/calc/points.jl:330-382`. Verification: `test/runtests.jl` testset "RobotRow CSV".
- **FR-10.** The system shall read a laser CSV into `LaserRow` values from the
  columns `TimeReceived, X, Z, Intensity`, where each of `X`, `Z`, `Intensity`
  holds space-separated numbers.
  Source: `src/calc/points.jl:237-287`, `121-137`. Verification: `test/runtests.jl` testsets "_parse_delimited_array", "LaserRow CSV".
- **FR-11.** The system shall accept `TimeReceived` as `yyyy-mm-ddTHH:MM:SS.s` or
  `yyyy-mm-dd HH:MM:SS.s`.
  Source: `src/calc/points.jl:99-105`, `240-266`. Verification: no test.
- **FR-12.** The system shall return an empty vector and log the error when a CSV
  file cannot be read.
  Source: `src/calc/points.jl:434-462`. Verification: `test/runtests.jl` "RobotRow CSV" (non-existent file).

### 3.4 Point cloud

- **FR-13.** The system shall keep, in each laser profile, only the points whose
  laser-frame X lies in `[calibration.laser_min_x, calibration.laser_max_x]`.
  Source: `src/calc/plane.jl:138-158`, `src/hlc.jl:115`. Verification: no test.
- **FR-14.** The system shall compute each world point as
  `T(robot pose) * T(calibration) * [x, 0, z, 1]`, where `T` is built from a
  translation and ZYX Euler angles in degrees.
  Source: `src/calc/points.jl:480-519`, `593-630`. Verification: `test/runtests.jl` testsets "euler_to_transform_y", "calculate_points_row".
- **FR-15.** The system shall pair robot and laser rows by row number up to the
  shorter list, warn when the lengths differ or when paired timestamps differ by
  more than 500 ms, and skip rows with empty laser arrays or an invalid robot row.
  Source: `src/calc/points.jl:647-696`. Verification: `test/runtests.jl` testset "calculate_points".

### 3.5 Base plane (first processed index)

- **FR-16.** For index 1, the system shall fit a plane `Ax + By + Cz + D = 0`
  through all points of the cloud by SVD of the centred coordinates, and write
  `A, B, C, D` to `config.yaml`.
  Source: `src/calc/plane.jl:17-92`, `src/hlc.jl:121-123`. Verification: no test.
- **FR-17.** For index 1, the system shall add the cloud to the point-cloud axis
  in red.
  Source: `src/plot/plot.jl:188-227`, `src/hlc.jl:126`. Verification: no test.

### 3.6 Layer heights (index 2 and later)

- **FR-18.** The system shall reduce each laser profile to one point: sort by Z,
  take the 20 lowest points, fit `z = a*x + b` with Optim LBFGS (started from the
  least-squares solution), and return `(mean x, a*mean x + b)`.
  Source: `src/calc/heiht.jl:166-250`. Verification: no test.
- **FR-19.** The system shall keep only those representative world points whose
  perpendicular distance to the plane is greater than `plane.StdZ`.
  Source: `src/calc/plane.jl:105-136`, `src/hlc.jl:132-133`. Verification: no test.
- **FR-20.** For index 2, the system shall write the x, y of the first and the
  last remaining point to `plane.p0` and `plane.p1` in `config.yaml`.
  Source: `src/calc/heiht.jl:154-164`, `src/hlc.jl:136-138`. Verification: no test.
- **FR-21.** The system shall build a grid of `plane.scans` steps from `p0` to
  `p1`, interpolate Z linearly along X (or along Y when `|p1.x - p0.x| < |p1.y - p0.y|`),
  give grid points outside the data the last valid Z, and set `r` to the distance
  from `p0`.
  Source: `src/calc/heiht.jl:253-348`. Verification: no test.
- **FR-22.** The system shall compute the current height of each grid point as
  its perpendicular distance to the plane and write it to
  `current_height/layers{n}.csv`, n = 1, 2, ...
  Source: `src/calc/heiht.jl:447-495`. Verification: no test.
- **FR-23.** The system shall compute the delta height: when `layers/` is empty,
  as the distance to the plane, saved as `layers1.csv`; otherwise as the
  Euclidean distance between grid point i and point i of the highest-numbered
  `layers{n}.csv`, saved as `layers{n+1}.csv`.
  Source: `src/calc/heiht.jl:350-445`. Verification: no test.

### 3.7 Plots

- **FR-24.** The system shall create one figure sized to the primary monitor with
  the axes "Delta Heights Distribution" (row 1), "Heights Distribution" (row 2),
  and a 3D "Point Cloud" (row 3), and attach a Makie `DataInspector` to it.
  Source: `src/plot/plot.jl:9-50`. Verification: no test.
- **FR-25.** For index 2 and later, the system shall add a scatter series of
  `(r, delta h)` labelled `Layer k-1 to k`, of `(r, h)` labelled `Layer k`, and of
  the cloud labelled `Points k+1`, where k counts the processed layers from 1
  (the base cloud is `Points 1`), replace the legend of each axis, and display the
  figure.
  Source: `src/plot/plot.jl:63-177`, `src/hlc.jl:146-148`. Verification: no test.

Inference: zoom, pan, 3D rotation and point coordinates on hover, which the
write-up lists as requirements (PDF p. 7, 9), come from Makie's default axis
interactions and the `DataInspector`; the project adds no code of its own for
them.

### 3.8 Configuration, utilities and the Python port

- **FR-26.** The system shall load `config.yaml` from the working directory,
  return `nothing` with an error log when the file or the `calibration` or
  `plane` section is missing or a value cannot be read.
  Source: `src/calc/config.jl:46-99`. Verification: no test.
- **FR-27.** The system shall save the configuration with the key order
  calibration (x, y, z, a, b, c, laser_min_x, laser_max_x), plane (exist, A, B, C,
  D, StdZ, p0, p1, scans).
  Source: `src/calc/config.jl:106-144`. Verification: no test.
- **FR-28.** `metrics_collector.jl` shall walk `src/` and print the number of
  files, total, blank, comment and code lines, structs and functions.
  Source: `metrics_collector.jl:6-113`, `118-124`. Verification: no test.
- **FR-29.** The Python port shall select the folder with a tkinter dialog,
  process pair N when pair N+1 is found starting from index 1, and poll every
  2 seconds.
  Source: `python/hlc.py:160-240`, `280-306`. Verification: no test.
- **FR-30.** The Python port shall set `plane.exist` to true when it saves the
  plane, and skip height processing while it is false or the configuration
  cannot be loaded. Measured: `Config.save_config` cannot write the NumPy values
  the plane fit produces (PyYAML `SafeDumper` raises `RepresenterError`) and,
  having opened the file for writing, leaves it empty; so the save never lands
  and every later index skips its heights (`docs/README.md`, section 8).
  Source: `python/plane.py:74-104`, `python/config.py:174-180`,
  `python/hlc.py:87-93`. Verification: no test; `Config.save_config` run once on
  a scratch copy (PyYAML 6.0.2, numpy 2.3.3).
- **FR-31.** The Python port shall, on Ctrl+C, warn that the last found index was
  not processed, and keep the plot window open until it is closed.
  Source: `python/hlc.py:242-272`. Verification: no test.

### 3.9 Declared but not implemented

| Claim | Where declared | What the code does |
| --- | --- | --- |
| Robot and laser rows are synchronised by their timestamps | `README.md:14` | Paired by row number; timestamps only warn (`src/calc/points.jl:636-637`, `665-673`) |
| `config.yaml` holds plot settings | `README.md:29` | No plot keys; `src/plot/plot.jl` reads no configuration |
| Plane fitted from points at the edges of the cloud | `src/calc/plane.jl:6-15` (`num_points_edge = 100`) | All points used, `n_edge = n_points` (`src/calc/plane.jl:25-26`) |
| `plane.exist` marks a computed plane | `config.yaml`, `src/calc/config.jl:22-23` | Never set by the Julia code |
| 2D scattered interpolation | `using ScatteredInterpolation` (`src/calc/heiht.jl:9`) | Calls are commented out (`src/calc/heiht.jl:273-274`, `311-328`) |
| Automated test suite | `test/runtests.jl` | Cannot load: `using ..Calculation` (`test/runtests.jl:13`) while the module is `Calc` |
| Manual test via `julia HLC.jl` | `test/README.md:4` | `src/hlc.jl` defines the module only; the entry point is `src/main.jl` |
| Hardware: Windows 10/11, 8 GB RAM, x64, 1 GB disk | PDF p. 7 | Not checked by any code |
| Automatic correction of the robot or welding | PDF p. 5 ("in the future") | Not present |

## 4. Interfaces

User interface:

| Element | Behaviour | Source |
| --- | --- | --- |
| Folder dialog | Opens at start; cancel exits | `src/hlc.jl:197-203` |
| Plot window | Three axes, legends in column 2, hover inspector | `src/plot/plot.jl:16-50`, `87`, `123`, `172` |
| Console | `@info`, `@warn`, `@error` logs; Ctrl+C stops | `src/hlc.jl:41-43`, `172-182` |

Files:

| File | Direction | Format | Source |
| --- | --- | --- | --- |
| `<folder>/RobotCoordinate{N}.csv` | read | CSV `TimeReceived,X,Y,Z,RX,RY,RZ`; mm and degrees (plot labels, `deg2rad`) | `src/calc/points.jl:330-382`, `480-484` |
| `<folder>/LaserCoordinate{N}.csv` | read | CSV `TimeReceived,X,Z,Intensity`, the last three as space-separated lists | `src/calc/points.jl:237-287` |
| `config.yaml` (working directory) | read and write | YAML, section 5 | `src/calc/config.jl` |
| `<folder>/layers/layers{n}.csv` | write, then read as previous layer | CSV header `x,y,z,r,h` | `src/calc/heiht.jl:379-430` |
| `<folder>/current_height/layers{n}.csv` | write | CSV header `x,y,z,r,h` | `src/calc/heiht.jl:485-492` |
| Python: same inputs; outputs with header `CSV,TimeReceived,X,Y,Z,R,H` | read / write | CSV | `python/height.py:35-47`, `320-333` |

Julia module functions called by `HLC` (`src/hlc.jl`):

| Function | Input | Output |
| --- | --- | --- |
| `Calc.load_config(filename="config.yaml")` | path | `AppConfig` or `nothing` |
| `Calc.csv_to_data_array(T, file)` | `RobotRow` or `LaserRow`, path | `Vector{T}` |
| `Calc.filter_laser_points(rows)` | `Vector{LaserRow}` | `Vector{LaserRow}` |
| `Calc.calculate_points(robot, laser, calibration)` | rows, calibration `RobotRow` | `Vector{Point}` |
| `Calc.calculate_plane(points)` | `Vector{Point}` | `(A, B, C, D)` or `nothing`; writes `config.yaml` |
| `Calc.calculate_laser_mins(rows)` | `Vector{LaserRow}` | one-point `LaserRow` per profile |
| `Calc.filter_by_plane(points)` | `Vector{Point}` | `Vector{Point}` |
| `Calc.calculate_grid_range(points)` | `Vector{Point}` | writes `p0`, `p1` |
| `Calc.calculate_points_on_grid(points, scans)` | `Vector{Point}`, `Int` | `Vector{Height}` |
| `Calc.calculate_delta_heigts_destribution(h, dir)` | `Vector{Height}`, folder | `x, y, z, r, h` vectors; writes `layers/` |
| `Calc.calculate_heigts_destribution(h, dir)` | `Vector{Height}`, folder | `x, y, z, r, h` vectors; writes `current_height/` |
| `Plot.update_plane`, `update_cloud_points`, `update_delta_heigts_destribution`, `update_heigts_destribution` | points or `(r, h)` | adds a series and redraws |

## 5. Data

| Entity | Fields | Source |
| --- | --- | --- |
| `RobotRow` | `csv`, `tm`, `x`, `y`, `z`, `rx`, `ry`, `rz` (degrees); also holds the calibration | `src/calc/points.jl:55-69` |
| `LaserRow` | `csv`, `tm`, `x_array`, `z_array`, `intensity_array::Vector{Int32}` | `src/calc/points.jl:25-36` |
| `Point` | `csv`, `tm`, `x`, `y`, `z` (world frame) | `src/calc/points.jl:83-94` |
| `Height` | `csv`, `tm`, `x`, `y`, `z`, `r` (distance along the grid), `h` | `src/calc/heiht.jl:25-38` |
| `AppConfig` | `calibration::CalibrationConfig`, `plane::PlaneConfig` (with `p0`, `p1::PointConfig`) | `src/calc/config.jl:6-37` |

`config.yaml` keys: `calibration.{x, y, z, a, b, c, laser_min_x, laser_max_x}`,
`plane.{exist, A, B, C, D, StdZ, p0.{x, y}, p1.{x, y}, scans}` (`config.yaml`).
`plane.{A, B, C, D}` change when index 1 is processed and `plane.{p0, p1}` when
index 2 is processed (FR-16, FR-20); neither happens for a pair skipped at start
(FR-5). `python/config.yaml` lacks `laser_min_x` and `laser_max_x`.

Storage is files only; there is no database. Recorded scans are not in the
repository (`.gitignore:39` ignores `*.csv`).

## 6. Non-functional requirements

- **NFR-1.** New scan pairs shall be detected by polling with a 2 s interval,
  without a file-system watcher. Source: `src/hlc.jl:167`, `219`.
- **NFR-2.** A malformed CSV row shall not stop processing: the row is given
  default values and a warning or an error is logged. Source: `src/calc/points.jl:258-260`, `275-285`, `372-380`.
- **NFR-3.** The plot module shall need a monitor and OpenGL at load time
  (inference: it calls `GLFW.GetPrimaryMonitor()` when included).
  Source: `src/plot/plot.jl:9-16`.
- **NFR-4.** All lengths shall be in millimetres and angles in degrees (axis
  labels and `deg2rad`). Source: `src/plot/plot.jl:19-31`, `src/calc/points.jl:482-484`.
- **NFR-5.** Text files shall be stored with LF line endings, PowerShell files
  with CRLF, and PDF and PNG files in Git LFS. Source: `.gitattributes:1-9`.
- **NFR-6.** Recorded scans, `Manifest.toml` and `config_tmp.yaml` shall not be
  committed. Source: `.gitignore:37-39`.
- **NFR-7.** The code is distributed under the MIT licence. Source: `LICENSE`.
- **NFR-8.** The repository shall keep the lab tooling of repo-quality-template;
  `.\recipe.ps1 test` checks only `.claude/` and exits 0 on success.
  Source: `recipe.ps1:41-55`, `README.md:59-63`.

No performance, memory or latency target is stated in code or configuration.

## 7. Constraints and dependencies

| Dependency | Version | Source |
| --- | --- | --- |
| Julia | not stated | no `Project.toml` |
| NativeFileDialog, YAML, OrderedCollections, CSV, DataFrames, Optim, Interpolations, ScatteredInterpolation, Makie, GLMakie, Colors | not pinned | `using` lines in `src/`; `Manifest.toml` ignored (`.gitignore:37`) |
| Julia standard library: Dates, LinearAlgebra, Statistics, Printf, Test | with Julia | `src/`, `test/runtests.jl:3-9` |
| NearestNeighbors, StaticArrays (test script only) | not pinned | `test/test_interp.jl:2-4` |
| numpy, PyYAML, pandas, scipy, matplotlib | not pinned | `python/requirements.txt` |
| tkinter | with CPython | `python/hlc.py:18-19` |
| ruff (tooling) | `==0.16.1` | `.claude/ruff.toml` |

## 8. Acceptance

No automated acceptance exists for the program code (section 3.9). A manual
check that follows `test/README.md` and this specification:

1. From the repository root, run `julia src/main.jl` (`README.md:45`) and select an
   empty folder. Expect `layers/` and `current_height/` to be created (FR-3).
2. Copy pair 1, then pair 2. After pair 2 appears, expect a red cloud in the
   point-cloud axis and new `plane.A..D` in `config.yaml` (FR-7, FR-16, FR-17).
3. Copy pair 3. Expect new `plane.p0`, `plane.p1` in `config.yaml`, files
   `layers/layers1.csv` and `current_height/layers1.csv` with header `x,y,z,r,h`,
   and one new series in each of the three axes (FR-20 to FR-25).
4. Copy pair 4. Expect `layers2.csv` and `current_height/layers2.csv`, and a series
   labelled `Layer 1 to 2` (FR-23, FR-25).
5. Press Ctrl+C. Expect the shutdown message; pair 4 itself stays unprocessed
   (FR-7, FR-8).
6. `.\recipe.ps1 test` exits 0 (NFR-8).

## 9. Open questions

1. Which Julia version and package versions was the program used with? Nothing
   pins them.
2. Which robot, controller and laser scanner produce the CSV files, and which
   program writes them into the folder?
3. Which frame is `calibration` relative to (flange, tool centre point)? The code
   only composes it after the robot pose (`src/calc/points.jl:595-600`).
4. Why do the 20 lowest-Z points of a profile represent the bead? The comment in
   `src/hlc.jl:128` says "max". The direction of the laser Z axis is not stated.
5. Should the delta height be signed? The code uses an unsigned Euclidean
   distance (`src/calc/heiht.jl:420`); a signed `z - z_last` is commented out
   (`src/calc/heiht.jl:419`).
6. Is skipping pairs already present at start (FR-5) intended? The Python port
   does not skip them.
7. Should the last pair be processed on stop? Both versions leave it
   (`python/hlc.py:244-257` carries the code for it, commented out).
8. Is `config.yaml`, a tracked file, meant to be rewritten on every run?
9. Is the Python port maintained? It has known undefined names, a config save
   that empties `config.yaml` (`docs/README.md`, section 8; FR-30) and no laser
   X-range filter.
10. What time per scan is acceptable during printing? No target is given.
11. Where are the recorded scans that `test/README.md` refers to? Partly
    answered by the code: `test/test_adder.jl:148-150` copies them from
    `test/2025-04-30_13-45-49/...` (commented out: `test/2025-03-20_14-52-45/test1`,
    the folder `test/README.md` names) into `test/2025-03-20_14-52-45` of the
    coursework copy `CourceProject3` (`README.md:65`) on the author's machine.
    They are not in this repository; whether they are kept anywhere else is unknown.
