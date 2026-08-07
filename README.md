# HLC - Height Layer Calculation for WAAM

![Real Wall](docs/image_real_wall.png)
![Scanned Wall](docs/image_scanned_wall.png)

## Overview
This application is designed for calculating and visualizing the distributed height of layers during 3D printing using the **Wire Arc Additive Manufacturing (WAAM)** method. It processes laser scanning data and robot positioning coordinates to monitor and analyze the build process.

## Key Features
- **Data Synchronization**: Synchronizes robot and laser sensor data based on timestamps.
- **Automated Processing**: Monitors directories for new scan files (`RobotCoordinateX.csv` and `LaserCoordinateX.csv`) and processes them automatically.
- **Geometric Analysis**: 
  - Calculates the base plane from the initial scan.
  - Filters point clouds relative to the workspace geometry.
  - Interpolates and generates height distribution grids.
- **Real-time Visualization**: Provides visual feedback on point clouds and layer height distributions.

## Tools and Technologies

### Languages
- **Julia**: Primary language used for core calculation logic, real-time monitoring, and high-performance data processing.
- **Python**: Used for supplementary data analysis, configuration handling, and advanced plotting.

### Libraries & Frameworks
- **Julia Ecosystem**:
  - `NativeFileDialog`: GUI for folder selection.
  - `Dates`: Timestamp and temporal data management.
  - `StaticArrays`: Optimized memory usage for geometric computations.
  - `Printf`: Formatted output for metrics and logs.
- **Python Ecosystem**:
  - `NumPy`, `Pandas`: Efficient handling of large datasets and CSV processing.
  - `SciPy`: Advanced scientific and technical computing.
  - `Matplotlib`: Generation of high-quality visualizations.
  - `PyYAML`: Management of application configuration files.

## Visualization of bad valik
![Height Distribution Visualization](docs/image.png)

## Documentation
Cource project:

[📄 Application development for calculating and visualizing the distributed height of layers during 3D printing using the WAAM method.pdf](<docs/Application development for calculating and visualizing the distributed height of layers during 3D printing using the WAAM method.pdf>)

## Two repositories, one project

`CourceProject3` is the private coursework copy of this work. They are not
copies of each other, which is worth stating because their file lists look
almost the same: 30 of the 36 files there are byte-identical to files here, but
this repository has ten the other does not - the write-up PDF, the wall images,
a `.gitignore` - and five files exist in both with different content, `README.md`
and `config.yaml` among them.

This one is the fuller version and the public one. Read it first.
