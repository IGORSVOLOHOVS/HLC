# calc/points.jl
using Dates
using LinearAlgebra
using CSV
using DataFrames # Required by CSV.jl for reading/writing
using YAML       # Added for YAML parsing
using Base       # Ensure using Base: for basename

# ------------------------------------------------------ Structs -----------------------------------------------------------

"""
    LaserRow

Represents a single row of data from a laser scanner measurement, potentially containing multiple points.
Assumes data comes from a CSV row like: TimeReceived,"X values","Z values","Intensity values"
where values within quotes are space-separated.

# Fields
- `csv::String`: Source identifier (e.g., filename or description). *Note: Not automatically populated during CSV read.*
- `tm::DateTime`: Timestamp of the measurement (from TimeReceived column).
- `x_array::Vector{Float64}`: Array of X-coordinates (space-separated in CSV).
- `z_array::Vector{Float64}`: Array of Z-coordinates (space-separated in CSV).
- `intensity_array::Vector{Int32}`: Array of intensity values (space-separated integers in CSV).
"""
mutable struct LaserRow
    csv::String
    tm::DateTime
    x_array::Vector{Float64}
    z_array::Vector{Float64}
    intensity_array::Vector{Int32} # Changed to Int32

    # Default constructor for empty initialization - FIXED
    LaserRow() = new("", Dates.unix2datetime(0), Float64[], Float64[], Int32[])
    # Constructor with values
    LaserRow(csv, tm, x, z, intensity) = new(csv, tm, x, z, intensity)
end

