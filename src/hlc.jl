# hlc.jl
module HLC

# ----------------------------------------- Dependencies -----------------------------------------------------
using NativeFileDialog 
using Dates

include("calc/calc.jl")
include("plot/plot.jl")

# ----------------------------------------- Structures / Functions -------------------------------------------
"""
    monitor_path(path::String)

Placeholder function for monitoring a directory.
"""
function monitor_path(path::String, interval::Int64)
    println("Starting path monitoring: ", path)
    # Add your actual monitoring logic here
    # For example, starting FileWatching.watch_folder or another mechanism
    # laser_rows = Calc.csv_to_data_array(Calc.LaserRow, joinpath(path, "LaserCoordinate1.csv"))
    # robot_rows = Calc.csv_to_data_array(Calc.RobotRow, joinpath(path, "RobotCoordinate1.csv"))
    # cal = Calc.get_calibration()

    # point_cloud = Calc.calculate_points(robot_rows, laser_rows, cal)

    # Plot.update_cloud_points(point_cloud)
    
    # clean layer_path if it exists
    if isdir(joinpath(path, "layers"))
        rm(joinpath(path, "layers"), recursive=true)
    end
    if isdir(joinpath(path, "current_height"))
        rm(joinpath(path, "current_height"), recursive=true)
    end

    mkdir(joinpath(path, "layers"))
    mkdir(joinpath(path, "current_height"))

    monitored_dir = abspath(path)
    println("="^40)
    @info "Starting directory monitoring: $monitored_dir"
    println("="^40)

    last_confirmed_index::Int = 0 # The last index for which BOTH files were found

    try
         if isdir(monitored_dir)
             current_index = 1
             while true
                 robot_file = "RobotCoordinate$(current_index).csv"
                 laser_file = "LaserCoordinate$(current_index).csv"
                 robot_path = joinpath(monitored_dir, robot_file)
                 laser_path = joinpath(monitored_dir, laser_file)

                 if isfile(robot_path) && isfile(laser_path)
                     # Both files for this index exist
                     last_confirmed_index = current_index
                     @debug "Found existing confirmed index: $last_confirmed_index"
                     current_index += 1 # Check the next one
                 else
                     # The pair is incomplete or missing, stop checking
                     @info "Initial confirmed index: $last_confirmed_index. Wait scans files..."
                     break
                 end
             end
         else
             @warn "Target directory '$monitored_dir' not found during initial check."
             # last_confirmed_index remains 0
         end
    catch e
        @error "Error during initial index check in '$monitored_dir': " exception=(e, catch_backtrace())
        # Can decide to exit or continue with last_confirmed_index = 0
    end


    # --- Main monitoring loop ---
    try
        conf = Calc.load_config()
        calibration = Calc.RobotRow(
            "", Dates.unix2datetime(0), # empty lines
            conf.calibration.x, conf.calibration.y, conf.calibration.z, # x, y, z
            conf.calibration.a, conf.calibration.b, conf.calibration.c, # rx, ry, rz - same parametrs as a, b, c
        )
        while true
            # Check directory availability (in case it's deleted during operation)
            if !isdir(monitored_dir)
                @error "Directory '$monitored_dir' is no longer available! Stopping monitoring."
                break # Break the while loop
            end

            next_index_to_check = last_confirmed_index + 1
            @debug "Checking index: $next_index_to_check"

            robot_file_next = "RobotCoordinate$(next_index_to_check).csv"
            laser_file_next = "LaserCoordinate$(next_index_to_check).csv"

            robot_path_next = joinpath(monitored_dir, robot_file_next)
            laser_path_next = joinpath(monitored_dir, laser_file_next)

            # Check for the existence of BOTH files for the next index
            if isfile(robot_path_next) && isfile(laser_path_next)
                # --- New pair found ---
                @info "Detected complete pair for index: $next_index_to_check"

                # Report readiness of the PREVIOUS index (if not zero)
                if last_confirmed_index > 0
                    prev_index = last_confirmed_index
                    robot_file_prev = joinpath(monitored_dir, "RobotCoordinate$(prev_index).csv")
                    laser_file_prev = joinpath(monitored_dir, "LaserCoordinate$(prev_index).csv")

                    # read laser and robot points
                    robot_rows = Calc.csv_to_data_array(Calc.RobotRow, robot_file_prev)
                    laser_rows = Calc.csv_to_data_array(Calc.LaserRow, laser_file_prev)

                    # calculate points
                    cloud_points = Calc.calculate_points(robot_rows, laser_rows, calibration)

                    # firts scan - plane
                    if prev_index == 1
                        # calculate plain and save to config.yaml
                        plane_params = Calc.calculate_plane(cloud_points)

                        # update plots (with plane)
                        Plot.update_plane(cloud_points)
                    else
                        # find max approximated 
                        laser_rows_mins = Calc.calculate_laser_mins(laser_rows)

                        # calculate points and filter it by plane
                        cloud_points_mins = Calc.calculate_points(robot_rows, laser_rows_mins, calibration)
                        cloud_points_mins = Calc.filter_by_plane(cloud_points_mins)
                        
                        # interpolate it, create grid
                        if prev_index == 2
                            Calc.calculate_grid_range(cloud_points_mins)
                        end
                        heights_on_grid::Vector{Calc.Height} = Calc.calculate_points_on_grid(cloud_points_mins, conf.plane.scans)

                        # create delta heights description and current heights description 
                        x_delta, y_delta, z_delta, r_delta, h_delta = Calc.calculate_delta_heigts_destribution(heights_on_grid, monitored_dir)
                        x, y, z, r, h = Calc.calculate_heigts_destribution(heights_on_grid, monitored_dir)

                        # plot it
                        Plot.update_delta_heigts_destribution(r_delta, h_delta)
                        Plot.update_heigts_destribution(r, h)
                        Plot.update_cloud_points(cloud_points)
                    end
                
                elseif next_index_to_check == 1 # Special case for the first found index
                    @info "This is the first detected pair (index 1). No previous files."
                end

                # Update state
                last_confirmed_index = next_index_to_check

                # DO NOT wait for the interval, immediately check the next index,
                # as multiple pairs might have appeared simultaneously
                @info "Scan with index: $next_index_to_check was processed!"
                continue

            else
                # Pair for next_index_to_check is not ready yet (or doesn't exist)
                @debug "Pair for index $next_index_to_check not found. Waiting..."
                # Wait before the next check
                sleep(interval)
            end

        end # while true

    catch e
        # Handle interruption (Ctrl+C)
        if e isa InterruptException
            println("\n\n[", now(), "] Interrupt signal received (Ctrl+C). Shutting down...")
        else
            @error "Unexpected error in monitoring loop:" exception=(e, catch_backtrace())
            rethrow(e) # Rethrow the error for diagnostics
        end
    finally
        println("[", now(), "] Monitoring stopped.")
    end
