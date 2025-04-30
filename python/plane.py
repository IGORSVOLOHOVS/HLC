# plane.py
import logging
import numpy as np
from typing import List, Optional, Tuple

# Assuming Point and config structures are defined elsewhere or imported
from points import Point # Requires points.py
from config import Config, AppConfig # Requires config.py

class Plane:
    """Handles plane fitting and point filtering based on plane distance."""

    @staticmethod
    def calculate_plane(points: List[Point], config_filename: str = "config.yaml", num_points_edge: int = 100) -> Optional[Tuple[float, float, float, float]]:
        """
        Calculates the plane Ax + By + Cz + D = 0 approximating the points using SVD.
        Uses points from the edges of the input list. Updates the configuration file.

        Args:
            points: List of Point objects.
            config_filename: Path to the configuration file to update.
            num_points_edge: Number of points to take from each end of the list.

        Returns:
            Tuple (A, B, C, D) of plane parameters if successful, None otherwise.
            The normal vector (A, B, C) is normalized.
        """
        n_points = len(points)
        if n_points < 3:
            logging.error(f"Insufficient points ({n_points}) to define a plane.")
            return None

        # Select points from the edges (assuming points might be ordered by trajectory)
        # n_edge = min(num_points_edge, n_points // 2)
        n_edge = n_points # Use all points as per Julia code logic change

        if n_edge < 1 and n_points >= 3:
            logging.warning(f"Layer is short, using all {n_points} points for plane definition.")
            points_for_plane_indices = list(range(n_points))
        elif n_edge >= 1:
            # Take from beginning and end, ensure unique indices
            indices_first = list(range(min(n_edge, n_points)))
            indices_last = list(range(max(0, n_points - n_edge), n_points))
            points_for_plane_indices = sorted(list(set(indices_first + indices_last)))
        else: # n_points < 3 case already handled
             logging.error(f"Cannot select points for plane (n_edge={n_edge}, n_points={n_points}).")
             return None

        if len(points_for_plane_indices) < 3:
             logging.error(f"Insufficient unique points ({len(points_for_plane_indices)}) after edge selection.")
             return None

        points_for_plane = [points[i] for i in points_for_plane_indices]

        # Convert selected points to a numpy array (N x 3)
        points_matrix = np.array([[p.x, p.y, p.z] for p in points_for_plane])

        # Calculate the centroid
        centroid = np.mean(points_matrix, axis=0) # Shape (3,)

        # Center the points
        centered_points = points_matrix - centroid # Broadcasting centroid

        try:
            # Perform SVD on the centered points matrix (transposed for svd)
            # We want the null space of centered_points.T, which corresponds to the
            # last column of V in U, S, Vh = svd(centered_points)
            # Or equivalently, the last column of U in U, S, Vh = svd(centered_points.T)
            # Let's use the latter approach as it's more direct for the normal vector.
            U, S, Vh = np.linalg.svd(centered_points.T) # SVD of 3xN matrix

            # The normal vector is the left singular vector corresponding to the smallest singular value
            # which is the last column of U.
            normal_vector = U[:, -1] # Shape (3,)
            A, B, C = normal_vector[0], normal_vector[1], normal_vector[2]

            # Ensure the normal vector is normalized (should be by definition from SVD)
            # norm = np.linalg.norm(normal_vector)
            # if norm > 1e-9:
            #     A, B, C = normal_vector / norm
            # else: # Should not happen with SVD if points are not collinear/coincident
            #      logging.error("Normal vector has zero length after SVD.")
            #      return None

            # Calculate D using the centroid: A*cx + B*cy + C*cz + D = 0
            D = -np.dot(normal_vector, centroid)

            # Check for vertical plane (C close to zero)
            if abs(C) < 1e-9:
                logging.warning("Calculated plane is almost vertical (C ≈ 0). Height calculations might be unstable.")

            # --- Update Configuration File ---
            conf = Config.load_config(config_filename)
            if conf is None:
                logging.error(f"Failed to load configuration from '{config_filename}' to save plane parameters.")
                # Return the calculated plane anyway, but config won't be updated
                return A, B, C, D

            conf.plane.A = A
            conf.plane.B = B
            conf.plane.C = C
            conf.plane.D = D
            conf.plane.exist = True # Mark plane as calculated
            Config.save_config(conf, config_filename)
            # ---------------------------------

            logging.info(f"Plane calculated and saved: A={A:.4f}, B={B:.4f}, C={C:.4f}, D={D:.4f}")
            return A, B, C, D

        except np.linalg.LinAlgError as e:
            logging.error(f"SVD computation failed: {e}")
            return None
        except Exception as e:
            logging.exception("An unexpected error occurred during plane calculation:")
            return None


    @staticmethod
    def filter_by_plane(points: List[Point], config_filename: str = "config.yaml") -> List[Point]:
        """
        Filters points, keeping those whose perpendicular distance to the plane
        (defined in the config file) is GREATER than a threshold (config.plane.StdZ).

        Args:
            points: List of Point objects to filter.
            config_filename: Path to the configuration file containing plane parameters (A, B, C, D) and threshold (StdZ).

        Returns:
            A new list containing only the points farther than the threshold from the plane.
        """
        conf = Config.load_config(config_filename)
        if conf is None or not conf.plane.exist:
            logging.error(f"Cannot filter points: Plane parameters not loaded or not calculated in '{config_filename}'.")
            return [] # Return empty list as filtering cannot be performed

        A, B, C, D = conf.plane.A, conf.plane.B, conf.plane.C, conf.plane.D
        threshold = conf.plane.StdZ # Perpendicular distance threshold

        # Denominator for distance calculation: sqrt(A^2 + B^2 + C^2)
        # Since the normal from SVD should be normalized, this should be ~1.0
        norm_sq = A**2 + B**2 + C**2
        if norm_sq < 1e-12: # Check if normal vector is essentially zero
             logging.error("Cannot filter points: Plane normal vector is zero.")
             return []
        norm = math.sqrt(norm_sq)
        if abs(norm - 1.0) > 1e-6: # Check if it's significantly different from 1
            logging.warning(f"Plane normal vector (A,B,C) from config is not normalized (norm={norm:.4f}). Distances might be scaled.")


        filtered_points: List[Point] = []
        for p in points:
            # Calculate perpendicular distance: |Ax + By + Cz + D| / sqrt(A^2 + B^2 + C^2)
            distance = abs(A * p.x + B * p.y + C * p.z + D) / norm

            # Keep points FARTHER than the threshold
            if distance > threshold:
                filtered_points.append(p)

        logging.info(f"Filtered points by plane distance > {threshold:.4f}. Kept {len(filtered_points)} out of {len(points)}.")
        return filtered_points


