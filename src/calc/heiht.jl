# calc/heiht.jl
using Dates
using Statistics
using CSV
using DataFrames
using LinearAlgebra # For norm (distance between points)
using Optim
using Interpolations
using ScatteredInterpolation

"""
    Height

Structure to store a point with its calculated height relative to a plane.

# Fields
- `csv::String`: Identifier of the data source.
- `tm::DateTime`: Timestamp (may be irrelevant for pure height data).
- `x::Float64`: X coordinate of the grid point.
- `y::Float64`: Y coordinate of the grid point.
- `z::Float64`: Interpolated/nearest Z value of the source points within the grid cell.
- `r::Float64`: Radius or other parameter associated with the point (e.g., from the CSV file).
- `h::Float64`: Height of the point above/below the calculated plane (z - z_plane).
"""
mutable struct Height
    csv::String
    tm::DateTime
    x::Float64
    y::Float64
    z::Float64 # Interpolated/nearest Z
    r::Float64 # Added field r
    h::Float64 # Height above the plane

    # Corrected default constructor
    Height() = new("", Dates.unix2datetime(0), NaN, NaN, NaN, NaN, NaN) # Added NaN for r
    # Constructor with values
    Height(csv, tm, x, y, z, r, h) = new(string(csv), tm, Float64(x), Float64(y), Float64(z), Float64(r), Float64(h)) # Added r
end


# --- Functions for working with CSV ---

"""
    csv_to_data!(row::Height, csv_row::DataFrameRow)

Fills the `Height` structure from a DataFrame row.
Assumes the presence of columns :TimeReceived, :X, :Y, :Z, :R, :H, :CSV.
"""
function csv_to_data!(row::Height, csv_row::DataFrameRow)::Height
    try
        # Time processing (use global formats if Calculation is not available)
        # REPLACEMENT: Assume formats are defined globally or passed as arguments
        # If they are still in Main.Calculation, leave as is.
        # For example, use strings directly (less efficient):
        local fmt_t = DateFormat("yyyy-mm-ddTHH:MM:SS.s")
        local fmt_space = DateFormat("yyyy-mm-dd HH:MM:SS.s")

        time_val = csv_row.TimeReceived
        if isa(time_val, DateTime)
            row.tm = time_val
        elseif isa(time_val, AbstractString)
            time_str = string(time_val)
            try
                row.tm = DateTime(time_str, fmt_t)
            catch
                try
                    row.tm = DateTime(time_str, fmt_space)
                catch e
                    @warn "Failed to parse TimeReceived '$time_str': $e"
                    row.tm = Dates.unix2datetime(0)
                end
            end
        else
            @warn "Unexpected type for TimeReceived: $(typeof(time_val))"
            row.tm = Dates.unix2datetime(0)
        end

        # Processing numeric fields
        row.x = parse(Float64, string(coalesce(csv_row.X, "NaN")))
        row.y = parse(Float64, string(coalesce(csv_row.Y, "NaN")))
        row.z = parse(Float64, string(coalesce(csv_row.Z, "NaN")))
        row.r = parse(Float64, string(coalesce(csv_row.R, "NaN"))) # Added handling for R
        row.h = parse(Float64, string(coalesce(csv_row.H, "NaN")))
        # Processing CSV field if it exists
        row.csv = :CSV in names(csv_row) ? coalesce(csv_row.CSV, "") : ""


    catch e
        @error "Error processing Height from CSV: $e. Row data: $csv_row"
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        # Reset to default values on error
        row.tm = Dates.unix2datetime(0)
        row.x = row.y = row.z = row.r = row.h = NaN # Added r = NaN
        row.csv = ""
    end
    return row
end

"""
    data_to_csv(row::Height)::NamedTuple

Converts the `Height` structure to a NamedTuple for writing to CSV.
Includes fields CSV, TimeReceived, X, Y, Z, R, H.
"""
function data_to_csv(row::Height)::NamedTuple
    # REPLACEMENT: Use format directly or pass as argument
    local fmt_t = DateFormat("yyyy-mm-ddTHH:MM:SS.s")
    return (
        CSV=row.csv,
        TimeReceived=Dates.format(row.tm, fmt_t),
        X=row.x,
        Y=row.y,
        Z=row.z,
        R=row.r, # Added field R
        H=row.h
    )
