# hlc.py
import logging
import os
import shutil
import time
import matplotlib.pyplot as plt # Import for final show() call
from datetime import datetime
from typing import Optional, Tuple

# Import necessary classes from other modules
from config import Config, AppConfig, PointConfig # Added AppConfig, PointConfig
from height import HeightCalculator, Height # Added Height
from plane import Plane
from plot import Plotter
from points import Points, RobotRow, LaserRow, Point

# Use tkinter for folder selection GUI
import tkinter as tk
from tkinter import filedialog

class HLC:
    """Main class for the Height Layer Calculation (HLC) application."""

    def __init__(self):
        self.plotter: Optional[Plotter] = None
        self.config_file: str = "config.yaml" # Default config file name

    def _initialize_output_dirs(self, base_path: str):
        """Creates or cleans the necessary output directories."""
        layers_dir = os.path.join(base_path, "layers")
        current_height_dir = os.path.join(base_path, "current_height")

        for dir_path in [layers_dir, current_height_dir]:
            try:
                if os.path.exists(dir_path):
                    logging.warning(f"Directory '{dir_path}' already exists. Cleaning it.")
                    shutil.rmtree(dir_path)
                os.makedirs(dir_path)
                logging.info(f"Initialized directory: {dir_path}")
            except Exception as e:
                logging.exception(f"Error initializing directory '{dir_path}':")
                # Decide if this is a fatal error
                raise # Re-raise to stop execution if directories are critical

    def _process_index_data(self, index_to_process: int, monitored_dir: str, calibration: RobotRow):
        """Processes the data for a specific index (reads files, calculates, plots)."""
        logging.info(f"--- Processing data for index: {index_to_process} ---")
        start_time = time.time()

        robot_file_proc = f"RobotCoordinate{index_to_process}.csv"
        laser_file_proc = f"LaserCoordinate{index_to_process}.csv"
        robot_path_proc = os.path.join(monitored_dir, robot_file_proc)
        laser_path_proc = os.path.join(monitored_dir, laser_file_proc)

        try:
            # 1. Read data
            robot_rows = Points.csv_to_robot_rows(robot_path_proc)
            laser_rows = Points.csv_to_laser_rows(laser_path_proc)

            if not robot_rows or not laser_rows:
                logging.warning(f"Empty data found when processing index {index_to_process}. Skipping.")
                return # Skip processing if data is missing

            # 2. Calculate Point Cloud
            cloud_points = Points.calculate_points(robot_rows, laser_rows, calibration)
            if not cloud_points:
                logging.warning(f"Point cloud calculation yielded no points for index {index_to_process}. Skipping.")
                return # Skip if no points

            # 3. Handle based on index
            if index_to_process == 1:
                # First scan: Calculate plane
                logging.info("Processing first scan (index 1): Calculating plane...")
                plane_params = Plane.calculate_plane(cloud_points, self.config_file)
                if plane_params:
                    logging.info("Plane calculated successfully.")
                    # Plot the points used for plane calculation (red)
                    if self.plotter:
                        self.plotter.update_plane_points(cloud_points)
                else:
                    logging.error("Failed to calculate plane for the first scan.")
                    # Decide how to proceed: stop or continue without plane?

            else: # Subsequent scans (index > 1)
                logging.info(f"Processing scan {index_to_process}: Calculating heights...")
                # Reload config in case plane parameters were just updated or StdZ changed
                app_config = Config.load_config(self.config_file)
                if app_config is None or not app_config.plane.exist:
                    logging.error("Plane configuration missing or invalid. Cannot process heights.")
                    # Plot the raw cloud anyway
                    if self.plotter:
                         self.plotter.update_cloud_points(cloud_points)
                    return # Skip height processing

                # a. Find laser minimums (approximated points)
                laser_rows_mins = HeightCalculator.calculate_laser_mins(laser_rows)
                if not laser_rows_mins:
                    logging.warning("No representative laser minimums found.")
                else:
                    # b. Calculate points for minimums
                    # We need robot rows corresponding to the mins. Assume the original robot_rows match laser_rows_mins by index.
                    # This assumes calculate_laser_mins preserves order and length relative to input laser_rows.
                    if len(robot_rows) != len(laser_rows_mins):
                         logging.warning(f"Mismatch between robot rows ({len(robot_rows)}) and laser mins ({len(laser_rows_mins)}). Using original robot rows count.")
                         # Adjust robot_rows if necessary, or handle potential errors
                         # For simplicity, assume they match for now. A more robust solution might involve time matching.

                    cloud_points_mins = Points.calculate_points(robot_rows[:len(laser_rows_mins)], laser_rows_mins, calibration)


                    # c. Filter points by distance to plane
                    cloud_points_filtered = Plane.filter_by_plane(cloud_points_mins, self.config_file)

                    if not cloud_points_filtered:
                        logging.warning("No points remained after filtering by plane distance.")
                    else:
                        # d. Set grid range if it's the second scan being processed (which corresponds to index 2 files)
                        if index_to_process == 2:
                            logging.info("Processing second scan (index 2): Setting grid range...")
                            HeightCalculator.calculate_grid_range(cloud_points_filtered, self.config_file)
                            # Reload config to get updated grid range
                            app_config = Config.load_config(self.config_file)
                            if app_config is None:
                                logging.error("Failed to reload config after setting grid range.")
                                # Continue, but interpolation might use old/default range

                        # e. Interpolate onto grid
                        heights_on_grid = HeightCalculator.calculate_points_on_grid(cloud_points_filtered, self.config_file)

                        if not heights_on_grid:
                            logging.warning("Interpolation onto grid yielded no points.")
                        else:
                            # f. Calculate delta and current heights, save CSVs
                            delta_h = HeightCalculator.calculate_delta_heights_distribution(heights_on_grid, monitored_dir, self.config_file)
                            current_h = HeightCalculator.calculate_heights_distribution(heights_on_grid, monitored_dir, self.config_file)

                            # g. Update plots
                            if self.plotter:
                                if delta_h:
                                    r_delta = [h.r for h in delta_h]
                                    h_delta = [h.h for h in delta_h]
                                    self.plotter.update_delta_heights_distribution(r_delta, h_delta)
                                if current_h:
                                    r_curr = [h.r for h in current_h]
                                    h_curr = [h.h for h in current_h]
                                    self.plotter.update_heights_distribution(r_curr, h_curr)

                # Plot the full (unfiltered) point cloud for this layer (for all layers > 0)
                if self.plotter:
                    self.plotter.update_cloud_points(cloud_points)

        except Exception as e:
            logging.exception(f"Error processing index {index_to_process}:")
            # Decide whether to stop or try to continue

        processing_time = time.time() - start_time
        logging.info(f"--- Finished processing index {index_to_process} in {processing_time:.2f} seconds. ---")


    def monitor_path(self, path: str, interval: int = 2):
        """
        Monitors the specified directory for new pairs of RobotCoordinate and
        LaserCoordinate CSV files. Processes index N only after index N+1 is found.

        Args:
            path: The directory path to monitor.
            interval: The polling interval in seconds.
        """
        monitored_dir = os.path.abspath(path)
        logging.info(f"Starting directory monitoring: {monitored_dir}")
        print("="*40)
        print(f"Monitoring: {monitored_dir}")
        print(f"Check interval: {interval} seconds")
        print("Processing logic: Process index N after files for N+1 are found.")
        print("Press Ctrl+C to stop.")
        print("="*40)


        try:
            # Initialize Plotter
            self.plotter = Plotter()

            # Initialize output directories
            self._initialize_output_dirs(monitored_dir)

            # Load initial configuration and calibration
            calibration = Points.get_calibration(self.config_file)
            if calibration is None:
                logging.error("Failed to load calibration data. Cannot proceed.")
                return

            last_processed_index = 0 # Index whose data has actually been processed and plotted
            last_found_index = 0     # Last index for which BOTH files were confirmed to exist

            while True:
                # --- Check for the next potential pair ---
                next_index_to_check = last_found_index + 1
                logging.debug(f"Checking for index: {next_index_to_check}")

                robot_file_next = f"RobotCoordinate{next_index_to_check}.csv"
                laser_file_next = f"LaserCoordinate{next_index_to_check}.csv"
                robot_path_next = os.path.join(monitored_dir, robot_file_next)
                laser_path_next = os.path.join(monitored_dir, laser_file_next)

                robot_exists = os.path.isfile(robot_path_next)
                laser_exists = os.path.isfile(laser_path_next)

                if robot_exists and laser_exists:
                    # --- New complete pair found ---
                    logging.info(f"Found complete pair for index: {next_index_to_check}")
                    last_found_index = next_index_to_check # Update the latest index found

                    # --- Determine if a previous index can now be processed ---
                    # We process index N only when N+1 is found.
                    # So, if we just found index `last_found_index`, we can process `last_found_index - 1`.
                    index_to_process = last_found_index - 1

                    # Check if this index is greater than the last one we actually processed
                    if index_to_process > last_processed_index and index_to_process > 0:
                        # Process the data for index_to_process
                        self._process_index_data(index_to_process, monitored_dir, calibration)
                        last_processed_index = index_to_process # Mark this index as processed
                    elif index_to_process == 0:
                        logging.info(f"Found first pair (index {last_found_index}). Waiting for index {last_found_index + 1} to process it.")

                    # --- Loop immediately ---
                    # Continue immediately to check for the *next* index (e.g., if multiple pairs appeared)
                    continue # Skip the sleep

                else:
                    # --- Pair not ready yet ---
                    if not robot_exists and not laser_exists:
                        logging.debug(f"Waiting for files for index {next_index_to_check}...")
                    elif not robot_exists:
                        logging.debug(f"Waiting for {robot_file_next} (index {next_index_to_check})...")
                    else: # not laser_exists
                        logging.debug(f"Waiting for {laser_file_next} (index {next_index_to_check})...")

                    # Wait before the next check
                    time.sleep(interval)

        except KeyboardInterrupt:
            logging.info("Ctrl+C received. Shutting down monitoring...")
            # --- Process the last waiting index? ---
            # Decide if the index `last_found_index` (which was found but not processed because `last_found_index + 1` wasn't found)
            # should be processed upon stopping. The Julia code didn't seem to, so we won't by default.
            index_to_process_on_exit = last_found_index
            if index_to_process_on_exit > last_processed_index and index_to_process_on_exit > 0:
                 logging.warning(f"Monitoring stopped. Index {index_to_process_on_exit} was found but its data was not processed because index {index_to_process_on_exit + 1} was not detected.")
                 # Optionally, uncomment the next lines to process the last found index on exit:
                 # print(f"Processing final found index {index_to_process_on_exit} before exiting...")
                 # logging.info(f"Processing final found index {index_to_process_on_exit} before exiting...")
                 # try:
                 #     self._process_index_data(index_to_process_on_exit, monitored_dir, calibration)
                 #     last_processed_index = index_to_process_on_exit
                 # except Exception as e:
                 #     logging.exception(f"Error processing final index {index_to_process_on_exit}:")

        except Exception as e:
            logging.exception("An unexpected error occurred in the monitoring loop:")
        finally:
            if self.plotter:
                logging.info("Closing plot window...")
                # Keep plot open after monitoring stops unless closed explicitly
                # self.plotter.close() # Uncomment to close plot automatically
                # Ensure plot stays visible if not closed
                try:
                    if plt.fignum_exists(self.plotter.fig.number):
                        plt.ioff() # Turn off interactive mode if it was on
                        plt.show() # Keep window open until manually closed
                except Exception as plot_err:
                     logging.error(f"Error keeping plot window open: {plot_err}")

            logging.info("Monitoring stopped.")
            print("="*40)
            print("Monitoring stopped.")
            print("="*40)


    def run(self):
        """Starts the HLC application: prompts for folder and starts monitoring."""
        print("Initializing HLC Application...")
        logging.info("Initializing HLC Application...")

        # --- Folder Selection ---
        root = tk.Tk()
        root.withdraw() # Hide the main tkinter window
        print("Please select the directory containing the scan data...")
        path = filedialog.askdirectory(title="Select Scan Data Folder")
        root.destroy() # Close the tkinter instance

        if not path:
            print("Folder selection cancelled by user. Exiting.")
            logging.info("Folder selection cancelled.")
            return

        if not os.path.isdir(path):
            print(f"Error: Selected path is not a valid directory: {path}")
            logging.error(f"Selected path is not a valid directory: {path}")
            return

        print(f"Selected folder: {path}")
        logging.info(f"User selected folder: {path}")

        # --- Start Monitoring ---
        self.monitor_path(path) # Use default interval

