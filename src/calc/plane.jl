# calc/plane.jl
using LinearAlgebra
using Statistics

"""
    calculate_plane(points::Vector{Point}; num_points_edge::Int = 100) -> Union{NTuple{4, Float64}, Nothing}

Calculates the parameters of the plane Ax + By + Cz + D = 0 that approximates the point cloud,
using SVD on points from the edges of the (assumed sorted) cloud.
Returns a tuple (A, B, C, D), where the normal vector (A, B, C) is normalized.
Returns `nothing` if there are insufficient points or an error occurs.

# Arguments
- `points::Vector{Point}`: Vector of points in the cloud (assumed potentially sorted by trajectory).
- `num_points_edge::Int`: Number of points to take from each edge for the calculation.
"""
function calculate_plane(points::Vector{Point}; num_points_edge::Int = 100)::Union{NTuple{4, Float64}, Nothing}
    n_points = length(points)
    if n_points < 3
        @error "Insufficient points ($n_points) to define a plane."
        return nothing
    end

    # Select points from the edges
    # n_edge = min(num_points_edge, n_points ÷ 2)
    n_edge = n_points
    local points_for_plane::Vector{Point}
    if n_edge < 1 && n_points >= 3 # If the layer is short, but there are enough points
        @warn "Layer is short, using all $n_points points to define the plane."
        points_for_plane = points
    elseif n_edge < 1 # If n_points < 3, already handled above
         @error "Insufficient points ($n_points) to define the plane (n_edge < 1)."
         return nothing
    else
        p_first = points[1:n_edge]
        # Ensure we don't take more points than available and indices are correct
        start_last = max(1, n_points - n_edge + 1)
        p_last = points[start_last:end]
        points_for_plane = vcat(p_first, p_last)
        # Remove duplicates if ranges overlapped (for very short layers)
        unique!(points_for_plane)
        if length(points_for_plane) < 3
             @error "Insufficient unique points ($(length(points_for_plane))) after edge selection to define the plane."
             return nothing
        end
    end

    # Convert points to a matrix (3 x N)
    points_matrix = Matrix{Float64}(undef, 3, length(points_for_plane))
    for (i, p) in enumerate(points_for_plane)
        points_matrix[:, i] = [p.x, p.y, p.z]
    end

    # Calculate the centroid of the selected points
    centroid = mean(points_matrix, dims=2) # 3x1 column vector

    # Center the points
    centered_points = points_matrix .- centroid

    try
        # Perform SVD
        U, _, _ = svd(centered_points)

        # The normal to the plane is the last left singular vector
        normal_vector = U[:, end]
        A, B, C = normal_vector[1], normal_vector[2], normal_vector[3]

        # Calculate D
        D = -dot(normal_vector, vec(centroid)) # vec() converts 3x1 to a vector

        # Check for vertical plane
         if abs(C) < 1e-9
             @warn "Found plane is almost vertical (C ≈ 0). Calculations might be unstable."
         end

        # --- Assuming load_config/save_config handle a config object ---
        # --- This part interacts with external configuration ---
        conf = load_config() # Assumed function
        conf.plane.A = A
        conf.plane.B = B
        conf.plane.C = C
        conf.plane.D = D
        save_config(conf) # Assumed function
        # ----------------------------------------------------------

        return (A, B, C, D)

    catch e
        @error "Error calculating plane via SVD:" exception=(e, catch_backtrace())
        return nothing
    end
end

"""
    filter_by_plane(points::Vector{Point}, plane_params::NTuple{4, Float64}, threshold::Float64) -> Vector{Point}

Filters points, keeping those that are within a specified *vertical*
distance (`threshold`) from the plane Ax + By + Cz + D = 0.

# Arguments
- `points::Vector{Point}`: Vector of original points.
# Returns
- `Vector{Point}`: Filtered vector of points.
"""
function filter_by_plane(points::Vector{Point})::Vector{Point}
    # --- Assuming load_config provides necessary parameters ---
    conf = Calc.load_config() # Assumed function/module
    A = conf.plane.A
    B = conf.plane.B
    C = conf.plane.C
    D = conf.plane.D
    threshold = conf.plane.StdZ # Assuming StdZ holds the threshold
    # ----------------------------------------------------------

    if abs(C) < 1e-9
        @error "Plane is almost vertical (C ≈ 0). Cannot calculate vertical distance for filtering."
        # Return empty or original? Depends on requirements.
        return Point[] # Returning empty as filtering is not possible
    end

    filtered_points::Vector{Point} = []

    for p in points
        # z_plane = (-D - A * p.x - B * p.y) / C
        # vertical_distance = abs(p.z - z_plane)
        # if vertical_distance > threshold # Keep points FARTHER than the threshold
        #     push!(filtered_points, p)
        # end
        distanc = abs(A*p.x + B*p.y + C*p.z + D) / sqrt(A^2 + B^2 + C^2)
        if distanc > threshold # Keep points FARTHER than the threshold
            push!(filtered_points, p)
        end
    end

    return filtered_points
end

function filter_laser_points(laser_rows::Vector{LaserRow})::Vector{LaserRow}
    config = load_config()
    laser_min = config.calibration.laser_min_x
    laser_max = config.calibration.laser_max_x

    new_laser_rows::Vector{LaserRow} = []
    for laser_row in laser_rows
        new_laser_row::LaserRow = LaserRow()
        new_laser_row.csv = laser_row.csv
        new_laser_row.tm = laser_row.tm
        for i in 1:length(laser_row.x_array)
            if laser_row.x_array[i] >= laser_min && laser_row.x_array[i] <= laser_max
                push!(new_laser_row.x_array, laser_row.x_array[i])
                push!(new_laser_row.z_array, laser_row.z_array[i])
                push!(new_laser_row.intensity_array, laser_row.intensity_array[i])
            end
        end
        push!(new_laser_rows, new_laser_row)
    end
    return new_laser_rows
end
