# points.py
import logging
import math
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import List, Optional, Tuple, Union

import numpy as np
import pandas as pd
import yaml
from scipy.spatial.transform import Rotation as R

# Import config structures if needed for type hinting or direct use
from config import CalibrationConfig # Assuming RobotRow structure matches CalibrationConfig for YAML loading

# Define common date formats
DATE_FORMAT_STR = "%Y-%m-%dT%H:%M:%S.%f"
DATE_FORMAT_STR_SPACE = "%Y-%m-%d %H:%M:%S.%f"
# Truncate microseconds to milliseconds before formatting for output consistency
DATE_FORMAT_OUTPUT = "%Y-%m-%dT%H:%M:%S.%f"

def _truncate_microseconds(dt: datetime) -> datetime:
    """Truncates microseconds to milliseconds."""
    if dt.microsecond >= 1000:
         # Truncate by removing the last 3 digits of microseconds
         ms = dt.microsecond // 1000
         return dt.replace(microsecond=ms * 1000)
    return dt # No truncation needed if less than 1ms

def _parse_datetime(time_val: Union[str, datetime, pd.Timestamp, None]) -> datetime:
    """Parses various time inputs into a timezone-aware datetime object (UTC)."""
    if isinstance(time_val, datetime):
        # If already datetime, ensure it's timezone-aware (assume UTC if naive)
        if time_val.tzinfo is None:
            return time_val.replace(tzinfo=timezone.utc)
        return time_val
    if isinstance(time_val, pd.Timestamp):
         # Convert pandas Timestamp to datetime, ensure UTC
        dt = time_val.to_pydatetime()
        if dt.tzinfo is None:
            return dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(timezone.utc) # Convert to UTC if different timezone
    if isinstance(time_val, str):
        time_str = time_val.strip()
        # Try parsing with the primary format
        try:
            # Handle potential trailing 'Z' for UTC
            if time_str.endswith('Z'):
                time_str = time_str[:-1] + "+00:00"
                return datetime.fromisoformat(time_str) # Use fromisoformat for robustness
            dt = datetime.strptime(time_str, DATE_FORMAT_STR)
            return dt.replace(tzinfo=timezone.utc) # Assume UTC
        except ValueError:
            # Try parsing with the secondary format
            try:
                dt = datetime.strptime(time_str, DATE_FORMAT_STR_SPACE)
                return dt.replace(tzinfo=timezone.utc) # Assume UTC
            except ValueError:
                # Try ISO format directly
                 try:
                     # Handle potential trailing 'Z' for UTC
                     if time_str.endswith('Z'):
                         time_str = time_str[:-1] + "+00:00"
                     dt_aware = datetime.fromisoformat(time_str)
                     # Ensure it's UTC
                     return dt_aware.astimezone(timezone.utc)
                 except ValueError:
                    logging.warning(f"Failed to parse TimeReceived string '{time_val}' with known formats.")
                    return datetime.fromtimestamp(0, tz=timezone.utc) # Default to epoch UTC
    # Handle None or other unexpected types
    if time_val is not None:
         logging.warning(f"Unexpected type for TimeReceived: {type(time_val)}. Using epoch.")
    return datetime.fromtimestamp(0, tz=timezone.utc) # Default to epoch UTC

def _parse_delimited_array(s: Optional[str], dtype: type = float, delim: str = ' ') -> np.ndarray:
    """Parses a delimited string into a numpy array."""
    if s is None or not isinstance(s, str):
        return np.array([], dtype=dtype)
    s_stripped = s.strip()
    if not s_stripped:
        return np.array([], dtype=dtype)
    parts = s_stripped.split(delim)
    try:
        # Filter out empty strings that might result from multiple delimiters
        valid_parts = [part for part in parts if part]
        arr = np.array(valid_parts, dtype=dtype)
        return arr
    except ValueError as e:
        logging.warning(f"Failed to parse array string '{s}' into array of {dtype} with delimiter '{delim}': {e}")
        return np.array([], dtype=dtype)

def _format_delimited_array(arr: np.ndarray, delim: str = ' ') -> str:
    """Formats a numpy array into a delimited string."""
    if arr is None or arr.size == 0:
        return ""
    return delim.join(map(str, arr))


