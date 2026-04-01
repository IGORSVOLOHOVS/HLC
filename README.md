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