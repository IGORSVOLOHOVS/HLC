# Removed 'using FilePathsBase' as its '/' operator is causing persistent errors.
# We will use standard Julia functions like joinpath, cp, isfile, isdir.

"""
    copy_files_std(source_folder_str::String, dest_folder_str::String, n_max::Int)

Copies files named "LaserCoordinateN.csv" and "RobotCoordinateN.csv"
for N from 1 to n_max from the source folder to the destination folder,
prompting the user before each index N.

Uses standard Julia functions (joinpath, cp, isfile, isdir).
"""
function copy_files_std(source_folder_str::String, dest_folder_str::String, n_max::Int)
    # --- Input Validation (using standard string paths) ---
    if !isdir(source_folder_str)
        println("❌ Error: Source folder not found or is not a directory:")
        println("   '$source_folder_str'")
        return # Exit the function
    end
    if !isdir(dest_folder_str)
        println("❌ Error: Destination folder not found or is not a directory:")
        println("   '$dest_folder_str'")
        return # Exit the function
    end

    println("📁 Preparing to copy files with index 1 to $n_max")
    println("   Source:      $source_folder_str")
    println("   Destination: $dest_folder_str")
    println("-"^40) # Separator

    files_copied_count = 0
    files_not_found_count = 0

    for n in 1:n_max
        # Define filenames
        laser_filename = "LaserCoordinate$(n).csv"
        robot_filename = "RobotCoordinate$(n).csv"

        # --- Construct source and destination paths using standard joinpath ---
        src_laser = joinpath(source_folder_str, laser_filename)
        src_robot = joinpath(source_folder_str, robot_filename)
        dest_laser = joinpath(dest_folder_str, laser_filename)
        dest_robot = joinpath(dest_folder_str, robot_filename)

        # --- User Prompt ---
        println("\n➡️  Press ENTER to process files for index $n (or type 'skip'/'quit'):")
        # Add a print BEFORE readline
        println("DEBUG: Waiting for input for index $n...")
        input = lowercase(strip(readline())) # Read user input, normalize
        # Add a print AFTER readline
        println("DEBUG: Read input: '$input'")

        if input == "quit"
            println("🛑 Operation aborted by user.")
            break # Exit the loop
        elseif input == "skip"
            println("⏭️  Skipping index $n.")
            continue # Go to the next iteration of the loop
        else
            # Add explicit confirmation it's proceeding
            println("DEBUG: Proceeding because input was not 'quit' or 'skip'.")
        end

        println("   Processing index $n...")

        # --- Copy Laser File ---
        if isfile(src_laser)
            try
                # --- Use cp() for copying ---
                # force=true will overwrite the destination file if it already exists.
                # Remove force=true if you want an error if the destination file exists.
                cp(src_laser, dest_laser; force=true)
                println("   ✅ Copied: $laser_filename")
                files_copied_count += 1
            catch e
                # Print error message if copying fails
                println("   ❌ Error copying $src_laser to $dest_laser: $e")
            end
        else
            println("   ⚠️  Source file not found: $src_laser")
            files_not_found_count += 1
        end

        # --- Copy Robot File ---
        if isfile(src_robot)
            try
                # --- Use cp() for copying ---
                cp(src_robot, dest_robot; force=true)
                println("   ✅ Copied: $robot_filename")
                files_copied_count += 1
            catch e
                 # Print error message if copying fails
                println("   ❌ Error copying $src_robot to $dest_robot: $e")
            end
        else
            println("   ⚠️  Source file not found: $src_robot")
            files_not_found_count += 1
        end
    end

    println("-"^40) # Separator
    println("🏁 File copying process finished.")
    println("   Files successfully copied: $files_copied_count")
    println("   Source files not found: $files_not_found_count")
end
# Removed 'using FilePathsBase' for now, as joinpath is standard
# If you need FilePathsBase for other reasons, you can keep 'using FilePathsBase'
# and 'folder = Path(folder_path)' - joinpath works with Path objects too.

function clean_folder(folder_path::String)
    # Check if the folder actually exists before trying to read it
    # isdir works directly with the string path
    if !isdir(folder_path) 
        println("Error: Folder not found - ", folder_path)
        return
    end
    
    # readdir also works directly with the string path
    for file in readdir(folder_path) 
        # Construct the full path using the standard joinpath function
        # It works with the folder_path string and the file string
        full_path = joinpath(folder_path, file) 
        
        # Check if 'full_path' points to a file (and not a subdirectory)
        # isfile works directly with the string path
        if isfile(full_path) 
             if occursin(r"RobotCoordinate.*\.csv", file) || occursin(r"LaserCoordinate.*\.csv", file)
                try
                    # rm works directly with the string path
                    rm(full_path) 
                    println("Deleted: ", full_path) 
                catch e
                    println("Error deleting file ", full_path, ": ", e)
                end
            end
        end
    end
end


# Example usage (ensure this path exists when you run it)



# copy_files_std(source_dir, dest_dir, max_index)
# --- Example Usage ---
# Make sure these paths exist and are correct for your system!
# source_dir = "C:\\Users\\Admin\\Projects\\Additive-Lab-Software\\CourceProject3\\HLC\\test\\2025-03-20_14-52-45\\test1"
source_dir = "C:\\Users\\Admin\\Projects\\Additive-Lab-Software\\CourceProject3\\HLC\\test\\2025-04-30_13-45-49\\2025-04-30_15-09-02"
dest_dir = "C:\\Users\\Admin\\Projects\\Additive-Lab-Software\\CourceProject3\\HLC\\test\\2025-03-20_14-52-45"
max_index = 36 # Copy files with index 1, 2, 3, 4, 5

clean_folder(dest_dir)
copy_files_std(source_dir, dest_dir, max_index)