# Example Usage (optional)
if __name__ == "__main__":
    # Create some dummy points roughly on a plane z = 0.1*x + 0.05*y + 5
    # Plane: 0.1x + 0.05y - z + 5 = 0 => A=0.1, B=0.05, C=-1, D=5
    dummy_points = []
    for x in np.linspace(0, 10, 5):
        for y in np.linspace(0, 10, 5):
            z = 0.1 * x + 0.05 * y + 5 + np.random.randn() * 0.1 # Add noise
            dummy_points.append(Point(x=x, y=y, z=z))

    # Add some outlier points far from the plane
    dummy_points.append(Point(x=5, y=5, z=15))
    dummy_points.append(Point(x=0, y=0, z=-10))

    print(f"Generated {len(dummy_points)} dummy points.")

    # --- Calculate Plane ---
    # Ensure a config file exists or create one first
    # Config.save_config(AppConfig(), "test_plane_config.yaml") # Create if needed

    print("\nCalculating plane...")
    plane_params = Plane.calculate_plane(dummy_points, config_filename="test_plane_config.yaml")

    if plane_params:
        print(f"Calculated plane parameters (A, B, C, D): {plane_params}")

        # --- Filter Points ---
        print("\nFiltering points...")
        # Load the config again to ensure StdZ is set (it might be 0 initially)
        # Manually set a threshold in the config file for testing, e.g., StdZ: 1.0
        # Or update it programmatically:
        temp_conf = Config.load_config("test_plane_config.yaml")
        if temp_conf:
             temp_conf.plane.StdZ = 1.0 # Set threshold for filtering outliers
             Config.save_config(temp_conf, "test_plane_config.yaml")
             print("Set StdZ threshold to 1.0 in config.")

        filtered = Plane.filter_by_plane(dummy_points, config_filename="test_plane_config.yaml")
        print(f"Original points: {len(dummy_points)}, Filtered points (distance > 1.0): {len(filtered)}")
        # Expected: Should keep the outlier points (z=15, z=-10) and maybe a few noisy ones
        print("Kept points:")
        for p in filtered:
             print(f"  (x={p.x:.2f}, y={p.y:.2f}, z={p.z:.2f})")

    else:
        print("Plane calculation failed.")