end

"""
    csv_to_data_array(::Type{Height}, file::String)::Vector{Height}

Reads a CSV file and converts rows into a vector of `Height` structures.
"""
function csv_to_data_array(::Type{Height}, file::String)::Vector{Height}
    result = Height[]
    try
        # REPLACEMENT: Use format directly or pass as argument
        local fmt_t = DateFormat("yyyy-mm-ddTHH:MM:SS.s")
        # Specify the main date format, csv_to_data! will handle other variants
        df = CSV.read(file, DataFrame; dateformat=fmt_t)
        for csv_row in eachrow(df)
            row_instance = Height()
            push!(result, csv_to_data!(row_instance, csv_row)) # csv_to_data! now handles R
        end
    catch e
        @error "Failed to read or process Height CSV '$file': $e"
        showerror(stderr, e, catch_backtrace())
        println(stderr)
        return Height[] # Return an empty vector on error
    end
    return result
end


# --- Calculation Functions ---

"""
    calculate_grid_range(points::Vector{Point}) -> NamedTuple{(:xmin, :xmax, :ymin, :ymax), NTuple{4, Float64}}

Determines the minimum and maximum X and Y coordinates from a vector of `Point` points.
(Kept from the previous version, may require adaptation depending on usage)
"""
function calculate_grid_range(points::Vector{Point})
    config = load_config()

    # Extracting plane parameters
    config.plane.p0.x = points[1].x
    config.plane.p0.y = points[1].y
    config.plane.p1.x = points[end].x
    config.plane.p1.y = points[end].y

    save_config(config)
end

function _linear_regression_optim(x, z)
    # Define the objective function (SSE)
    function sse(params)
        a, b = params
        predictions = a .* x .+ b
        return sum((z .- predictions).^2)
    end

    # Initial guess for parameters [a, b]
    # Use Float64 for internal calculations
    x_f64 = Float64.(x)
    z_f64 = Float64.(z)
    initial_params = [0.0, mean(z_f64)] # Simple initial guess
    try
        # Attempt to use the least squares solution as an initial guess
        # Check if matrix is square or vector is empty before attempting \
        if length(x_f64) >= 2
            A = hcat(x_f64, ones(length(x_f64))) # Create design matrix [x 1]
            initial_params_ls = A \ z_f64 # Solve Ax = b for x (parameters [a, b])
            if length(initial_params_ls) == 2
                initial_params = initial_params_ls
            end
        end
    catch e
        println("Warning: Failed to compute least squares for initial guess. Error: $e")
    end

    # Perform optimization
    result = Optim.optimize(sse, initial_params, Optim.LBFGS()) # Specify the algorithm

    # Check convergence
    if !Optim.converged(result)
        @warn "Linear regression optimization did not converge!"
    end

    # Extract optimal parameters
    a, b = Optim.minimizer(result)
    return Float32(a), Float32(b) # Return Float32
end


"""
Processes a single laser scan: sorts by Z, takes the first N points,
performs linear regression, and returns a representative point.
"""
function calculate_laser_mins(laser_points::Vector{LaserRow}; num_points::Int = 20)::Vector{LaserRow}
    approximations::Vector{LaserRow} = []
    for row in laser_points
        n = length(row.x_array)
        
        # Sort by Z
        sort_idx = sortperm(row.z_array, rev = false)
        x_sorted = row.x_array[sort_idx]
        z_sorted = row.z_array[sort_idx]
        i_sorted = row.intensity_array[sort_idx]
    
        # Take the first num_points points
        limit = min(n, num_points)
        x_subset = x_sorted[1:limit]
        z_subset = z_sorted[1:limit]
        i_subset = i_sorted[1:limit]
    
        if limit < 2 # Need at least 2 points for regression
            @warn "Insufficient points ($limit) for regression in scan $(row.time). Returning average/first point."
            # If there are few points, can return the average or the first point
            if limit == 1
                # Use the single point
                return LaserRow(row.csv, row.tm, x_subset[1], z_subset[1], i_subset[1])
            else # limit == 0 (although this case is handled above)
                return LaserRow(row.csv, row.tm, 0.0f0, 0.0f0, 0) # Or return nothing?
            end
        end
    
        # Linear regression
        a, b = _linear_regression_optim(x_subset, z_subset)
    
        # Get the "average" point from regression
        x_mean = mean(x_subset)
        z_regr = a * x_mean + b
        i_val = i_subset[limit ÷ 2 + 1] # Median index (approximately)
    
        push!(approximations, LaserRow(row.csv, row.tm, [x_mean], [z_regr], [i_val]))
    end
    return approximations
