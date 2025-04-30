# plot.py
import logging
import time
from typing import List, Optional, Tuple, Union

import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import PathCollection
from matplotlib.legend import Legend
from mpl_toolkits.mplot3d import Axes3D

# Assuming Point and Height structures are defined elsewhere
from points import Point # Requires points.py
from height import Height # Requires height.py

# Enable interactive mode for non-blocking plots
plt.ion()

class Plotter:
    """Handles plotting of point clouds and height distributions using Matplotlib."""

    def __init__(self):
        """Initializes the Matplotlib figure and axes."""
        logging.info("Initializing Plotter...")
        try:
            # Get screen size for figure placement (optional)
            # screen_width, screen_height = self._get_screen_resolution()
            # Use a reasonable default size
            screen_width, screen_height = 1200, 900

            self.fig = plt.figure(figsize=(screen_width / 100, screen_height / 100)) # inches
            self.fig.canvas.manager.set_window_title('HLC Data Visualization') # Set window title


            # --- Create Axes ---
            # GridSpec for layout (3 rows, 2 columns: plots in col 1, legends in col 2)
            gs = self.fig.add_gridspec(3, 2, width_ratios=[4, 1]) # Plots take more space

            # Delta Heights Distribution (Top Left)
            self.ax_hd = self.fig.add_subplot(gs[0, 0])
            self.ax_hd.set_title("Delta Heights Distribution")
            self.ax_hd.set_xlabel("Step (Radius/Index)") # Changed from mm, R is not always mm
            self.ax_hd.set_ylabel("ΔHeight (mm)")
            self.ax_hd.grid(True, linestyle='--', alpha=0.6)
            self._hd_legend: Optional[Legend] = None # Store legend object

            # Current Heights Distribution (Middle Left)
            self.ax_chd = self.fig.add_subplot(gs[1, 0], sharex=self.ax_hd) # Share x-axis
            self.ax_chd.set_title("Heights Distribution")
            self.ax_chd.set_xlabel("Step (Radius/Index)")
            self.ax_chd.set_ylabel("Height (mm)")
            self.ax_chd.grid(True, linestyle='--', alpha=0.6)
            self._chd_legend: Optional[Legend] = None

            # Point Cloud (Bottom Left)
            self.ax_pc = self.fig.add_subplot(gs[2, 0], projection='3d')
            self.ax_pc.set_title("Point Cloud")
            self.ax_pc.set_xlabel("X (mm)")
            self.ax_pc.set_ylabel("Y (mm)")
            self.ax_pc.set_zlabel("Z (mm)")
            # Make axes equal for better 3D representation
            # self.ax_pc.set_aspect('equal', adjustable='box') # May cause issues with autoscaling
            self.ax_pc.grid(True)
            self._pc_legend: Optional[Legend] = None

            # Axes for legends (Right Column) - We'll place legends here manually
            self.ax_hd_legend_pos = gs[0, 1]
            self.ax_chd_legend_pos = gs[1, 1]
            self.ax_pc_legend_pos = gs[2, 1]


            # Store plot handles (scatter objects) to update legends
            self._hd_plots: List[PathCollection] = []
            self._chd_plots: List[PathCollection] = []
            self._pc_plots: List[PathCollection] = [] # For 3D plots (use Path3DCollection if needed)

            # IDs for labeling layers/datasets
            self._hd_id = 0
            self._chd_id = 0
            self._pc_id = 0

            plt.tight_layout(pad=2.0) # Adjust layout
            self.fig.show()
            self.fig.canvas.flush_events() # Ensure the window appears
            logging.info("Plotter initialized successfully.")

        except Exception as e:
            logging.exception("Error initializing Plotter:")
            raise # Re-raise the exception after logging

    def _get_screen_resolution(self) -> Tuple[int, int]:
        """Tries to get the primary monitor resolution (platform dependent)."""
        try:
            # Tkinter method (often available)
            import tkinter
            root = tkinter.Tk()
            root.withdraw() # Hide the root window
            width = root.winfo_screenwidth()
            height = root.winfo_screenheight()
            root.destroy()
            return width, height
        except Exception:
            logging.warning("Could not get screen resolution via tkinter. Using default.")
            return 1200, 800 # Default fallback

    def _update_legend(self, ax: plt.Axes, legend_ref: Optional[Legend], plots: list, title: str, position_spec) -> Legend:
        """Helper to remove the old legend and create a new one."""
        # Remove previous legend if it exists and is still part of the figure
        if legend_ref is not None and legend_ref.figure is not None:
            try:
                legend_ref.remove()
            except Exception as e:
                 logging.warning(f"Could not remove previous legend for {title}: {e}")

        # Create a new legend using handles and labels from the plots list
        handles = [p for p in plots]
        labels = [p.get_label() for p in plots]

        if not handles: # No plots yet
             return None

        # Place legend in its dedicated subplot area
        # Need to create a dummy axis in the legend position if using fig.legend
        # Easier: Use ax.legend and place it outside
        # new_legend = ax.legend(handles, labels, title=title, loc='center left', bbox_to_anchor=(1.05, 0.5))

        # Alternative: Place legend in the specified GridSpec location
        legend_ax = self.fig.add_subplot(position_spec)
        legend_ax.axis('off') # Hide axes of the legend subplot
        new_legend = legend_ax.legend(handles, labels, title=title, loc='center')


        return new_legend

    def update_delta_heights_distribution(self, r_values: Union[List[float], np.ndarray], h_values: Union[List[float], np.ndarray]):
        """Updates the Delta Heights Distribution plot."""
        if len(r_values) != len(h_values):
            logging.warning("Mismatched R and H lengths for delta heights plot. Skipping.")
            return
        if len(r_values) == 0:
            logging.warning("Empty data for delta heights plot. Skipping.")
            return

        self._hd_id += 1
        current_label = f"Layer {self._hd_id-1} to {self._hd_id}" # Match Julia label

        # Plot new data
        scatter_plot = self.ax_hd.scatter(r_values, h_values, s=10, label=current_label) # s is markersize
        self._hd_plots.append(scatter_plot)

        # Update legend
        self._hd_legend = self._update_legend(self.ax_hd, self._hd_legend, self._hd_plots, "ΔLayers", self.ax_hd_legend_pos)

        # Adjust limits and redraw
        self.ax_hd.relim()
        self.ax_hd.autoscale_view()
        self.fig.canvas.draw_idle()
        self.fig.canvas.flush_events()

    def update_heights_distribution(self, r_values: Union[List[float], np.ndarray], h_values: Union[List[float], np.ndarray]):
        """Updates the Heights Distribution plot."""
        if len(r_values) != len(h_values):
            logging.warning("Mismatched R and H lengths for heights plot. Skipping.")
            return
        if len(r_values) == 0:
            logging.warning("Empty data for heights plot. Skipping.")
            return

        self._chd_id += 1
        current_label = f"Layer {self._chd_id}"

        # Plot new data
        scatter_plot = self.ax_chd.scatter(r_values, h_values, s=10, label=current_label)
        self._chd_plots.append(scatter_plot)

        # Update legend
        self._chd_legend = self._update_legend(self.ax_chd, self._chd_legend, self._chd_plots, "Layers", self.ax_chd_legend_pos)

        # Adjust limits and redraw
        self.ax_chd.relim()
        self.ax_chd.autoscale_view()
        self.fig.canvas.draw_idle()
        self.fig.canvas.flush_events()

    def update_cloud_points(self, points: List[Point], is_plane: bool = False):
        """Updates the 3D Point Cloud plot."""
        if not points:
            logging.warning("Empty points list for point cloud plot. Skipping.")
            return

        self._pc_id += 1
        if is_plane:
             current_label = f"Plane Points {self._pc_id}"
             color = 'red'
             marker_size = 5 # Make plane points more visible
        else:
             current_label = f"Layer Points {self._pc_id}"
             color = None # Use default color cycle
             marker_size = 1

        # Extract coordinates
        x = np.array([p.x for p in points])
        y = np.array([p.y for p in points])
        z = np.array([p.z for p in points])

        # Plot new data
        # Note: For large clouds, consider downsampling or using faster plotting methods
        scatter_plot = self.ax_pc.scatter(x, y, z, s=marker_size, label=current_label, c=color, depthshade=True)
        self._pc_plots.append(scatter_plot)

        # Update legend
        self._pc_legend = self._update_legend(self.ax_pc, self._pc_legend, self._pc_plots, "Point Sets", self.ax_pc_legend_pos)

        # Adjust limits and redraw
        # Autoscale for 3D can be tricky; manual adjustment might be needed sometimes
        # self.ax_pc.relim() # May not work well for 3D
        # self.ax_pc.autoscale_view()
        # A simple way to rescale (might not preserve aspect ratio well):
        all_x = np.concatenate([p.get_offsets()[:, 0] for p in self._pc_plots if hasattr(p, 'get_offsets')])
        all_y = np.concatenate([p.get_offsets()[:, 1] for p in self._pc_plots if hasattr(p, 'get_offsets')])
        # For 3D, need to access the z data differently
        # This part needs refinement for robust 3D autoscaling.
        # Let's rely on initial autoscaling and manual zoom/pan for now.

        self.fig.canvas.draw_idle()
        self.fig.canvas.flush_events()

    def update_plane_points(self, points: List[Point]):
         """Convenience method to plot points specifically representing the plane."""
         self.update_cloud_points(points, is_plane=True)

    def close(self):
        """Closes the plot window."""
        plt.close(self.fig)
        logging.info("Plotter window closed.")

