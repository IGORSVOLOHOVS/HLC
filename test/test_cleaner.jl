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


dest_dir = "C:\\Users\\Admin\\Projects\\Additive-Lab-Software\\CourceProject3\\HLC\\test\\2025-03-20_14-52-45"


# Example usage (ensure this path exists when you run it)



clean_folder(dest_dir)
# copy_files_std(source_dir, dest_dir, max_index)