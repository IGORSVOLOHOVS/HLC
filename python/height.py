# height.py
import logging
import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import List, Optional, Tuple, Union

import numpy as np
import pandas as pd
from scipy.interpolate import interp1d
# from scipy.interpolate import griddata # For 2D interpolation if needed later
from scipy.optimize import least_squares # Alternative for regression

from config import Config # Requires config.py
from points import Point, LaserRow, _parse_datetime # Requires points.py

@dataclass
class Height:
    """Structure to store a point with its calculated height relative to a plane."""
    csv_source: str = ""
    tm: datetime = field(default_factory=lambda: datetime.fromtimestamp(0, tz=timezone.utc))
    x: float = np.nan
    y: float = np.nan
    z: float = np.nan # Interpolated/calculated Z on grid or plane
    r: float = np.nan # Radial distance or step parameter
    h: float = np.nan # Height relative to baseline/plane

    def __post_init__(self):
        # Ensure datetime is timezone-aware
        if self.tm.tzinfo is None:
            self.tm = self.tm.replace(tzinfo=timezone.utc)

    # Define methods for CSV conversion if needed, or handle directly using pandas
    def to_dict(self) -> dict:
        """Converts Height object to a dictionary for CSV writing."""
        # Format datetime for consistency
        time_str = self.tm.strftime(Points.DATE_FORMAT_OUTPUT)[:-3] if self.tm else "" # Match Julia format
        return {
            "CSV": self.csv_source,
            "TimeReceived": time_str,
            "X": self.x,
            "Y": self.y,
            "Z": self.z,
            "R": self.r,
            "H": self.h
        }

    @staticmethod
    def from_csv_row(csv_row: pd.Series, source: str = "") -> 'Height':
        """Creates a Height object from a pandas Series (CSV row)."""
        return Height(
            csv_source=csv_row.get("CSV", source),
            tm=_parse_datetime(csv_row.get("TimeReceived")),
            x=pd.to_numeric(csv_row.get("X"), errors='coerce'),
            y=pd.to_numeric(csv_row.get("Y"), errors='coerce'),
            z=pd.to_numeric(csv_row.get("Z"), errors='coerce'),
            r=pd.to_numeric(csv_row.get("R"), errors='coerce'),
            h=pd.to_numeric(csv_row.get("H"), errors='coerce')
        )


