# calc/config.jl
using YAML
using Printf # For formatted output
using OrderedCollections # <-- Add this line to import

mutable struct PointConfig
    x::Float64
    y::Float64
end

mutable struct CalibrationConfig
    x::Float64
    y::Float64
    z::Float64
    a::Float64
    b::Float64
    c::Float64
    laser_min_x::Float64
    laser_max_x::Float64
end

mutable struct PlaneConfig
    exist::Bool
    A::Float64
    B::Float64
    C::Float64
    D::Float64
    StdZ::Float64
    p0::PointConfig # Using nested structure
    p1::PointConfig # Using nested structure
    scans::Int
end

mutable struct AppConfig
    calibration::CalibrationConfig
    plane::PlaneConfig
end

# --- Function to load configuration from file ---
"""
    load_config(filename::String="config.yaml") -> Union{AppConfig, Nothing}

Loads configuration from a YAML file and returns an AppConfig object.
Returns `nothing` in case of an error.
"""
function load_config(filename::String="config.yaml")::Union{AppConfig, Nothing}
    try
        if !isfile(filename)
            @error "Configuration file not found: $filename"
            return nothing
        end

        raw_config = YAML.load_file(filename)

        # Key existence check (basic)
        if !haskey(raw_config, "calibration") || !haskey(raw_config, "plane")
             @error "Missing required sections 'calibration' or 'plane' in file $filename"
             return nothing
        end

        cal_data = raw_config["calibration"]
        plane_data = raw_config["plane"]

        # Nested key check (example)
        req_cal_keys = ["exist", "x", "y", "z", "a", "b", "c", "laser_min_x", "laser_max_x"]
        req_plane_keys = ["A", "B", "C", "D", "StdZ", "p0", "p1", "scans"]
        req_point_keys = ["x", "y"]

        # (Optional) Add stricter key validation if necessary

        # Create nested structures
        p0 = PointConfig(plane_data["p0"]["x"], plane_data["p0"]["y"])
        p1 = PointConfig(plane_data["p1"]["x"], plane_data["p1"]["y"])

        # Create main structures
        calibration_config = CalibrationConfig(
            cal_data["x"], cal_data["y"], cal_data["z"],
            cal_data["a"], cal_data["b"], cal_data["c"],
            cal_data["laser_min_x"], cal_data["laser_max_x"]
        )
            
        plane_config = PlaneConfig(
            plane_data["exist"], # Take 'exist' from the plane section
            plane_data["A"], plane_data["B"], plane_data["C"], plane_data["D"],
            plane_data["StdZ"],
            p0, p1,
            plane_data["scans"]
        )

        # Assemble the final configuration object
        app_config = AppConfig(calibration_config, plane_config)

        return app_config

    catch e
        @error "Error loading or parsing file '$filename':" exception=(e, catch_backtrace())
        return nothing # Return nothing on any error
    end
end

"""
    save_config(config::AppConfig, filename::String="config.yaml")

Saves the AppConfig object to a YAML file, preserving key order.
"""
function save_config(config::AppConfig, filename::String="config.yaml")
    # Use OrderedDict to preserve key order at all levels
    config_odict = OrderedDict(
        "calibration" => OrderedDict( # <-- OrderedDict here
            "x" => config.calibration.x,
            "y" => config.calibration.y,
            "z" => config.calibration.z,
            "a" => config.calibration.a,
            "b" => config.calibration.b,
            "c" => config.calibration.c,
            "laser_min_x" => config.calibration.laser_min_x,
            "laser_max_x" => config.calibration.laser_max_x
        ),
        "plane" => OrderedDict( # <-- OrderedDict here
            "exist" => config.plane.exist,
            "A" => config.plane.A,
            "B" => config.plane.B,
            "C" => config.plane.C,
            "D" => config.plane.D,
            "StdZ" => config.plane.StdZ,
            "p0" => OrderedDict( # <-- OrderedDict here too, if x, y order matters
                "x" => config.plane.p0.x,
                "y" => config.plane.p0.y
            ),
            "p1" => OrderedDict( # <-- OrderedDict here too
                "x" => config.plane.p1.x,
                "y" => config.plane.p1.y
            ),
            "scans" => config.plane.scans # <-- If scans is an array/vector, order is preserved automatically
        )
    )

    try
        # YAML.write_file should handle OrderedDict correctly
        YAML.write_file(filename, config_odict)
    catch e
        @error "Error saving configuration to file '$filename':" exception=(e, catch_backtrace())
    end
end