end



"""
    run()

Starts the HLC process. Opens a graphical dialog for the user
to select a folder and then initiates monitoring of that folder.
"""
function run()
    println("Waiting for user to select a folder via GUI...")

    # Open the native folder selection dialog
    path = pick_folder() # Returns the selected path or "" if the user cancelled

    # Check if a path was selected (user didn't press "Cancel")
    if isempty(path)
        println("Folder selection cancelled by user.")
        return # Exit if no folder was selected
    end

    # Optionally: Check if the selected path is actually a folder
    if !isdir(path)
        # Ideally, show a graphical error message here too,
        # but for simplicity, keep console output for now.
        @error "Selected path is not a folder or is inaccessible: $path"
        # Could use `run(\`cmd /c msg * "Error text"\`)` on Windows
        # or `run(\`zenity --error --text="Error text"\`)` on Linux (if zenity is installed)
        # for a simple graphical notification.
        return # Exit if it's not a folder
    end

    println("Folder selected: ", path)
    println("Starting monitoring...")
    # monitor_path("C:\\Users\\Admin\\Projects\\Additive-Lab-Software\\CourceProject3\\HLC\\test\\2025-03-20_14-52-45", 2) # Call the monitoring function with the selected path
    monitor_path(path, 2)
end

end # end module HLC
