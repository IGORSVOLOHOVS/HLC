# plot/plot.jl
module Plot

using Makie, GLMakie
using Colors
using LinearAlgebra
using Printf # Added for formatted coordinate strings

function primary_resolution()
    monitor = GLMakie.GLFW.GetPrimaryMonitor()
    videomode = GLMakie.MonitorProperties(monitor).videomode
    return (videomode.width, videomode.height)
end

# Create Figure and Axes
HLC_FIG = Figure(size = primary_resolution())
HLC_AX_HD = Axis(HLC_FIG[1, 1],
    title="Delta Heights Distribution",
    xlabel = "step (mm)", ylabel = "Δheight (mm)",
    aspect = DataAspect()
)

HLC_AX_CHD = Axis(HLC_FIG[2, 1],
    title="Heights Distribution",
    xlabel = "step (mm)", ylabel = "height (mm)",
    aspect = DataAspect()
)

HLC_AX_PC = Axis3(HLC_FIG[3, 1],
    title="Point Cloud",
    xlabel = "x (mm)", ylabel = "y (mm)", zlabel = "z (mm)",
    aspect=:data,
    viewmode = :free,
    zoommode = :fit
)

# --- Глобальная ссылка для хранения объекта текущей легенды HLC_AX_HD ---
# Инициализируем `nothing`, так как сначала легенды нет.
# Используем Ref для хранения изменяемой ссылки.
HLC_AX_HD_LEGEND = Ref{Union{Legend, Nothing}}(nothing)
HLC_AX_CHD_LEGEND = Ref{Union{Legend, Nothing}}(nothing)
HLC_AX_PC_LEGEND = Ref{Union{Legend, Nothing}}(nothing)
# ---------------------------------------------------------------------

# Global variables for layer/dataset IDs
HLC_AX_HD_ID = 0 # For Delta Heights
HLC_AX_CHD_ID = 0 # For Heights
HLC_AX_PC_ID = 0  # For Point Cloud

HLC_INSPECTOR = DataInspector(HLC_FIG)

"""
    update_delta_heigts_destribution(r, h)

Updates the Delta Heights Distribution plot (HLC_AX_HD).
Explicitly deletes the previous legend before creating and assigning a new one.
Labels are generated as "Layer N to N+1".

# Arguments
- `r`: Vector of radius values.
- `h`: Vector of height values.
"""
function update_delta_heigts_destribution(r, h)
    global HLC_AX_HD_ID       # Necessary to modify the global variable
    global HLC_AX_HD_LEGEND  # Necessary to access and modify the legend reference

    current_id = HLC_AX_HD_ID
    HLC_AX_HD_ID += 1 # Increment ID for the next call
    current_label = "Layer $(current_id) to $(current_id + 1)"

    scatter!(HLC_AX_HD, r, h, markersize=5, label=current_label)

    # --- Шаг 1: Удаление предыдущей легенды (если она существует) ---
    # Проверяем, есть ли ссылка на легенду и не была ли она уже удалена
    if !isnothing(HLC_AX_HD_LEGEND[]) && HLC_AX_HD_LEGEND[].parent !== nothing
        try
            delete!(HLC_AX_HD_LEGEND[]) # Удаляем объект легенды
            HLC_AX_HD_LEGEND[] = nothing # Сбрасываем ссылку после успешного удаления
        catch e
            @warn "Could not delete previous legend object: $e"
            # Все равно сбрасываем ссылку, чтобы избежать повторных попыток удаления
            HLC_AX_HD_LEGEND[] = nothing
        end
    end
    # -----------------------------------------------------------------
    new_legend = Legend(HLC_FIG, HLC_AX_HD, "ΔLayers") # Создаем новый объект
    HLC_FIG[1, 2] = new_legend # Помещаем новую легенду в ячейку [1, 2]
    HLC_AX_HD_LEGEND[] = new_legend # Обновляем глобальную ссылку

    # Display the Figure
    display(HLC_FIG)
end
"""
    update_heigts_destribution(r, h)

Updates the Heights Distribution plot (HLC_AX_CHD).
Labels are generated as "Layer N".

# Arguments
- `r`: Vector of radius values.
- `h`: Vector of height values.
"""
function update_heigts_destribution(r, h)
    global HLC_AX_CHD_ID # Necessary to modify the global variable
    global HLC_AX_CHD_LEGEND
    HLC_AX_CHD_ID += 1 # Increment ID before use (start with Layer 1)
    current_label = "Layer $(HLC_AX_CHD_ID)"
    scatter!(HLC_AX_CHD, r, h, markersize=5, label=current_label)
    # Consider adding a legend update here too, similar to the delta heights plot, if desired
    # Example:
    # HLC_FIG[2, 2] = Legend(HLC_FIG, HLC_AX_CHD, "Layers")
    if !isnothing(HLC_AX_CHD_LEGEND[]) && HLC_AX_CHD_LEGEND[].parent !== nothing
        try
            delete!(HLC_AX_CHD_LEGEND[]) # Удаляем объект легенды
            HLC_AX_CHD_LEGEND[] = nothing # Сбрасываем ссылку после успешного удаления
        catch e
            @warn "Could not delete previous legend object: $e"
            # Все равно сбрасываем ссылку, чтобы избежать повторных попыток удаления
            HLC_AX_CHD_LEGEND[] = nothing
        end
    end
    new_legend = Legend(HLC_FIG, HLC_AX_CHD, "Layers") # Создаем новый объект
    HLC_FIG[2, 2] = new_legend # Помещаем новую легенду в ячейку [1, 2]
    HLC_AX_CHD_LEGEND[] = new_legend # Обновляем глобальную ссылку

    display(HLC_FIG)