"""
    RobotRow

Represents the pose (position and orientation) of a robot at a specific time.
Assumes data comes from a CSV row like: TimeReceived,X,Y,Z,RX,RY,RZ
Also used to represent calibration data loaded from YAML.

# Fields
- `csv::String`: Source identifier (e.g., filename or description). *Note: Not automatically populated during CSV read.*
- `tm::DateTime`: Timestamp of the pose measurement (from TimeReceived column). Defaults to epoch for calibration.
- `x::Float64`: X-coordinate of the robot's position or calibration offset.
- `y::Float64`: Y-coordinate of the robot's position or calibration offset.
- `z::Float64`: Z-coordinate of the robot's position or calibration offset.
- `rx::Float64`: Rotation around the X-axis (roll) in degrees (maps to 'a' in YAML).
- `ry::Float64`: Rotation around the Y-axis (pitch) in degrees (maps to 'b' in YAML).
- `rz::Float64`: Rotation around the Z-axis (yaw) in degrees (maps to 'c' in YAML).
"""
mutable struct RobotRow
    csv::String
    tm::DateTime
    x::Float64
    y::Float64
    z::Float64
    rx::Float64 # Corresponds to 'a' in YAML calibration
    ry::Float64 # Corresponds to 'b' in YAML calibration
    rz::Float64 # Corresponds to 'c' in YAML calibration

    # Default constructor - FIXED
    RobotRow() = new("", Dates.unix2datetime(0), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    # Constructor with values
    RobotRow(csv, tm, x, y, z, rx, ry, rz) = new(csv, tm, x, y, z, rx, ry, rz)
end

"""
    Point

Represents a single point in 3D space, typically calculated in the world frame.

# Fields
- `csv::String`: Source identifier (inherited from the LaserRow).
- `tm::DateTime`: Timestamp associated with the point's calculation.
- `x::Float64`: X-coordinate of the point.
- `y::Float64`: Y-coordinate of the point.
- `z::Float64`: Z-coordinate of the point.
"""
mutable struct Point
    csv::String
    tm::DateTime
    x::Float64
    y::Float64
    z::Float64

     # Default constructor - FIXED
     Point() = new("", Dates.unix2datetime(0), 0.0, 0.0, 0.0)
     # Constructor with values
     Point(csv, tm, x, y, z) = new(csv, tm, x, y, z)
end

# ------------------------------------------------------ Helper Functions ----------------------------------------------------

# Define common date formats - Primary format used by CSV.read and data_to_csv
const DATE_FORMAT_STR = "yyyy-mm-ddTHH:MM:SS.s"
# Secondary format to try if parsing fails (handles space separator)
const DATE_FORMAT_STR_SPACE = "yyyy-mm-dd HH:MM:SS.s"

# Create DateFormat objects for parsing performance
const DATE_FORMAT_T = Dates.DateFormat(DATE_FORMAT_STR)
const DATE_FORMAT_SPACE = Dates.DateFormat(DATE_FORMAT_STR_SPACE)

"""
    _parse_delimited_array(s::AbstractString, T::Type; delim=' ')

Internal helper function to parse a delimited string into a Vector{T}.
Returns an empty vector if parsing fails or the string is empty.

# Arguments
- `s::AbstractString`: The string to parse (e.g., "1.0 2.5 3.0").
- `T::Type`: The numeric type to parse into (e.g., Float64, Int32).
- `delim::Char`: The delimiter character (default is space).

# Returns
- `Vector{T}`: The parsed vector of numbers.
"""
function _parse_delimited_array(s::AbstractString, T::Type; delim=' ')::Vector{T}
    s_stripped = strip(s) # Remove leading/trailing whitespace
    if isempty(s_stripped)
        return T[]
    end
    parts = split(s_stripped, delim; keepempty=false) # Don't keep empty strings from multiple spaces
    result = Vector{T}(undef, length(parts))
    try
        for (i, part) in enumerate(parts)
            result[i] = parse(T, part)
        end
        return result
    catch e
        @warn "Failed to parse array string '$s' into Vector{$T} with delimiter '$delim': $e"
        return T[] # Return empty on error
    end
end

"""
    _format_delimited_array(arr::Vector{<:Real}; delim=' ')

Internal helper function to format a vector of numbers into a delimited string.

# Arguments
- `arr::Vector{<:Real}`: The vector of numbers to format.
- `delim::Char`: The delimiter character (default is space).

# Returns
- `String`: The formatted string (e.g., "1.0 2.5 3.0").
"""
function _format_delimited_array(arr::Vector{<:Real}; delim=' ')::String
    return join(string.(arr), delim)
end

# ------------------------------------------------------ YAML Handling (New) -------------------------------------------------

"""
    get_calibration(filename::String="config.yaml") -> Union{RobotRow, Nothing}

Loads calibration data (x, y, z, a, b, c) from the 'calibration' section
of a YAML file and returns it as a `RobotRow` object.
Returns `nothing` if the file is not found, the section is missing,
keys are missing, or a parsing error occurs.

Note: 'a', 'b', 'c' from YAML are mapped to 'rx', 'ry', 'rz' in RobotRow.
The 'tm' field of the returned RobotRow defaults to the Unix epoch.
The 'csv' field is set to the filename.
"""
function get_calibration(filename::String="config.yaml")::Union{RobotRow, Nothing}
    try
        if !isfile(filename)
            @error "Configuration file not found: $filename" # Translated from: Файл конфигурации не найден
            return nothing
        end

        raw_config = YAML.load_file(filename)

        # Check for 'calibration' section
        if !haskey(raw_config, "calibration")
             @error "Missing required section 'calibration' in file $filename" # Translated from: Отсутствует обязательная секция 'calibration'
             return nothing
        end
        cal_data = raw_config["calibration"]

        # Check for required keys within 'calibration'
        req_keys = ["x", "y", "z", "a", "b", "c"]
        for key in req_keys
            if !haskey(cal_data, key)
                @error "Missing required key '$key' in section 'calibration' of file $filename" # Translated from: Отсутствует обязательный ключ
                return nothing
            end
        end

        # Create and populate RobotRow for calibration
        # Map YAML a, b, c to RobotRow rx, ry, rz
        calibration_row = RobotRow(
            "",                       # Source identifier
            Dates.unix2datetime(0),   # Default timestamp (epoch)
            Float64(cal_data["x"]),   # Convert just in case YAML parsed as Int
            Float64(cal_data["y"]),
            Float64(cal_data["z"]),
            Float64(cal_data["a"]),   # rx (roll)
            Float64(cal_data["b"]),   # ry (pitch)
            Float64(cal_data["c"])    # rz (yaw)
        )
        calibration_row.csv = filename # Set source identifier to the filename

        return calibration_row

    catch e
        @error "Error loading or parsing calibration from file '$filename':" exception=(e, catch_backtrace()) # Translated from: Ошибка при загрузке или парсинге калибровки из файла
        return nothing # Return nothing on any error
    end
end


# ------------------------------------------------------ CSV Handling --------------------------------------------------------

# --- LaserRow CSV ---

"""
    csv_to_data!(row::LaserRow, csv_row::DataFrameRow)

Populates a `LaserRow` struct from a `DataFrameRow`.
Assumes columns: :TimeReceived, :X, :Z, :Intensity
Where :X, :Z, :Intensity contain space-delimited strings.
Handles cases where :TimeReceived might be DateTime or String due to inconsistent CSV formatting.
*Note: Does not populate the `row.csv` field.*

# Arguments
- `row::LaserRow`: The `LaserRow` struct to populate (mutated).
- `csv_row::DataFrameRow`: The row from the DataFrame.

# Returns
- `LaserRow`: The populated `row` object.
"""
function csv_to_data!(row::LaserRow, csv_row::DataFrameRow)::LaserRow
    try
        # --- Handle TimeReceived ---
        time_val = csv_row.TimeReceived
        if isa(time_val, DateTime)
            # Already parsed correctly by CSV.read
            row.tm = time_val
        elseif isa(time_val, AbstractString)
            # CSV.read failed to parse, try parsing manually with known formats
            time_str = string(time_val) # Ensure it's a standard String
            parsed = false
            try
                # Try parsing with the primary format ('T' separator)
                row.tm = DateTime(time_str, DATE_FORMAT_T)
                parsed = true
            catch e1
                try
                    # Try parsing with the secondary format (' ' separator)
                    row.tm = DateTime(time_str, DATE_FORMAT_SPACE)
                    parsed = true
                catch e2
                    @warn "Failed to parse TimeReceived string '$time_str' with both formats: $e1 and $e2. Row data: $csv_row"
                    row.tm = Dates.unix2datetime(0) # Assign default on failure
                end
            end
        else
            # Unexpected type
             @warn "Unexpected type for TimeReceived: $(typeof(time_val)). Row data: $csv_row"
             row.tm = Dates.unix2datetime(0) # Assign default
        end

        # --- Handle other fields ---
        # Parse space-delimited strings into arrays
        # Convert potential non-string types (like Missing) to string before parsing arrays
        row.x_array = _parse_delimited_array(string(csv_row.X), Float64; delim=' ')
        row.z_array = _parse_delimited_array(string(csv_row.Z), Float64; delim=' ')
        row.intensity_array = _parse_delimited_array(string(csv_row.Intensity), Int32; delim=' ') # Use Int32

    catch e
        @error "Error processing LaserRow from CSV: $e. Row data: $csv_row"
        # Print stacktrace for more debugging info
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        # Reset row to default if parsing fails badly
        row.tm = Dates.unix2datetime(0)
        row.x_array = Float64[]
        row.z_array = Float64[]
        row.intensity_array = Int32[]
    end
    return row
end

"""
    data_to_csv(row::LaserRow)::NamedTuple

Converts a `LaserRow` struct into a `NamedTuple` suitable for writing to a CSV.
Outputs columns: TimeReceived, X, Z, Intensity with space-delimited values.
Uses the primary date format ('T' separator) for output consistency.
*Note: Does not include the `csv` field in the output.*

# Arguments
- `row::LaserRow`: The struct to convert.

# Returns
- `NamedTuple`: Data ready for CSV writing.
"""
function data_to_csv(row::LaserRow)::NamedTuple
    return (
        # Format output using the primary 'T' separator format string
        TimeReceived=Dates.format(row.tm, DATE_FORMAT_T),
        X=_format_delimited_array(row.x_array; delim=' '),
        Z=_format_delimited_array(row.z_array; delim=' '),
        Intensity=_format_delimited_array(row.intensity_array; delim=' ') # Format Int32 array
    )
end

# --- RobotRow CSV ---

"""
    csv_to_data!(row::RobotRow, csv_row::DataFrameRow)

Populates a `RobotRow` struct from a `DataFrameRow`.
Assumes columns: :TimeReceived, :X, :Y, :Z, :RX, :RY, :RZ
Handles cases where :TimeReceived might be DateTime or String due to inconsistent CSV formatting.
*Note: Does not populate the `row.csv` field.*

# Arguments
- `row::RobotRow`: The `RobotRow` struct to populate (mutated).
- `csv_row::DataFrameRow`: The row from the DataFrame.

# Returns
- `RobotRow`: The populated `row` object.
"""
function csv_to_data!(row::RobotRow, csv_row::DataFrameRow)::RobotRow
     try
        # --- Handle TimeReceived ---
        time_val = csv_row.TimeReceived
        if isa(time_val, DateTime)
            # Already parsed correctly by CSV.read
            row.tm = time_val
        elseif isa(time_val, AbstractString)
            # CSV.read failed to parse, try parsing manually with known formats
            time_str = string(time_val) # Ensure it's a standard String
            parsed = false
            try
                # Try parsing with the primary format ('T' separator)
                row.tm = DateTime(time_str, DATE_FORMAT_T)
                parsed = true
            catch e1
                try
                    # Try parsing with the secondary format (' ' separator)
                    row.tm = DateTime(time_str, DATE_FORMAT_SPACE)
                    parsed = true
                catch e2
                    @warn "Failed to parse TimeReceived string '$time_str' with both formats: $e1 and $e2. Row data: $csv_row"
                    row.tm = Dates.unix2datetime(0) # Assign default on failure
                end
            end
        else
            # Unexpected type
             @warn "Unexpected type for TimeReceived: $(typeof(time_val)). Row data: $csv_row"
             row.tm = Dates.unix2datetime(0) # Assign default
        end

        # --- Handle other fields ---
        # Parse numeric values
        # Handle potential Missing values by coalescing or checking ismissing
        # Use parse(Float64, string(value)) for robustness if CSV reads numbers as strings
        # Use coalesce to provide "NaN" string if value is missing, then parse
        row.x = parse(Float64, string(coalesce(csv_row.X, "NaN")))
        row.y = parse(Float64, string(coalesce(csv_row.Y, "NaN")))
        row.z = parse(Float64, string(coalesce(csv_row.Z, "NaN")))
        row.rx = parse(Float64, string(coalesce(csv_row.RX, "NaN")))
        row.ry = parse(Float64, string(coalesce(csv_row.RY, "NaN")))
        row.rz = parse(Float64, string(coalesce(csv_row.RZ, "NaN")))
     catch e
         @error "Error processing RobotRow from CSV: $e. Row data: $csv_row"
         # Print stacktrace for more debugging info
         showerror(stderr, e, catch_backtrace())
         println(stderr)
         # Reset row to default if parsing fails badly
         row.tm = Dates.unix2datetime(0)
         row.x = row.y = row.z = row.rx = row.ry = row.rz = NaN # Use NaN for invalid numeric data
     end
     return row
end

"""
    data_to_csv(row::RobotRow)::NamedTuple

Converts a `RobotRow` struct into a `NamedTuple` suitable for writing to a CSV.
Outputs columns: TimeReceived, X, Y, Z, RX, RY, RZ
Uses the primary date format ('T' separator) for output consistency.
*Note: Does not include the `csv` field in the output.*

# Arguments
- `row::RobotRow`: The struct to convert.

# Returns
- `NamedTuple`: Data ready for CSV writing.
"""
function data_to_csv(row::RobotRow)::NamedTuple
    return (
        # Format output using the primary 'T' separator format string
        TimeReceived=Dates.format(row.tm, DATE_FORMAT_T),
        X=row.x,
        Y=row.y,
        Z=row.z,
        RX=row.rx,
        RY=row.ry,
        RZ=row.rz
    )
end

# --- Generic CSV Reading ---

"""
    csv_to_data_array(::Type{T}, file::String)::Vector{T} where T <: Union{RobotRow, LaserRow}

Reads a CSV file and converts its rows into a vector of the specified struct type `T`
(either `RobotRow` or `LaserRow`). It dispatches to the correct `csv_to_data!` method
based on the provided type `T`.
*Note: The `csv` field in the returned structs is not populated by this function.*

# Arguments
- `::Type{T}`: The type of struct to create (e.g., `RobotRow` or `LaserRow`).
- `file::String`: Path to the CSV file.

# Returns
- `Vector{T}`: A vector containing the parsed data. Returns empty vector on error.

# Example Usage
```julia
robot_data = csv_to_data_array(RobotRow, "robot_poses.csv")
laser_data = csv_to_data_array(LaserRow, "laser_scans.csv")
```
"""
function csv_to_data_array(::Type{T}, file::String)::Vector{T} where T <: Union{RobotRow, LaserRow}
    result = T[] # Initialize vector of the specified type T
    local df # Ensure df is in local scope for the catch block if needed

    try
        # Read the CSV into a DataFrame.
        # Provide the primary dateformat. CSV.jl will attempt to parse using this format.
        # If parsing fails for some rows due to format mismatch, they might remain as strings.
        # Consider specifying `stringtype=String` if `InlineStrings` causes issues.
        df = CSV.read(file, DataFrame; dateformat=DATE_FORMAT_STR) # Keep primary format here

        # Iterate over DataFrame rows and convert each to the specified type T
        for csv_row in eachrow(df)
            row_instance = T() # Create a new instance of type T
            # csv_to_data! will now handle both DateTime and String types for TimeReceived
            # and attempt to parse numeric fields robustly.
            push!(result, csv_to_data!(row_instance, csv_row))
        end
    catch e
        # Use correct type T in error message
        @error "Failed to read or process $(T) CSV '$file': $e"
        # Print stacktrace for more debugging info
        showerror(stderr, e, catch_backtrace())
        println(stderr) # Add a newline after stacktrace
        # Return empty vector on error
        return T[]
    end
    return result
end


# ------------------------------------------------------ Transformation Logic ------------------------------------------------
# (No changes needed in this section, assuming it's correct)

"""
    euler_to_transform_y(data::RobotRow)::Matrix{Float64}

Converts Euler angles (ZYX convention, degrees) and translation from a `RobotRow`
into a 4x4 homogeneous transformation matrix.

# Arguments
- `data::RobotRow`: Robot pose data containing translation (x, y, z) and rotation (rx, ry, rz in degrees).

# Returns
- `Matrix{Float64}`: A 4x4 transformation matrix representing the robot's pose.
"""
function euler_to_transform_y(data::RobotRow)::Matrix{Float64}
    # Convert degrees to radians
    r_x = deg2rad(data.rx) # Roll
    r_y = deg2rad(data.ry) # Pitch
    r_z = deg2rad(data.rz) # Yaw

    # Calculate sines and cosines
    cos_rx, sin_rx = cos(r_x), sin(r_x)
    cos_ry, sin_ry = cos(r_y), sin(r_y)
    cos_rz, sin_rz = cos(r_z), sin(r_z)

    # Rotation matrix (ZYX order: Yaw, Pitch, Roll)
    # R = Rz(rz) * Ry(ry) * Rx(rx)
    result_matrix = zeros(Float64, 4, 4)

    # Column 1
    result_matrix[1, 1] = cos_ry * cos_rz
    result_matrix[2, 1] = cos_ry * sin_rz
    result_matrix[3, 1] = -sin_ry

    # Column 2
    result_matrix[1, 2] = sin_rx * sin_ry * cos_rz - cos_rx * sin_rz
    result_matrix[2, 2] = sin_rx * sin_ry * sin_rz + cos_rx * cos_rz
    result_matrix[3, 2] = sin_rx * cos_ry

    # Column 3
    result_matrix[1, 3] = cos_rx * sin_ry * cos_rz + sin_rx * sin_rz
    result_matrix[2, 3] = cos_rx * sin_ry * sin_rz - sin_rx * cos_rz
    result_matrix[3, 3] = cos_rx * cos_ry

    # Homogeneous coordinate
    result_matrix[4, 4] = 1.0

    # Fill the translation part (Column 4)
    result_matrix[1, 4] = data.x
    result_matrix[2, 4] = data.y
    result_matrix[3, 4] = data.z

    return result_matrix
end

"""
    transform_to_euler_y(input_matrix::Matrix{Float64})::RobotRow

Extracts Euler angles (ZYX convention, degrees) and translation from a 4x4
homogeneous transformation matrix and returns them in a `RobotRow`.

Handles gimbal lock singularity for pitch near +/- 90 degrees.

# Arguments
- `input_matrix::Matrix{Float64}`: A 4x4 transformation matrix.

# Returns
- `RobotRow`: A struct containing the extracted pose. `csv` and `tm` fields will be empty/default.
"""
function transform_to_euler_y(input_matrix::Matrix{Float64})::RobotRow
    # Initialize with default values
    result = RobotRow() # Uses the default constructor

    # Extract translation
    result.x = input_matrix[1, 4]
    result.y = input_matrix[2, 4]
    result.z = input_matrix[3, 4]

    # Extract Euler angles (ZYX convention)
    # Pitch (ry)
    sin_pitch = -input_matrix[3, 1]
    # Clamp sin_pitch to avoid domain errors in asin due to potential floating point inaccuracies
    if sin_pitch > 1.0
        sin_pitch = 1.0
    elseif sin_pitch < -1.0
        sin_pitch = -1.0
    end

    # Use a slightly more robust check for gimbal lock
    if abs(abs(sin_pitch) - 1.0) < 1e-9 # Check if sin_pitch is very close to +1 or -1
        # Gimbal lock case
        result.ry = rad2deg(copysign(pi / 2.0, sin_pitch)) # +/- 90 degrees

        # Set roll (rx) to 0 and calculate yaw (rz) from atan2(R12, R22) - common convention
        result.rz = rad2deg(atan(input_matrix[1, 2], input_matrix[2, 2])) # Yaw
        result.rx = 0.0 # Roll is arbitrary, set to 0
    else
        # Normal case
        result.ry = rad2deg(asin(sin_pitch)) # Pitch

        # Roll (rx) from atan2(R32, R33)
        result.rx = rad2deg(atan(input_matrix[3, 2], input_matrix[3, 3]))

        # Yaw (rz) from atan2(R21, R11)
        result.rz = rad2deg(atan(input_matrix[2, 1], input_matrix[1, 1]))
    end

    # Note: csv and tm fields remain at their default values (using Dates.unix2datetime(0) now)
    # as they cannot be determined solely from the matrix.
    return result
end


"""
    calculate_points_row(robot_row::RobotRow, laser_row::LaserRow, calibration::RobotRow)::Vector{Point}

Calculates the world coordinates of laser points for a single timestamp,
given the robot pose, laser data, and sensor calibration (offset).

# Arguments
- `robot_row::RobotRow`: The robot's pose at the time of the laser scan.
- `laser_row::LaserRow`: The laser scan data (points relative to the sensor).
- `calibration::RobotRow`: The pose of the laser sensor relative to the robot's base frame.

# Returns
- `Vector{Point}`: A vector of calculated points in the world frame.
"""
function calculate_points_row(robot_row::RobotRow, laser_row::LaserRow, calibration::RobotRow)::Vector{Point}
    # Calculate transformation from robot base to world
    T_world_robot = euler_to_transform_y(robot_row)
    # Calculate transformation from laser sensor to robot base
    T_robot_laser = euler_to_transform_y(calibration)

    # Combined transformation from laser sensor frame to world frame
    T_world_laser = T_world_robot * T_robot_laser

    num_points = min(length(laser_row.x_array), length(laser_row.z_array))
    # Intensity array length isn't used for coordinate calculation, but should ideally match
    if num_points != length(laser_row.intensity_array)
        @warn "Mismatch between coordinate array lengths ($(num_points)) and intensity array length ($(length(laser_row.intensity_array))) for timestamp $(laser_row.tm) in source '$(laser_row.csv)'."
        # Decide how to handle: trim to shortest, error, or proceed?
        # Here, we proceed based on coordinate length.
        # Ensure num_points doesn't exceed intensity array length if intensities are crucial later
        num_points = min(num_points, length(laser_row.intensity_array))
    end

    points = Vector{Point}(undef, num_points) # Preallocate vector

    for j in 1:num_points
        # Create homogeneous coordinate vector for the laser point (assuming Y=0 in laser frame)
        # Point in laser frame: [lx, 0, lz, 1]
        p_laser = [laser_row.x_array[j], 0.0, laser_row.z_array[j], 1.0]

        # Transform point from laser frame to world frame
        p_world = T_world_laser * p_laser

        # Create Point struct with world coordinates and metadata
        # Extract world coordinates (first 3 elements of p_world)
        # Use timestamp and csv source from the *laser* data for the resulting point
        # The .csv field from laser_row will likely be "" now.
        points[j] = Point(laser_row.csv, laser_row.tm, p_world[1], p_world[2], p_world[3])
    end

    return points
end

"""
    calculate_points(robot_rows::Vector{RobotRow}, laser_rows::Vector{LaserRow}, calibration::RobotRow)::Vector{Point}

Calculates world coordinates for multiple laser scans based on corresponding robot poses.
Assumes a one-to-one correspondence between robot_rows and laser_rows based on index.
For time synchronization, a more robust approach (e.g., finding nearest neighbors in time) might be needed.

# Arguments
- `robot_rows::Vector{RobotRow}`: A vector of robot poses.
- `laser_rows::Vector{LaserRow}`: A vector of laser scans.
- `calibration::RobotRow`: The pose of the laser sensor relative to the robot's base frame.

# Returns
- `Vector{Point}`: A flattened vector containing all calculated points from all scans.
"""
function calculate_points(robot_rows::Vector{RobotRow}, laser_rows::Vector{LaserRow}, calibration::RobotRow)::Vector{Point}
    if length(robot_rows) != length(laser_rows)
        @warn "Robot rows and Laser rows have different lengths ($(length(robot_rows)) vs $(length(laser_rows))). Processing only up to the minimum length."
    end

    min_len = min(length(robot_rows), length(laser_rows))
    if min_len == 0
        return Point[] # Return empty if either input is empty
    end

    # Estimate total number of points for preallocation (can be rough)
    # Use average length of arrays in first few laser rows if available for better estimate
    estimated_points_per_row = isempty(laser_rows) || isempty(laser_rows[1].x_array) ? 50 : length(laser_rows[1].x_array) # Guess 50 if first is empty
    estimated_points = min_len * estimated_points_per_row

    points = Vector{Point}(undef, 0) # Initialize empty
    sizehint!(points, estimated_points) # Preallocate roughly

    for i in 1:min_len
        # Check if timestamps are reasonably close (optional, but good practice)
        # Ensure both tm fields are valid DateTimes before comparing
        if isa(robot_rows[i].tm, DateTime) && isa(laser_rows[i].tm, DateTime) &&
           robot_rows[i].tm != Dates.unix2datetime(0) && laser_rows[i].tm != Dates.unix2datetime(0) # Check not default
            time_diff = abs(robot_rows[i].tm - laser_rows[i].tm)
            if time_diff > Millisecond(500) # Example threshold: 500ms
                 @warn "Timestamp mismatch for index $i: Robot=$(robot_rows[i].tm) ('$(robot_rows[i].csv)'), Laser=$(laser_rows[i].tm) ('$(laser_rows[i].csv)'). Difference: $time_diff"
            end
        else
             @warn "Skipping timestamp comparison for index $i due to invalid or default DateTime."
        end


        # Check if laser row data is valid before processing
        if isempty(laser_rows[i].x_array) || isempty(laser_rows[i].z_array)
             @warn "Skipping index $i due to empty coordinate arrays in LaserRow: Timestamp=$(laser_rows[i].tm), Source='$(laser_rows[i].csv)'"
             continue # Skip to the next iteration
        end

        # Check if robot row data is valid (e.g., not default values from parsing error)
        if robot_rows[i].tm == Dates.unix2datetime(0) || isnan(robot_rows[i].x) # Check timestamp and a numeric field
             @warn "Skipping index $i due to invalid RobotRow data (default timestamp or NaN): $(robot_rows[i])"
             continue
        end


        points_row = calculate_points_row(robot_rows[i], laser_rows[i], calibration)
        append!(points, points_row) # Append the vector of points from the row
    end
    return points
end