end


function calculate_points_on_grid(points::Vector{Point}, scans::Int64)::Vector{Height}
    if isempty(points)
        @warn "Input vector 'points' for interpolate_mins is empty. Interpolation is not possible."
        return [] # Return an empty vector or handle otherwise
    end
    
    config = load_config()
    p0 = config.plane.p0
    p1 = config.plane.p1
    r_grid_max = sqrt((p1.y - p0.y)^2 + (p1.x - p0.x)^2)
    x_grid = p0.x:(Float64(p1.x) - p0.x) / scans:p1.x
    y_grid = p0.y:(Float64(p1.y) - p0.y) / scans:p1.y
    r_grid = 0.0:Float64(r_grid_max) / scans:r_grid_max

    # Extract scattered points
    x = [p.x for p in points]
    y = [p.y for p in points]
    z = [p.z for p in points]

    # Create points matrix (2xN for ScatteredInterpolation)
    # point_coords = hcat(x, y)' # Transpose to get 2 rows (x, y) and N columns
    # itp = ScatteredInterpolation.interpolate(Multiquadratic(), point_coords, z) # Example: Nearest neighbor
    xy = []
    xy_grid = []
    if abs(p1.x - p0.x) < abs(p1.y - p0.y)
        xy = y
        xy_grid = y_grid
    else
        xy = x
        xy_grid = x_grid
    end

    xy_sorted = []
    z_sorted = []
    if !issorted(xy)
        # Получаем индексы для сортировки вектора xy_unsorted
        perm = sortperm(xy)
    
        # Применяем эту сортировку к обоим векторам
        xy_sorted = xy[perm]
        z_sorted = z[perm] # Важно применить ту же перестановку!
    else
        # Если уже отсортирован, просто используем как есть
        xy_sorted = xy
        z_sorted = z
    end
    
    # Теперь используем отсортированные данные для интерполяции
    # Эта строка должна заменить вашу строку 288 или использоваться после подготовки данных
    itp = Interpolations.linear_interpolation(xy_sorted, z_sorted)

    # println(xy_grid)
    # println(z)
    # itp = Interpolations.linear_interpolation(xy, z)


    # Evaluate on the new grid
    heights::Vector{Height} = []
    # i = 1
    # for x_eval in x_grid
    #     z_evals = []
    #     for y_eval in y_grid
    #         # Evaluate expects points as columns (e.g., [x; y] or [x y]')
    #         z_eval = ScatteredInterpolation.evaluate(itp, [x_eval y_eval]')[1] # Evaluate single point, get first result
    #         push!(z_evals, z_eval)
    #     end
    #     height = Height()
    #     height.x = x_eval
    #     height.y = y_grid[1]
    #     height.z = maximum(z_evals)
    #     height.r = r_grid[i]
    #     height.h = 0

    #     i += 1
    #     push!(heights, height)
    # end
    z_valid = z[1]
    for i in 1:length(x_grid)
        height = Height()
        # height.z = ScatteredInterpolation.evaluate(itp, [x_grid[i] y_grid[i]]')[1]
        height.x = x_grid[i]
        height.y = y_grid[i]
        height.r = r_grid[i]
        try
            height.z = itp(xy_grid[i])
            z_valid = height.z
        catch
            height.z = z_valid
        end
        
        height.h = 0

        push!(heights, height)
    end
    return heights
end

