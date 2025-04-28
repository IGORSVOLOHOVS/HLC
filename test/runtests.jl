# test/runtests.jl or test_calculation.jl

using Test
using Dates
using LinearAlgebra
using CSV
using DataFrames
# Ensure using Base: for basename if not implicitly available
using Base

# --- IMPORTANT FIX for running tests within a package structure ---
# Use relative import assuming Calculation.jl is in ../src/
using ..Calculation
# If Calculation is installed as a package or globally available,
# you might use `using Calculation`, but `using ..Calculation` is standard
# for package tests.
# -----------------------------------------------------------------


# --- Test Helper Functions ---
@testset "Helper Functions" begin
    @testset "_parse_delimited_array" begin
        @test Calculation._parse_delimited_array("1.1 2.2 3.3", Float64; delim=' ') == [1.1, 2.2, 3.3]
        @test Calculation._parse_delimited_array("10 20 -30", Int32; delim=' ') == Int32[10, 20, -30]
        @test Calculation._parse_delimited_array(" 1.0  2.0 ", Float64; delim=' ') == [1.0, 2.0] # Extra spaces
        @test Calculation._parse_delimited_array("", Float64; delim=' ') == Float64[] # Empty string
        @test Calculation._parse_delimited_array("   ", Int32; delim=' ') == Int32[] # Only spaces
        @test Calculation._parse_delimited_array("1;2;3", Int16; delim=';') == Int16[1, 2, 3] # Different delimiter
        # Test parsing failure (returns empty array and warns)
        @test_logs (:warn,) Calculation._parse_delimited_array("1.0 abc 3.0", Float64; delim=' ') == Float64[]
    end

    @testset "_format_delimited_array" begin
        @test Calculation._format_delimited_array([1.1, 2.2, 3.3]; delim=' ') == "1.1 2.2 3.3"
        @test Calculation._format_delimited_array(Int32[10, 20, -30]; delim=' ') == "10 20 -30"
        @test Calculation._format_delimited_array(Float64[]; delim=' ') == "" # Empty array
        @test Calculation._format_delimited_array([1, 2, 3]; delim=';') == "1;2;3" # Different delimiter
    end
end

# --- Test CSV Handling ---
@testset "CSV Handling" begin
    # Create a temporary directory for CSV files
    mktempdir() do temp_dir
        robot_csv_path = joinpath(temp_dir, "robot_test.csv")
        laser_csv_path = joinpath(temp_dir, "laser_test.csv")

        # --- RobotRow CSV ---
        @testset "RobotRow CSV" begin
            # Sample data - UPDATE: Set csv field to "" as it's not populated from file anymore
            robot_data_expected = [
                Calculation.RobotRow("", DateTime(2025, 4, 15, 10, 0, 0), 1.0, 2.0, 3.0, 10.0, 20.0, 30.0),
                Calculation.RobotRow("", DateTime(2025, 4, 15, 10, 0, 1), 1.1, 2.1, 3.1, 11.0, 21.0, 31.0)
            ]
            # Data to write (doesn't include csv field)
            robot_data_to_write = Calculation.data_to_csv.(robot_data_expected)

            # Write test CSV
            CSV.write(robot_csv_path, robot_data_to_write)

            # Test reading
            read_robot_data = Calculation.csv_to_data_array(Calculation.RobotRow, robot_csv_path)
            @test length(read_robot_data) == 2
            # Add checks only if read_robot_data is not empty
            if length(read_robot_data) == 2
                @test read_robot_data[1].tm == robot_data_expected[1].tm
                @test read_robot_data[1].x == robot_data_expected[1].x
                @test read_robot_data[1].rz == robot_data_expected[1].rz
                @test read_robot_data[1].csv == "" # Check csv field is now empty
                @test read_robot_data[2].y == robot_data_expected[2].y
                @test read_robot_data[2].rx == robot_data_expected[2].rx
                @test read_robot_data[2].csv == "" # Check csv field is now empty
            end


            # Test reading non-existent file
            @test Calculation.csv_to_data_array(Calculation.RobotRow, joinpath(temp_dir, "nonexistent.csv")) == Calculation.RobotRow[]

            # Test data_to_csv formatting
            nt = Calculation.data_to_csv(robot_data_expected[1]) # Use expected data which has all fields
            @test nt.TimeReceived == "2025-04-15 10:00:00.0"
            @test nt.X == 1.0
            @test nt.RZ == 30.0
        end

        # --- LaserRow CSV ---
         @testset "LaserRow CSV" begin
            # Sample data - UPDATE: Set csv field to ""
            laser_data_expected = [
                Calculation.LaserRow("", DateTime(2025, 4, 15, 11, 0, 0), [1.1, 1.2], [3.1, 3.2], Int32[10, 11]),
                Calculation.LaserRow("", DateTime(2025, 4, 15, 11, 0, 1), [2.1, 2.2, 2.3], [4.1, 4.2, 4.3], Int32[20, 21, 22])
            ]
             # Data to write (doesn't include csv field)
            laser_data_to_write = Calculation.data_to_csv.(laser_data_expected)

            # Write test CSV
            CSV.write(laser_csv_path, laser_data_to_write)

            # Test reading
            read_laser_data = Calculation.csv_to_data_array(Calculation.LaserRow, laser_csv_path)
            @test length(read_laser_data) == 2
             # Add checks only if read_laser_data is not empty
             if length(read_laser_data) == 2
                @test read_laser_data[1].tm == laser_data_expected[1].tm
                @test read_laser_data[1].x_array == laser_data_expected[1].x_array
                @test read_laser_data[1].z_array == laser_data_expected[1].z_array
                @test read_laser_data[1].intensity_array == laser_data_expected[1].intensity_array
                @test read_laser_data[1].csv == "" # Check csv field is now empty
                @test read_laser_data[2].tm == laser_data_expected[2].tm
                @test read_laser_data[2].x_array == laser_data_expected[2].x_array
                @test read_laser_data[2].intensity_array == laser_data_expected[2].intensity_array
                @test read_laser_data[2].csv == "" # Check csv field is now empty
             end

            # Test reading non-existent file
             @test Calculation.csv_to_data_array(Calculation.LaserRow, joinpath(temp_dir, "nonexistent_laser.csv")) == Calculation.LaserRow[]

            # Test data_to_csv formatting
            nt = Calculation.data_to_csv(laser_data_expected[1]) # Use expected data
            @test nt.TimeReceived == "2025-04-15 11:00:00.0"
            @test nt.X == "1.1 1.2"
            @test nt.Z == "3.1 3.2"
            @test nt.Intensity == "10 11"
         end
    end # mktempdir
