# config.py
import yaml
import logging
from dataclasses import dataclass, field
from typing import Optional, Dict, Any

# Setup basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

@dataclass
class PointConfig:
    """Configuration for a 2D point."""
    x: float = 0.0
    y: float = 0.0

@dataclass
class CalibrationConfig:
    """Configuration for calibration parameters."""
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    a: float = 0.0  # Corresponds to rx (roll)
    b: float = 0.0  # Corresponds to ry (pitch)
    c: float = 0.0  # Corresponds to rz (yaw)

@dataclass
class PlaneConfig:
    """Configuration related to the calculated plane."""
    exist: bool = False
    A: float = 0.0
    B: float = 0.0
    C: float = 0.0
    D: float = 0.0
    StdZ: float = 0.0 # Threshold for filtering points near the plane
    p0: PointConfig = field(default_factory=PointConfig) # Start point for grid range
    p1: PointConfig = field(default_factory=PointConfig) # End point for grid range
    scans: int = 100 # Number of steps/scans for grid interpolation

@dataclass
class AppConfig:
    """Main application configuration structure."""
    calibration: CalibrationConfig = field(default_factory=CalibrationConfig)
    plane: PlaneConfig = field(default_factory=PlaneConfig)

class Config:
    """Handles loading and saving of application configuration using YAML."""

    @staticmethod
    def load_config(filename: str = "config.yaml") -> Optional[AppConfig]:
        """
        Loads configuration from a YAML file and returns an AppConfig object.

        Args:
            filename: The path to the YAML configuration file.

        Returns:
            An AppConfig object if successful, None otherwise.
        """
        try:
            with open(filename, 'r') as f:
                raw_config = yaml.safe_load(f)

            if not raw_config:
                logging.error(f"Configuration file '{filename}' is empty or invalid.")
                return None

            # Basic validation
            if "calibration" not in raw_config or "plane" not in raw_config:
                logging.error(f"Missing required sections 'calibration' or 'plane' in '{filename}'.")
                return None

            cal_data = raw_config["calibration"]
            plane_data = raw_config["plane"]

            # More detailed validation (check required keys)
            req_cal_keys = ["x", "y", "z", "a", "b", "c"]
            req_plane_keys = ["exist", "A", "B", "C", "D", "StdZ", "p0", "p1", "scans"]
            req_point_keys = ["x", "y"]

            for key in req_cal_keys:
                if key not in cal_data:
                    logging.error(f"Missing key '{key}' in 'calibration' section of '{filename}'.")
                    return None
            for key in req_plane_keys:
                if key not in plane_data:
                    logging.error(f"Missing key '{key}' in 'plane' section of '{filename}'.")
                    return None
            if "p0" not in plane_data or "p1" not in plane_data:
                 logging.error(f"Missing 'p0' or 'p1' in 'plane' section of '{filename}'.")
                 return None
            for key in req_point_keys:
                 if key not in plane_data["p0"]:
                     logging.error(f"Missing key '{key}' in 'plane.p0' section of '{filename}'.")
                     return None
                 if key not in plane_data["p1"]:
                     logging.error(f"Missing key '{key}' in 'plane.p1' section of '{filename}'.")
                     return None

            # Create nested structures
            p0 = PointConfig(x=float(plane_data["p0"]["x"]), y=float(plane_data["p0"]["y"]))
            p1 = PointConfig(x=float(plane_data["p1"]["x"]), y=float(plane_data["p1"]["y"]))

            # Create main structures
            calibration_config = CalibrationConfig(
                x=float(cal_data["x"]), y=float(cal_data["y"]), z=float(cal_data["z"]),
                a=float(cal_data["a"]), b=float(cal_data["b"]), c=float(cal_data["c"])
            )

            plane_config = PlaneConfig(
                exist=bool(plane_data["exist"]),
                A=float(plane_data["A"]), B=float(plane_data["B"]),
                C=float(plane_data["C"]), D=float(plane_data["D"]),
                StdZ=float(plane_data["StdZ"]),
                p0=p0, p1=p1,
                scans=int(plane_data["scans"])
            )

            app_config = AppConfig(calibration=calibration_config, plane=plane_config)
            logging.info(f"Configuration loaded successfully from '{filename}'.")
            return app_config

        except FileNotFoundError:
            logging.error(f"Configuration file not found: {filename}")
            return None
        except yaml.YAMLError as e:
            logging.error(f"Error parsing YAML file '{filename}': {e}")
            return None
        except (KeyError, TypeError, ValueError) as e:
             logging.error(f"Error processing configuration data from '{filename}': {e}")
             return None
        except Exception as e:
            logging.exception(f"An unexpected error occurred while loading config from '{filename}':")
            return None

    @staticmethod
    def save_config(config: AppConfig, filename: str = "config.yaml") -> None:
        """
        Saves the AppConfig object to a YAML file.

        Args:
            config: The AppConfig object to save.
            filename: The path to the YAML file to save to.
        """
        # Convert dataclasses to a dictionary structure suitable for YAML
        config_dict: Dict[str, Any] = {
            "calibration": {
                "x": config.calibration.x,
                "y": config.calibration.y,
                "z": config.calibration.z,
                "a": config.calibration.a,
                "b": config.calibration.b,
                "c": config.calibration.c
            },
            "plane": {
                "exist": config.plane.exist,
                "A": config.plane.A,
                "B": config.plane.B,
                "C": config.plane.C,
                "D": config.plane.D,
                "StdZ": config.plane.StdZ,
                "p0": {
                    "x": config.plane.p0.x,
                    "y": config.plane.p0.y
                },
                "p1": {
                    "x": config.plane.p1.x,
                    "y": config.plane.p1.y
                },
                "scans": config.plane.scans
            }
        }

        try:
            with open(filename, 'w') as f:
                # Use sort_keys=False to preserve order as much as possible (though dicts are inherently unordered pre-Python 3.7)
                # Dumper=yaml.SafeDumper ensures standard YAML output
                yaml.dump(config_dict, f, default_flow_style=False, sort_keys=False, Dumper=yaml.SafeDumper)
            logging.info(f"Configuration saved successfully to '{filename}'.")
        except Exception as e:
            logging.exception(f"Error saving configuration to file '{filename}':")