@dataclass
class LaserRow:
    """Represents a single row of laser scanner data."""
    csv_source: str = ""
    tm: datetime = field(default_factory=lambda: datetime.fromtimestamp(0, tz=timezone.utc))
    x_array: np.ndarray = field(default_factory=lambda: np.array([], dtype=float))
    z_array: np.ndarray = field(default_factory=lambda: np.array([], dtype=float))
    intensity_array: np.ndarray = field(default_factory=lambda: np.array([], dtype=np.int32))

    def __post_init__(self):
        # Ensure arrays are numpy arrays
        if not isinstance(self.x_array, np.ndarray):
            self.x_array = np.array(self.x_array, dtype=float)
        if not isinstance(self.z_array, np.ndarray):
            self.z_array = np.array(self.z_array, dtype=float)
        if not isinstance(self.intensity_array, np.ndarray):
            self.intensity_array = np.array(self.intensity_array, dtype=np.int32)
        # Ensure datetime is timezone-aware
        if self.tm.tzinfo is None:
             self.tm = self.tm.replace(tzinfo=timezone.utc)


@dataclass
class RobotRow:
    """Represents the pose (position and orientation) of a robot."""
    csv_source: str = ""
    tm: datetime = field(default_factory=lambda: datetime.fromtimestamp(0, tz=timezone.utc))
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    rx: float = 0.0  # Roll in degrees
    ry: float = 0.0  # Pitch in degrees
    rz: float = 0.0  # Yaw in degrees

    def __post_init__(self):
         # Ensure datetime is timezone-aware
         if self.tm.tzinfo is None:
             self.tm = self.tm.replace(tzinfo=timezone.utc)

@dataclass
class Point:
    """Represents a single point in 3D space (world frame)."""
    csv_source: str = ""
    tm: datetime = field(default_factory=lambda: datetime.fromtimestamp(0, tz=timezone.utc))
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0

    def __post_init__(self):
         # Ensure datetime is timezone-aware
         if self.tm.tzinfo is None:
             self.tm = self.tm.replace(tzinfo=timezone.utc)