function calculate_delta_heigts_destribution(points, output_path)

    # if layer_path empty (no layers1.csv)
    layer_path = joinpath(output_path, "layers")
    layer_path_current_height = joinpath(output_path, "current_height")

    layer_path_file = readdir(layer_path)

    if length(layer_path_file) == 0
        x = [p.x for p in points]
        y = [p.y for p in points]
        z = [p.z for p in points]
        r = [p.r for p in points]

        config = load_config()
        A = config.plane.A 
        B = config.plane.B
        C = config.plane.C
        D = config.plane.D

        z_plane = (-A .* x .- B .* y .- D) ./ C
        h = abs.(A .* x .+ B .* y .+ C .* z .+ D) ./ sqrt(A^2 + B^2 + C^2)
        
        # h = z .- z_plane

        # if < 0 ---> 0
        h .= max.(h, 0.0) # Efficient way to clamp at 0

        # save to csv
        filename_csv = joinpath(layer_path, "layers1.csv")
        open(filename_csv, "w") do file
            write(file, "x,y,z,r,h\n") # Header
            for i in 1:length(x)
                write(file, string(x[i], ",", y[i], ",", z[i], ",", r[i], ",", h[i], "\n"))
            end
        end

        return x, y, z, r, h
    else
        # load last csv layer layers*.csv
        layers = readdir(layer_path)
        layers = filter(x -> occursin(r"layers\d+\.csv", x), layers)
        layers = sort(layers, by = x -> parse(Int, match(r"\d+", x).match))
        last_layer = layers[end]

        # load last layer X,Y,Z,H
        last_layer_path = joinpath(layer_path, last_layer)
        x_last = []
        y_last = []
        z_last = []
        r_last = []
        h_last = []
        for line in eachline(last_layer_path)
            if line == "x,y,z,r,h"
                continue
            end
            data = split(line, ",")
            push!(x_last, parse(Float64, data[1]))
            push!(y_last, parse(Float64, data[2]))
            push!(z_last, parse(Float64, data[3]))
            push!(r_last, parse(Float64, data[4]))
            push!(h_last, parse(Float64, data[5]))
        end

        x = [p.x for p in points]
        y = [p.y for p in points]
        z = [p.z for p in points]
        r = [p.r for p in points]

        # h = z .- z_last
        h = sqrt.((x .- x_last).^2 + (y .- y_last).^2 + (z .- z_last).^2)

        # save to csv
        id = parse(Int, match(r"\d+", last_layer).match) + 1
        filename_csv = joinpath(layer_path, "layers$id.csv")
        open(filename_csv, "w") do file
            write(file, "x,y,z,r,h\n") # Header
            for i in 1:length(x)
                write(file, string(x[i], ",", y[i], ",", z[i], ",", r[i], ",", h[i], "\n"))
            end
        end
        config = load_config()
        A = config.plane.A 
        B = config.plane.B
        C = config.plane.C
        D = config.plane.D
        
        z_plane = (-A .* x .- B .* y .- D) ./ C
        h_current = z .- z_plane
        h_current .= max.(h_current, 0.0) # Efficient way to clamp at 0

        return x, y, z, r, h
    end

    return Nothing, Nothing, Nothing, Nothing, Nothing
end

function calculate_heigts_destribution(points, output_path)

    layer_path_current_height = joinpath(output_path, "current_height")

    layer_path_file = readdir(layer_path_current_height)
    
    last_layer = ""
    if length(layer_path_file) == 0
        last_layer = joinpath(layer_path_current_height, "layers1.csv")
    else
        layers = readdir(layer_path_current_height)
        layers = filter(x -> occursin(r"layers\d+\.csv", x), layers)
        layers = sort(layers, by = x -> parse(Int, match(r"\d+", x).match))
        last_layer = layers[end]
        id = parse(Int, match(r"\d+", last_layer).match) + 1
        last_layer = joinpath(layer_path_current_height, "layers$id.csv")
    end

    x = [p.x for p in points]
    y = [p.y for p in points]
    z = [p.z for p in points]
    r = [p.r for p in points]

    config = load_config()
    A = config.plane.A 
    B = config.plane.B
    C = config.plane.C
    D = config.plane.D

    z_plane = (-A .* x .- B .* y .- D) ./ C

    # h = z .- z_plane
    h = abs.(A .* x .+ B .* y .+ C .* z .+ D) ./ sqrt(A^2 + B^2 + C^2)
    

    # if < 0 ---> 0
    h .= max.(h, 0.0) # Efficient way to clamp at 0

    # save to current_height.csv
    filename_csv = joinpath(layer_path_current_height, last_layer)
    open(filename_csv, "w") do file
        write(file, "x,y,z,r,h\n") # Header
        for i in 1:length(x)
            write(file, string(x[i], ",", y[i], ",", z[i], ",", r[i], ",", h[i], "\n"))
        end
    end

    return x, y, z, r, h
end