class HeightCalculator:
    """Calculates height distributions, performs interpolation, and manages layers."""

    @staticmethod
    def calculate_grid_range(points: List[Point], config_filename: str = "config.yaml") -> bool:
        """
        Updates the p0 and p1 grid range points in the configuration file
        based on the first and last point in the provided list.

        Args:
            points: List of Point objects (used to determine range).
            config_filename: Path to the configuration file to update.

        Returns:
            True if successful, False otherwise.
        """
        if not points:
            logging.warning("Cannot calculate grid range: input points list is empty.")
            return False

        config = Config.load_config(config_filename)
        if config is None:
            logging.error(f"Failed to load config '{config_filename}' to update grid range.")
            return False

        # Use first and last points to define the range
        p_start = points[0]
        p_end = points[-1]

        config.plane.p0.x = p_start.x
        config.plane.p0.y = p_start.y
        config.plane.p1.x = p_end.x
        config.plane.p1.y = p_end.y

        Config.save_config(config, config_filename)
        logging.info(f"Grid range updated in '{config_filename}': p0=({p_start.x:.2f}, {p_start.y:.2f}), p1=({p_end.x:.2f}, {p_end.y:.2f})")
        return True

    @staticmethod
    def _linear_regression(x: np.ndarray, z: np.ndarray) -> Tuple[float, float]:
        """
        Performs simple linear regression (z = a*x + b) using numpy's polyfit.

        Args:
            x: Independent variable data (e.g., laser x-coordinates).
            z: Dependent variable data (e.g., laser z-coordinates).

        Returns:
            Tuple (a, b) representing the slope and intercept. Returns (NaN, NaN) if regression fails.
        """
        if x.size < 2 or z.size < 2 or x.size != z.size:
            logging.warning(f"Insufficient or mismatched data for linear regression (x size: {x.size}, z size: {z.size}).")
            return np.nan, np.nan
        try:
            # polyfit returns [slope, intercept] for degree 1
            coeffs = np.polyfit(x, z, 1)
            return coeffs[0], coeffs[1] # a, b
        except (np.linalg.LinAlgError, ValueError) as e:
            logging.error(f"Linear regression failed: {e}")
            return np.nan, np.nan

    @staticmethod
    def calculate_laser_mins(laser_rows: List[LaserRow], num_points: int = 20) -> List[LaserRow]:
        """
        Processes laser scans: sorts by Z, takes lowest points, performs linear regression,
        and returns a representative point (average X, regressed Z) for each scan.

        Args:
            laser_rows: List of LaserRow objects.
            num_points: Number of lowest Z points to consider for regression.

        Returns:
            List of LaserRow objects, each containing a single representative point.
        """
        approximations: List[LaserRow] = []
        for row in laser_rows:
            n = row.x_array.size
            if n == 0:
                logging.warning(f"Skipping empty laser scan (Time: {row.tm}, Source: {row.csv_source})")
                continue

            # Ensure x, z, intensity arrays have the same size
            if not (n == row.z_array.size == row.intensity_array.size):
                 logging.warning(f"Mismatched array sizes in laser scan (Time: {row.tm}, Source: {row.csv_source}). Skipping.")
                 continue

            # Sort by Z value (ascending)
            sort_idx = np.argsort(row.z_array)
            x_sorted = row.x_array[sort_idx]
            z_sorted = row.z_array[sort_idx]
            i_sorted = row.intensity_array[sort_idx] # Keep intensity sorted too

            # Take the first num_points points (lowest Z)
            limit = min(n, num_points)
            x_subset = x_sorted[:limit]
            z_subset = z_sorted[:limit]
            i_subset = i_sorted[:limit] # Keep corresponding intensities

            if limit < 2:
                logging.warning(f"Insufficient points ({limit}) for regression in scan (Time: {row.tm}). Using first point.")
                if limit == 1:
                    approximations.append(LaserRow(
                        csv_source=row.csv_source, tm=row.tm,
                        x_array=np.array([x_subset[0]]),
                        z_array=np.array([z_subset[0]]),
                        intensity_array=np.array([i_subset[0]], dtype=np.int32)
                    ))
                # If limit is 0, we already skipped this row earlier
                continue

            # Linear regression on the subset
            a, b = HeightCalculator._linear_regression(x_subset, z_subset)

            if np.isnan(a) or np.isnan(b):
                 logging.warning(f"Regression failed for scan (Time: {row.tm}). Skipping approximation.")
                 continue # Skip if regression failed

            # Calculate representative point
            x_mean = np.mean(x_subset)
            z_regr = a * x_mean + b
            # Choose a representative intensity (e.g., median index of the subset)
            i_val = i_subset[limit // 2]

            approximations.append(LaserRow(
                csv_source=row.csv_source, tm=row.tm,
                x_array=np.array([x_mean]),
                z_array=np.array([z_regr]),
                intensity_array=np.array([i_val], dtype=np.int32)
            ))

        return approximations


    @staticmethod
    def calculate_points_on_grid(points: List[Point], config_filename: str = "config.yaml") -> List[Height]:
        """
        Interpolates Z values from scattered points onto a 1D grid defined by p0, p1
        and the number of scans in the configuration.

        The interpolation axis (X or Y) is chosen based on the larger range between p0 and p1.

        Args:
            points: List of Point objects (typically filtered minimum points).
            config_filename: Path to the configuration file.

        Returns:
            List of Height objects representing points on the calculated grid.
        """
        if not points:
            logging.warning("Input 'points' for interpolation is empty.")
            return []

        config = Config.load_config(config_filename)
        if config is None:
            logging.error(f"Failed to load config '{config_filename}' for grid interpolation.")
            return []

        p0 = config.plane.p0
        p1 = config.plane.p1
        scans = config.plane.scans
        if scans <= 0:
             logging.error(f"Invalid number of scans ({scans}) in config. Must be positive.")
             return []

        # Determine grid range and interpolation axis
        dx = p1.x - p0.x
        dy = p1.y - p0.y
        r_grid_max = math.sqrt(dx**2 + dy**2)

        x_grid = np.linspace(p0.x, p1.x, scans + 1) # scans intervals -> scans + 1 points
        y_grid = np.linspace(p0.y, p1.y, scans + 1)
        r_grid = np.linspace(0.0, r_grid_max, scans + 1)

        # Extract scattered data
        x_data = np.array([p.x for p in points])
        y_data = np.array([p.y for p in points])
        z_data = np.array([p.z for p in points])

        # Choose interpolation axis based on larger range (like Julia code)
        if abs(dx) >= abs(dy):
            interp_axis_data = x_data
            interp_axis_grid = x_grid
            grid_coords_to_set = x_grid # We will set height.x
            other_coords_grid = y_grid  # We will set height.y
            interp_dim = 'x'
        else:
            interp_axis_data = y_data
            interp_axis_grid = y_grid
            grid_coords_to_set = y_grid # We will set height.y
            other_coords_grid = x_grid  # We will set height.x
            interp_dim = 'y'

        logging.info(f"Interpolating along '{interp_dim}' axis.")

        # Sort data by the chosen interpolation axis for 1D interpolation
        if not np.all(np.diff(interp_axis_data) >= 0): # Check if not sorted
            sort_indices = np.argsort(interp_axis_data)
            interp_axis_data_sorted = interp_axis_data[sort_indices]
            z_data_sorted = z_data[sort_indices]
        else:
            interp_axis_data_sorted = interp_axis_data
            z_data_sorted = z_data

        # Handle duplicate points in the interpolation axis data (required by interp1d)
        unique_indices = np.unique(interp_axis_data_sorted, return_index=True)[1]
        if len(unique_indices) < len(interp_axis_data_sorted):
             logging.warning(f"Duplicate points found along interpolation axis '{interp_dim}'. Using unique points.")
             interp_axis_data_unique = interp_axis_data_sorted[unique_indices]
             z_data_unique = z_data_sorted[unique_indices]
        else:
             interp_axis_data_unique = interp_axis_data_sorted
             z_data_unique = z_data_sorted


        if len(interp_axis_data_unique) < 2:
             logging.error(f"Insufficient unique points ({len(interp_axis_data_unique)}) for 1D interpolation along axis '{interp_dim}'.")
             return []


        # Create 1D linear interpolation function
        # Use fill_value="extrapolate" to handle grid points outside data range, like Julia's default
        try:
            interp_func = interp1d(interp_axis_data_unique, z_data_unique,
                                   kind='linear', bounds_error=False, fill_value="extrapolate")
        except ValueError as e:
             logging.error(f"Failed to create interpolation function: {e}")
             return []


        # Evaluate on the grid
        heights_on_grid: List[Height] = []
        z_interpolated = interp_func(interp_axis_grid)

        for i in range(scans + 1):
            height = Height()
            height.r = r_grid[i]
            height.z = z_interpolated[i]
            height.h = 0 # Initialize height relative to plane as 0

            # Assign X and Y based on the interpolation dimension
            if interp_dim == 'x':
                height.x = grid_coords_to_set[i]
                height.y = other_coords_grid[i] # Y varies linearly along the grid path
            else: # interp_dim == 'y'
                height.y = grid_coords_to_set[i]
                height.x = other_coords_grid[i] # X varies linearly along the grid path

            # Add timestamp? Maybe average or from config? Using default epoch for now.
            height.tm = datetime.fromtimestamp(0, tz=timezone.utc)
            height.csv_source = "InterpolatedGrid"

            heights_on_grid.append(height)

        return heights_on_grid


    @staticmethod
    def _save_heights_to_csv(heights: List[Height], filename: str):
        """Helper to save a list of Height objects to CSV using pandas."""
        if not heights:
            logging.warning(f"No height data to save to '{filename}'.")
            return
        try:
            df = pd.DataFrame([h.to_dict() for h in heights])
            # Define column order
            cols = ["CSV", "TimeReceived", "X", "Y", "Z", "R", "H"]
            df = df[cols] # Reorder columns
            df.to_csv(filename, index=False, float_format='%.6f') # Control float precision
            logging.info(f"Saved {len(heights)} height records to '{filename}'.")
        except Exception as e:
            logging.exception(f"Error saving heights to CSV '{filename}':")

    @staticmethod
    def _load_heights_from_csv(filename: str) -> List[Height]:
        """Helper to load a list of Height objects from CSV using pandas."""
        heights = []
        try:
            df = pd.read_csv(filename)
            required_cols = ['X', 'Y', 'Z', 'R', 'H'] # Minimum required
            if not all(col in df.columns for col in required_cols):
                 missing = [col for col in required_cols if col not in df.columns]
                 logging.error(f"Missing required columns in height CSV '{filename}': {missing}")
                 return []

            for _, row in df.iterrows():
                heights.append(Height.from_csv_row(row, source=filename))
            logging.info(f"Loaded {len(heights)} height records from '{filename}'.")

        except FileNotFoundError:
            logging.warning(f"Height CSV file not found: {filename}") # Warning, might be first layer
        except pd.errors.EmptyDataError:
             logging.warning(f"Height CSV file is empty: {filename}")
        except Exception as e:
            logging.exception(f"Error loading heights from CSV '{filename}':")
        return heights

    @staticmethod
    def _get_last_layer_file(layer_dir: str, prefix: str = "layers", ext: str = ".csv") -> Optional[Tuple[str, int]]:
        """Finds the latest layer file based on numeric index."""
        last_file = None
        max_id = -1
        pattern = re.compile(rf"^{re.escape(prefix)}(\d+){re.escape(ext)}$")

        try:
            if not os.path.isdir(layer_dir):
                logging.warning(f"Layer directory not found: {layer_dir}")
                return None

            for filename in os.listdir(layer_dir):
                match = pattern.match(filename)
                if match:
                    current_id = int(match.group(1))
                    if current_id > max_id:
                        max_id = current_id
                        last_file = os.path.join(layer_dir, filename)

            if last_file:
                return last_file, max_id
            else:
                return None # No matching files found
        except Exception as e:
             logging.exception(f"Error finding last layer file in '{layer_dir}':")
             return None

    @staticmethod
    def calculate_delta_heights_distribution(
        current_heights_on_grid: List[Height],
        output_path: str,
        config_filename: str = "config.yaml"
    ) -> Optional[List[Height]]:
        """
        Calculates the change in height (delta H) between the current layer and the previous one.
        If it's the first layer, calculates height relative to the fitted plane.
        Saves the result as the next layer file.

        Args:
            current_heights_on_grid: List of Height objects for the current layer's grid points.
            output_path: Base directory where 'layers' subdirectory exists or will be created.
            config_filename: Path to the configuration file.

        Returns:
            List of Height objects with the 'h' field representing the delta height (or height above plane for layer 1),
            or None on error.
        """
        if not current_heights_on_grid:
             logging.warning("calculate_delta_heights_distribution received empty current heights.")
             return None

        layer_dir = os.path.join(output_path, "layers")
        os.makedirs(layer_dir, exist_ok=True) # Ensure directory exists

        last_layer_info = HeightCalculator._get_last_layer_file(layer_dir)

        result_heights = [Height(**h.__dict__) for h in current_heights_on_grid] # Deep copy

        if last_layer_info is None: # First layer
            logging.info("First layer detected. Calculating height relative to the plane.")
            config = Config.load_config(config_filename)
            if config is None or not config.plane.exist:
                logging.error("Cannot calculate initial height: Plane config not loaded or plane not calculated.")
                return None

            A, B, C, D = config.plane.A, config.plane.B, config.plane.C, config.plane.D
            norm_sq = A**2 + B**2 + C**2
            if norm_sq < 1e-12:
                 logging.error("Cannot calculate height: Plane normal vector is zero.")
                 return None
            norm = math.sqrt(norm_sq)

            for h_obj in result_heights:
                # Calculate perpendicular distance to plane
                dist = (A * h_obj.x + B * h_obj.y + C * h_obj.z + D) / norm
                # Height is the distance. Clamp at 0 if below the plane.
                # Sign depends on normal vector direction, use absolute distance for thickness.
                h_obj.h = max(0.0, abs(dist)) # Use absolute distance as height above plane

            next_id = 1

        else: # Subsequent layer
            last_layer_file, last_id = last_layer_info
            logging.info(f"Calculating delta height relative to previous layer: {last_layer_file}")
            prev_heights = HeightCalculator._load_heights_from_csv(last_layer_file)

            if not prev_heights or len(prev_heights) != len(result_heights):
                 logging.error(f"Failed to load previous layer or length mismatch "
                               f"(current: {len(result_heights)}, previous: {len(prev_heights)}). Cannot calculate delta.")
                 return None

            # Calculate delta H (difference in Z or perpendicular distance?)
            # Julia code uses distance: sqrt((x-x_l)^2 + (y-y_l)^2 + (z-z_l)^2)
            for i, h_curr in enumerate(result_heights):
                 h_prev = prev_heights[i]
                 # Calculate Euclidean distance between corresponding grid points
                 dx = h_curr.x - h_prev.x
                 dy = h_curr.y - h_prev.y
                 dz = h_curr.z - h_prev.z
                 h_curr.h = math.sqrt(dx**2 + dy**2 + dz**2)
                 # Alternatively, if only Z difference matters: h_curr.h = h_curr.z - h_prev.z

            next_id = last_id + 1

        # Save the result as the new layer file
        new_layer_filename = os.path.join(layer_dir, f"layers{next_id}.csv")
        HeightCalculator._save_heights_to_csv(result_heights, new_layer_filename)

        return result_heights

    @staticmethod
    def calculate_heights_distribution(
        current_heights_on_grid: List[Height],
        output_path: str,
        config_filename: str = "config.yaml"
    ) -> Optional[List[Height]]:
        """
        Calculates the current absolute height relative to the fitted plane for each grid point.
        Saves the result to the 'current_height' directory, incrementing the file index.

        Args:
            current_heights_on_grid: List of Height objects for the current layer's grid points.
            output_path: Base directory where 'current_height' subdirectory exists or will be created.
            config_filename: Path to the configuration file.

        Returns:
            List of Height objects with the 'h' field representing the absolute height above the plane,
            or None on error.
        """
        if not current_heights_on_grid:
             logging.warning("calculate_heights_distribution received empty current heights.")
             return None

        current_height_dir = os.path.join(output_path, "current_height")
        os.makedirs(current_height_dir, exist_ok=True)

        config = Config.load_config(config_filename)
        if config is None or not config.plane.exist:
            logging.error("Cannot calculate current height: Plane config not loaded or plane not calculated.")
            return None

        A, B, C, D = config.plane.A, config.plane.B, config.plane.C, config.plane.D
        norm_sq = A**2 + B**2 + C**2
        if norm_sq < 1e-12:
             logging.error("Cannot calculate height: Plane normal vector is zero.")
             return None
        norm = math.sqrt(norm_sq)

        result_heights = [Height(**h.__dict__) for h in current_heights_on_grid] # Deep copy

        for h_obj in result_heights:
            # Calculate perpendicular distance to plane
            dist = (A * h_obj.x + B * h_obj.y + C * h_obj.z + D) / norm
            # Height is the absolute distance, clamped at 0.
            h_obj.h = max(0.0, abs(dist))

        # Find next file ID for saving
        last_file_info = HeightCalculator._get_last_layer_file(current_height_dir, prefix="layers")
        next_id = last_file_info[1] + 1 if last_file_info else 1

        # Save the result
        new_filename = os.path.join(current_height_dir, f"layers{next_id}.csv")
        HeightCalculator._save_heights_to_csv(result_heights, new_filename)

        return result_heights