end # CSV Handling Testset

# --- Test Transformation Logic ---
# (No changes needed in this section)
@testset "Transformation Logic" begin
    # Use isapprox for floating point comparisons
    TOL = 1e-9 # Tolerance for isapprox

    @testset "euler_to_transform_y" begin
        # Identity pose
        identity_pose = Calculation.RobotRow("", Dates.now(), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        T_identity = Calculation.euler_to_transform_y(identity_pose)
        @test T_identity ≈ Matrix(1.0I, 4, 4) atol=TOL

        # Pure translation
        trans_pose = Calculation.RobotRow("", Dates.now(), 1.0, 2.0, 3.0, 0.0, 0.0, 0.0)
        T_trans = Calculation.euler_to_transform_y(trans_pose)
        @test T_trans[1:3, 1:3] ≈ Matrix(1.0I, 3, 3) atol=TOL
        @test T_trans[1:3, 4] ≈ [1.0, 2.0, 3.0] atol=TOL
        @test T_trans[4, :] ≈ [0.0, 0.0, 0.0, 1.0] atol=TOL

        # Pure rotation (90 deg yaw)
        yaw_pose = Calculation.RobotRow("", Dates.now(), 0.0, 0.0, 0.0, 0.0, 0.0, 90.0)
        T_yaw = Calculation.euler_to_transform_y(yaw_pose)
        R_yaw_expected = [0.0 -1.0 0.0; 1.0 0.0 0.0; 0.0 0.0 1.0] # ZYX: Rz(90)
        @test T_yaw[1:3, 1:3] ≈ R_yaw_expected atol=TOL
        @test T_yaw[1:3, 4] ≈ [0.0, 0.0, 0.0] atol=TOL

         # Pure rotation (90 deg pitch)
        pitch_pose = Calculation.RobotRow("", Dates.now(), 0.0, 0.0, 0.0, 0.0, 90.0, 0.0)
        T_pitch = Calculation.euler_to_transform_y(pitch_pose)
        R_pitch_expected = [0.0 0.0 1.0; 0.0 1.0 0.0; -1.0 0.0 0.0] # ZYX: Ry(90)
        @test T_pitch[1:3, 1:3] ≈ R_pitch_expected atol=TOL

         # Pure rotation (90 deg roll)
        roll_pose = Calculation.RobotRow("", Dates.now(), 0.0, 0.0, 0.0, 90.0, 0.0, 0.0)
        T_roll = Calculation.euler_to_transform_y(roll_pose)
        R_roll_expected = [1.0 0.0 0.0; 0.0 0.0 -1.0; 0.0 1.0 0.0] # ZYX: Rx(90)
        @test T_roll[1:3, 1:3] ≈ R_roll_expected atol=TOL

        # Combined pose
        combined_pose = Calculation.RobotRow("", Dates.now(), 1.0, 2.0, 3.0, 10.0, 20.0, 30.0)
        T_combined = Calculation.euler_to_transform_y(combined_pose)
        # Manual calculation of expected R is tedious, but check translation part
        @test T_combined[1:3, 4] ≈ [1.0, 2.0, 3.0] atol=TOL
    end

    @testset "transform_to_euler_y" begin
        # Test identity
        T_identity = Matrix(1.0I, 4, 4)
        pose_identity = Calculation.transform_to_euler_y(T_identity)
        @test pose_identity.x ≈ 0.0 atol=TOL
        @test pose_identity.y ≈ 0.0 atol=TOL
        @test pose_identity.z ≈ 0.0 atol=TOL
        @test pose_identity.rx ≈ 0.0 atol=TOL
        @test pose_identity.ry ≈ 0.0 atol=TOL
        @test pose_identity.rz ≈ 0.0 atol=TOL

        # Test pure translation
        T_trans = Calculation.euler_to_transform_y(Calculation.RobotRow("", Dates.unixepoch(), 1.0, 2.0, 3.0, 0.0, 0.0, 0.0))
        pose_trans = Calculation.transform_to_euler_y(T_trans)
        @test pose_trans.x ≈ 1.0 atol=TOL
        @test pose_trans.y ≈ 2.0 atol=TOL
        @test pose_trans.z ≈ 3.0 atol=TOL
        @test pose_trans.rx ≈ 0.0 atol=TOL
        @test pose_trans.ry ≈ 0.0 atol=TOL
        @test pose_trans.rz ≈ 0.0 atol=TOL

        # Test 90 deg yaw
        T_yaw = Calculation.euler_to_transform_y(Calculation.RobotRow("", Dates.unixepoch(), 0.0, 0.0, 0.0, 0.0, 0.0, 90.0))
        pose_yaw = Calculation.transform_to_euler_y(T_yaw)
        @test pose_yaw.rx ≈ 0.0 atol=TOL
        @test pose_yaw.ry ≈ 0.0 atol=TOL
        @test pose_yaw.rz ≈ 90.0 atol=TOL

        # Test combined (convert forth and back)
        original_pose = Calculation.RobotRow("", Dates.unixepoch(), 1.5, -2.1, 0.5, 15.0, -25.0, 45.0)
        T_combined = Calculation.euler_to_transform_y(original_pose)
        recovered_pose = Calculation.transform_to_euler_y(T_combined)
        @test recovered_pose.x ≈ original_pose.x atol=TOL
        @test recovered_pose.y ≈ original_pose.y atol=TOL
        @test recovered_pose.z ≈ original_pose.z atol=TOL
        @test recovered_pose.rx ≈ original_pose.rx atol=TOL
        @test recovered_pose.ry ≈ original_pose.ry atol=TOL
        @test recovered_pose.rz ≈ original_pose.rz atol=TOL

        # Test Gimbal Lock (+90 deg pitch)
        T_gimbal_plus = Calculation.euler_to_transform_y(Calculation.RobotRow("", Dates.unixepoch(), 0.0, 0.0, 0.0, 0.0, 90.0, 0.0))
        pose_gimbal_plus = Calculation.transform_to_euler_y(T_gimbal_plus)
        @test pose_gimbal_plus.ry ≈ 90.0 atol=TOL
        # In gimbal lock, only sum/difference of yaw+roll is fixed. Check if consistent.
        # Here, rx=0, rz=atan(R12, R22) = atan(0,1) = 0
        @test pose_gimbal_plus.rx ≈ 0.0 atol=TOL
        @test pose_gimbal_plus.rz ≈ 0.0 atol=TOL #atan(0,1)=0

        # Test Gimbal Lock (-90 deg pitch)
        T_gimbal_minus = Calculation.euler_to_transform_y(Calculation.RobotRow("", Dates.unixepoch(), 0.0, 0.0, 0.0, 0.0, -90.0, 0.0))
        pose_gimbal_minus = Calculation.transform_to_euler_y(T_gimbal_minus)
        @test pose_gimbal_minus.ry ≈ -90.0 atol=TOL
        # Here, rx=0, rz=atan(R12, R22) = atan(0,1) = 0
        @test pose_gimbal_minus.rx ≈ 0.0 atol=TOL
        @test pose_gimbal_minus.rz ≈ 0.0 atol=TOL
    end
end # Transformation Logic Testset


# --- Test Point Calculation ---
# (No changes needed in this section)
@testset "Point Calculation" begin
    TOL = 1e-9 # Tolerance for isapprox

    # --- Test calculate_points_row ---
    @testset "calculate_points_row" begin
        # Simple case: Robot at origin, no rotation. Calibration identity.
        robot_origin = Calculation.RobotRow("robot", DateTime(2025,1,1), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
        # Use "" for csv field in expected laser data
        laser_simple = Calculation.LaserRow("", DateTime(2025,1,1), [1.0, 2.0], [3.0, 4.0], Int32[1, 2])
        calib_identity = Calculation.RobotRow("", DateTime(2025,1,1), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)

        points = Calculation.calculate_points_row(robot_origin, laser_simple, calib_identity)
        @test length(points) == 2
        # Points should be directly (x, 0, z) in world frame
        @test points[1].x ≈ 1.0 atol=TOL; @test points[1].y ≈ 0.0 atol=TOL; @test points[1].z ≈ 3.0 atol=TOL
        @test points[2].x ≈ 2.0 atol=TOL; @test points[2].y ≈ 0.0 atol=TOL; @test points[2].z ≈ 4.0 atol=TOL
        @test points[1].tm == laser_simple.tm
        @test points[1].csv == laser_simple.csv # Will be "" == ""

        # Case: Robot translated, no rotation. Calibration identity.
        robot_translated = Calculation.RobotRow("robot", DateTime(2025,1,1), 10.0, 20.0, 30.0, 0.0, 0.0, 0.0)
        points_trans = Calculation.calculate_points_row(robot_translated, laser_simple, calib_identity)
        @test length(points_trans) == 2
        # Points should be (10+x, 20+0, 30+z)
        @test points_trans[1].x ≈ (10.0 + 1.0) atol=TOL; @test points_trans[1].y ≈ (20.0 + 0.0) atol=TOL; @test points_trans[1].z ≈ (30.0 + 3.0) atol=TOL
        @test points_trans[2].x ≈ (10.0 + 2.0) atol=TOL; @test points_trans[2].y ≈ (20.0 + 0.0) atol=TOL; @test points_trans[2].z ≈ (30.0 + 4.0) atol=TOL

        # Case: Robot rotated (90 deg yaw), no translation. Calibration identity.
        robot_rotated = Calculation.RobotRow("robot", DateTime(2025,1,1), 0.0, 0.0, 0.0, 0.0, 0.0, 90.0) # Rotates +X axis to +Y axis
        points_rot = Calculation.calculate_points_row(robot_rotated, laser_simple, calib_identity)
        @test length(points_rot) == 2
        # Original point (1,0,3) -> rotated should be (-0, 1, 3) approx (0, 1, 3)
        # Original point (2,0,4) -> rotated should be (-0, 2, 4) approx (0, 2, 4)
        # Rz(90) = [0 -1 0; 1 0 0; 0 0 1]. p' = R*p => [0 -1 0; 1 0 0; 0 0 1] * [1;0;3] = [0;1;3]
        #                                             [0 -1 0; 1 0 0; 0 0 1] * [2;0;4] = [0;2;4]
        @test points_rot[1].x ≈ 0.0 atol=TOL; @test points_rot[1].y ≈ 1.0 atol=TOL; @test points_rot[1].z ≈ 3.0 atol=TOL
        @test points_rot[2].x ≈ 0.0 atol=TOL; @test points_rot[2].y ≈ 2.0 atol=TOL; @test points_rot[2].z ≈ 4.0 atol=TOL

        # Case: Robot at origin, Calibration offset translation
        calib_offset = Calculation.RobotRow("", DateTime(2025,1,1), 0.1, 0.2, 0.3, 0.0, 0.0, 0.0) # Laser mounted 0.1m forward, 0.2m left, 0.3m up rel to robot
        points_calib = Calculation.calculate_points_row(robot_origin, laser_simple, calib_identity)
        @test length(points_calib) == 2
        # Laser point (1,0,3) in laser frame. Laser frame origin is (0.1, 0.2, 0.3) in robot frame. Robot frame = World frame.
        # Point in world = RobotPose * CalibPose * LaserPoint = Identity * T(0.1,0.2,0.3) * [1,0,3,1]^T
        # T_calib * p_laser = [1 0 0 0.1; 0 1 0 0.2; 0 0 1 0.3; 0 0 0 1] * [1;0;3;1] = [1+0.1; 0+0.2; 3+0.3; 1] = [1.1; 0.2; 3.3; 1]
        # T_calib * p_laser = [1 0 0 0.1; 0 1 0 0.2; 0 0 1 0.3; 0 0 0 1] * [2;0;4;1] = [2+0.1; 0+0.2; 4+0.3; 1] = [2.1; 0.2; 4.3; 1]
        @test points_calib[1].x ≈ 1.1 atol=TOL; @test points_calib[1].y ≈ 0.2 atol=TOL; @test points_calib[1].z ≈ 3.3 atol=TOL
        @test points_calib[2].x ≈ 2.1 atol=TOL; @test points_calib[2].y ≈ 0.2 atol=TOL; @test points_calib[2].z ≈ 4.3 atol=TOL

        # Test warning for mismatched array lengths
        laser_mismatch = Calculation.LaserRow("", DateTime(2025,1,1), [1.0, 2.0], [3.0], Int32[1, 2]) # z shorter
        @test_logs (:warn,) Calculation.calculate_points_row(robot_origin, laser_mismatch, calib_identity)
        points_mismatch = Calculation.calculate_points_row(robot_origin, laser_mismatch, calib_identity)
        @test length(points_mismatch) == 1 # Should process only min length

    end # calculate_points_row testset

    # --- Test calculate_points ---
    @testset "calculate_points" begin
         # Setup data - UPDATE: Use "" for csv field
        robot_rows = [
            Calculation.RobotRow("", DateTime(2025,1,1,0,0,0), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0),
            Calculation.RobotRow("", DateTime(2025,1,1,0,0,1), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0) # Translated +1m in X
        ]
        laser_rows = [
            Calculation.LaserRow("", DateTime(2025,1,1,0,0,0), [1.0], [1.0], Int32[1]),
            Calculation.LaserRow("", DateTime(2025,1,1,0,0,1), [2.0], [2.0], Int32[2])
        ]
        calibration = Calculation.RobotRow("", DateTime(2025,1,1), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0) # Identity

        all_points = Calculation.calculate_points(robot_rows, laser_rows, calibration)
        @test length(all_points) == 2

        # Point 1: Robot at origin, laser point (1,0,1) -> World (1,0,1)
        @test all_points[1].x ≈ 1.0 atol=TOL; @test all_points[1].y ≈ 0.0 atol=TOL; @test all_points[1].z ≈ 1.0 atol=TOL
        @test all_points[1].csv == "" # Check csv field is inherited (empty)
        @test all_points[1].tm == DateTime(2025,1,1,0,0,0)

        # Point 2: Robot at (1,0,0), laser point (2,0,2) -> World (1+2, 0+0, 0+2) = (3,0,2)
        @test all_points[2].x ≈ 3.0 atol=TOL; @test all_points[2].y ≈ 0.0 atol=TOL; @test all_points[2].z ≈ 2.0 atol=TOL
        @test all_points[2].csv == "" # Check csv field is inherited (empty)
        @test all_points[2].tm == DateTime(2025,1,1,0,0,1)

        # Test with mismatched lengths (should warn and process min length)
        robot_rows_short = [robot_rows[1]]
        @test_logs (:warn,) Calculation.calculate_points(robot_rows_short, laser_rows, calibration)
        points_mismatch = Calculation.calculate_points(robot_rows_short, laser_rows, calibration)
        @test length(points_mismatch) == 1 # Only first point calculated

        # Test with timestamp mismatch (should warn)
        laser_rows_time_mismatch = [
             Calculation.LaserRow("", DateTime(2025,1,1,0,0,0), [1.0], [1.0], Int32[1]),
             Calculation.LaserRow("", DateTime(2025,1,1,0,0,5), [2.0], [2.0], Int32[2]) # 5s timestamp vs 1s robot
        ]
         @test_logs (:warn,) Calculation.calculate_points(robot_rows, laser_rows_time_mismatch, calibration)
         points_time_mismatch = Calculation.calculate_points(robot_rows, laser_rows_time_mismatch, calibration)
         @test length(points_time_mismatch) == 2 # Still processes, just warns

         # Test with empty input
         @test Calculation.calculate_points(Calculation.RobotRow[], laser_rows, calibration) == Calculation.Point[]
         @test Calculation.calculate_points(robot_rows, Calculation.LaserRow[], calibration) == Calculation.Point[]

    end # calculate_points testset

end # Point Calculation Testset

println("Calculation module tests completed.")