class Points:
    """Handles data structures, transformations, and I/O for point cloud data."""

    @staticmethod
    def get_calibration(filename: str = "config.yaml") -> Optional[RobotRow]:
        """
        Loads calibration data from the 'calibration' section of a YAML file.

        Args:
            filename: Path to the YAML configuration file.

        Returns:
            A RobotRow object containing calibration data, or None on error.
        """
        try:
            with open(filename, 'r') as f:
                raw_config = yaml.safe_load(f)

            if not raw_config or "calibration" not in raw_config:
                logging.error(f"Missing 'calibration' section in '{filename}'.")
                return None

            cal_data = raw_config["calibration"]
            req_keys = ["x", "y", "z", "a", "b", "c"]
            if not all(key in cal_data for key in req_keys):
                logging.error(f"Missing required keys in 'calibration' section of '{filename}'.")
                return None

            # Map YAML a, b, c to RobotRow rx, ry, rz
            calibration_row = RobotRow(
                csv_source=filename,
                tm=datetime.fromtimestamp(0, tz=timezone.utc), # Default timestamp
                x=float(cal_data["x"]),
                y=float(cal_data["y"]),
                z=float(cal_data["z"]),
                rx=float(cal_data["a"]), # Roll
                ry=float(cal_data["b"]), # Pitch
                rz=float(cal_data["c"])  # Yaw
            )
            return calibration_row

        except FileNotFoundError:
            logging.error(f"Configuration file not found: {filename}")
            return None
        except (yaml.YAMLError, KeyError, TypeError, ValueError) as e:
            logging.error(f"Error loading or parsing calibration from '{filename}': {e}")
            return None
        except Exception as e:
            logging.exception(f"Unexpected error loading calibration from '{filename}':")
            return None

    @staticmethod
    def csv_to_laser_rows(file_path: str) -> List[LaserRow]:
        """Reads a LaserRow CSV file into a list of LaserRow objects."""
        rows = []
        try:
            # Use pandas for robust CSV reading
            df = pd.read_csv(file_path, dtype={'X': str, 'Z': str, 'Intensity': str}) # Read arrays as strings initially

            required_cols = ['TimeReceived', 'X', 'Z', 'Intensity']
            if not all(col in df.columns for col in required_cols):
                 missing = [col for col in required_cols if col not in df.columns]
                 logging.error(f"Missing required columns in '{file_path}': {missing}")
                 return []

            for _, csv_row in df.iterrows():
                tm = _parse_datetime(csv_row['TimeReceived'])
                x_array = _parse_delimited_array(csv_row['X'], dtype=float)
                z_array = _parse_delimited_array(csv_row['Z'], dtype=float)
                intensity_array = _parse_delimited_array(csv_row['Intensity'], dtype=np.int32)

                # Basic validation on array lengths (optional but good)
                if not (len(x_array) == len(z_array) == len(intensity_array)):
                     logging.warning(f"Array length mismatch in row with time {tm} in '{file_path}'. "
                                     f"Lengths: X={len(x_array)}, Z={len(z_array)}, Intensity={len(intensity_array)}. Skipping row.")
                     continue # Skip rows with inconsistent data

                rows.append(LaserRow(
                    csv_source=file_path,
                    tm=tm,
                    x_array=x_array,
                    z_array=z_array,
                    intensity_array=intensity_array
                ))
        except FileNotFoundError:
            logging.error(f"LaserRow CSV file not found: {file_path}")
        except pd.errors.EmptyDataError:
             logging.warning(f"LaserRow CSV file is empty: {file_path}")
        except Exception as e:
            logging.exception(f"Failed to read or process LaserRow CSV '{file_path}':")
        return rows

    @staticmethod
    def csv_to_robot_rows(file_path: str) -> List[RobotRow]:
        """Reads a RobotRow CSV file into a list of RobotRow objects."""
        rows = []
        try:
            df = pd.read_csv(file_path)
            required_cols = ['TimeReceived', 'X', 'Y', 'Z', 'RX', 'RY', 'RZ']
            if not all(col in df.columns for col in required_cols):
                 missing = [col for col in required_cols if col not in df.columns]
                 logging.error(f"Missing required columns in '{file_path}': {missing}")
                 return []

            for _, csv_row in df.iterrows():
                 # Use pd.to_numeric for robust conversion, coercing errors to NaN
                 x = pd.to_numeric(csv_row['X'], errors='coerce')
                 y = pd.to_numeric(csv_row['Y'], errors='coerce')
                 z = pd.to_numeric(csv_row['Z'], errors='coerce')
                 rx = pd.to_numeric(csv_row['RX'], errors='coerce')
                 ry = pd.to_numeric(csv_row['RY'], errors='coerce')
                 rz = pd.to_numeric(csv_row['RZ'], errors='coerce')

                 # Check if any required numeric value failed to parse
                 if pd.isna([x, y, z, rx, ry, rz]).any():
                     logging.warning(f"Could not parse numeric data in row: {csv_row.to_dict()} in '{file_path}'. Skipping row.")
                     continue

                 tm = _parse_datetime(csv_row['TimeReceived'])

                 rows.append(RobotRow(
                     csv_source=file_path,
                     tm=tm,
                     x=x, y=y, z=z,
                     rx=rx, ry=ry, rz=rz
                 ))
        except FileNotFoundError:
            logging.error(f"RobotRow CSV file not found: {file_path}")
        except pd.errors.EmptyDataError:
             logging.warning(f"RobotRow CSV file is empty: {file_path}")
        except Exception as e:
            logging.exception(f"Failed to read or process RobotRow CSV '{file_path}':")
        return rows

    @staticmethod
    def euler_to_transform(pose: RobotRow) -> np.ndarray:
        """
        Converts Euler angles (ZYX convention, degrees) and translation
        from a RobotRow into a 4x4 homogeneous transformation matrix.

        Args:
            pose: RobotRow object containing pose information.

        Returns:
            A 4x4 numpy array representing the transformation matrix.
        """
        # Create rotation object from ZYX Euler angles in degrees
        # Note: scipy uses intrinsic rotations. ZYX intrinsic is equivalent to xyz extrinsic.
        # If the Julia code used extrinsic, the order might need reversal ('xyz').
        # Assuming ZYX intrinsic based on typical robotics usage.
        rotation = R.from_euler('zyx', [pose.rz, pose.ry, pose.rx], degrees=True)
        rotation_matrix = rotation.as_matrix()

        # Create 4x4 transformation matrix
        transform = np.identity(4)
        transform[0:3, 0:3] = rotation_matrix
        transform[0:3, 3] = [pose.x, pose.y, pose.z]

        return transform

    @staticmethod
    def transform_to_euler(matrix: np.ndarray) -> RobotRow:
        """
        Extracts Euler angles (ZYX convention, degrees) and translation
        from a 4x4 transformation matrix.

        Args:
            matrix: A 4x4 numpy array transformation matrix.

        Returns:
            A RobotRow object with extracted pose. csv_source and tm are default.
        """
        if matrix.shape != (4, 4):
            raise ValueError("Input matrix must be 4x4.")

        # Extract rotation matrix part
        rotation_matrix = matrix[0:3, 0:3]
        # Extract translation part
        translation = matrix[0:3, 3]

        # Create rotation object
        rotation = R.from_matrix(rotation_matrix)
        # Extract ZYX Euler angles in degrees
        # Note: Ensure this matches the convention used in euler_to_transform
        euler_angles_deg = rotation.as_euler('zyx', degrees=True)

        pose = RobotRow(
            x=translation[0],
            y=translation[1],
            z=translation[2],
            rz=euler_angles_deg[0], # Yaw
            ry=euler_angles_deg[1], # Pitch
            rx=euler_angles_deg[2]  # Roll
        )
        return pose

    @staticmethod
    def calculate_points_row(robot_row: RobotRow, laser_row: LaserRow, calibration: RobotRow) -> List[Point]:
        """
        Calculates world coordinates of laser points for a single timestamp.

        Args:
            robot_row: Robot's pose at the time of the scan.
            laser_row: Laser scan data relative to the sensor.
            calibration: Pose of the laser sensor relative to the robot base.

        Returns:
            List of calculated Point objects in the world frame.
        """
        if not isinstance(robot_row, RobotRow) or not isinstance(laser_row, LaserRow) or not isinstance(calibration, RobotRow):
             logging.error("Invalid input types for calculate_points_row.")
             return []
        if laser_row.x_array.size == 0 or laser_row.z_array.size == 0:
            logging.warning(f"Empty laser data for timestamp {laser_row.tm}. Skipping point calculation.")
            return []
        if laser_row.x_array.shape != laser_row.z_array.shape:
             logging.warning(f"Mismatched X/Z array shapes for timestamp {laser_row.tm}. Skipping.")
             return []


        T_world_robot = Points.euler_to_transform(robot_row)
        T_robot_laser = Points.euler_to_transform(calibration)
        T_world_laser = T_world_robot @ T_robot_laser # Matrix multiplication

        points_world: List[Point] = []
        num_laser_points = laser_row.x_array.size

        # Prepare laser points in homogeneous coordinates (N x 4)
        # Assuming laser points are in the XZ plane of the laser frame (Y=0)
        laser_points_local = np.zeros((num_laser_points, 4))
        laser_points_local[:, 0] = laser_row.x_array # X coordinates
        laser_points_local[:, 2] = laser_row.z_array # Z coordinates
        laser_points_local[:, 3] = 1.0              # Homogeneous coordinate

        # Transform points: T_world_laser (4x4) * laser_points_local.T (4xN) -> 4xN
        # Transpose result back to N x 4
        world_points_homogeneous = (T_world_laser @ laser_points_local.T).T

        # Extract world coordinates and create Point objects
        for i in range(num_laser_points):
            p_world = world_points_homogeneous[i, 0:3] # Extract x, y, z
            points_world.append(Point(
                csv_source=laser_row.csv_source, # Inherit source from laser data
                tm=laser_row.tm,              # Use laser timestamp
                x=p_world[0],
                y=p_world[1],
                z=p_world[2]
            ))

        return points_world

    @staticmethod
    def calculate_points(robot_rows: List[RobotRow], laser_rows: List[LaserRow], calibration: RobotRow) -> List[Point]:
        """
        Calculates world coordinates for multiple laser scans based on corresponding robot poses.
        Assumes a one-to-one correspondence by index.

        Args:
            robot_rows: List of robot poses.
            laser_rows: List of laser scans.
            calibration: Sensor pose relative to the robot base.

        Returns:
            Flattened list of all calculated Point objects.
        """
        if not robot_rows or not laser_rows:
            logging.warning("Empty robot or laser data provided to calculate_points.")
            return []
        if not isinstance(calibration, RobotRow):
             logging.error("Invalid calibration data provided.")
             return []

        min_len = min(len(robot_rows), len(laser_rows))
        if len(robot_rows) != len(laser_rows):
            logging.warning(f"Robot ({len(robot_rows)}) and Laser ({len(laser_rows)}) row counts differ. "
                            f"Processing only the first {min_len} pairs.")

        all_points: List[Point] = []
        for i in range(min_len):
            robot_row = robot_rows[i]
            laser_row = laser_rows[i]

            # Optional: Timestamp check (adjust threshold as needed)
            time_diff = abs(robot_row.tm - laser_row.tm)
            if time_diff.total_seconds() > 0.5: # 500ms threshold
                logging.warning(f"Timestamp mismatch for index {i}: Robot={robot_row.tm}, Laser={laser_row.tm}. Diff: {time_diff}")

            # Basic validity checks before processing the row
            if laser_row.x_array.size == 0 or laser_row.z_array.size == 0:
                 logging.warning(f"Skipping index {i} due to empty laser arrays (Time: {laser_row.tm})")
                 continue
            if np.isnan([robot_row.x, robot_row.y, robot_row.z, robot_row.rx, robot_row.ry, robot_row.rz]).any():
                 logging.warning(f"Skipping index {i} due to NaN in RobotRow data: {robot_row}")
                 continue


            points_for_row = Points.calculate_points_row(robot_row, laser_row, calibration)
            all_points.extend(points_for_row)

        return all_points