end

"""
    update_cloud_points(points)

Updates the 3D point cloud plot (HLC_AX_PC).
Labels are generated as "Points N".

# Arguments
- `points`: Vector of points with `.x`, `.y`, `.z` fields.
"""
function update_cloud_points(points)
    global HLC_AX_PC_ID # Necessary to modify the global variable
    global HLC_AX_PC_LEGEND
    # Check if the points array is empty
    if isempty(points)
        @warn "The 'points' array is empty in the update_cloud_points function"
        return
    end

    HLC_AX_PC_ID += 1 # Increment ID before use (start with Points 1)
    current_label = "Points $(HLC_AX_PC_ID)"

    # Extract x, y, z coordinates
    x = [p.x for p in points]
    y = [p.y for p in points]
    z = [p.z for p in points]

    # Add points to the 3D Axis
    scatter!(HLC_AX_PC, x, y, z, markersize=1, label=current_label)

    # Consider adding a legend update here too, similar to the delta heights plot, if desired
    # Example:
    # HLC_FIG[3, 2] = Legend(HLC_FIG, HLC_AX_PC, "Layers")
    if !isnothing(HLC_AX_PC_LEGEND[]) && HLC_AX_PC_LEGEND[].parent !== nothing
        try
            delete!(HLC_AX_PC_LEGEND[]) # Удаляем объект легенды
            HLC_AX_PC_LEGEND[] = nothing # Сбрасываем ссылку после успешного удаления
        catch e
            @warn "Could not delete previous legend object: $e"
            # Все равно сбрасываем ссылку, чтобы избежать повторных попыток удаления
            HLC_AX_PC_LEGEND[] = nothing
        end
    end
    new_legend = Legend(HLC_FIG, HLC_AX_PC, "Points") # Создаем новый объект
    HLC_FIG[3, 2] = new_legend # Помещаем новую легенду в ячейку [1, 2]
    HLC_AX_PC_LEGEND[] = new_legend # Обновляем глобальную ссылку

    # Display the Figure
    display(HLC_FIG)
end

"""
    update_plane(points)

Updates the 3D point cloud plot (HLC_AX_PC).
Labels are generated as "Points N".

# Arguments
- `points`: Vector of points with `.x`, `.y`, `.z` fields.
"""
function update_plane(points)
    global HLC_AX_PC_ID # Necessary to modify the global variable
    global HLC_AX_PC_LEGEND
    # Check if the points array is empty
    if isempty(points)
        @warn "The 'points' array is empty in the update_cloud_points function"
        return
    end

    HLC_AX_PC_ID += 1 # Increment ID before use (start with Points 1)
    current_label = "Points $(HLC_AX_PC_ID)"

    # Extract x, y, z coordinates
    x = [p.x for p in points]
    y = [p.y for p in points]
    z = [p.z for p in points]

    # Add points to the 3D Axis
    scatter!(HLC_AX_PC, x, y, z, markersize=1, color=:red, label=current_label)

    # Consider adding a legend update here too, similar to the delta heights plot, if desired
    # Example:
    # HLC_FIG[3, 2] = Legend(HLC_FIG, HLC_AX_PC, "Layers")
    if !isnothing(HLC_AX_PC_LEGEND[]) && HLC_AX_PC_LEGEND[].parent !== nothing
        try
            delete!(HLC_AX_PC_LEGEND[]) # Удаляем объект легенды
            HLC_AX_PC_LEGEND[] = nothing # Сбрасываем ссылку после успешного удаления
        catch e
            @warn "Could not delete previous legend object: $e"
            # Все равно сбрасываем ссылку, чтобы избежать повторных попыток удаления
            HLC_AX_PC_LEGEND[] = nothing
        end
    end
    new_legend = Legend(HLC_FIG, HLC_AX_PC, "Points") # Создаем новый объект
    HLC_FIG[3, 2] = new_legend # Помещаем новую легенду в ячейку [1, 2]
    HLC_AX_PC_LEGEND[] = new_legend # Обновляем глобальную ссылку

    # Display the Figure
    display(HLC_FIG)
end

end # --- End of your Plot module ---