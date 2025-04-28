# --- Необходимые пакеты ---
using LinearAlgebra      # Для norm
using NearestNeighbors   # Для KDTree, knn, inrange
using StaticArrays     # Для SVector (более эффективные векторы для координат)

# Предполагается, что функции find_pairs_within_threshold, get_svector, distance
# и структура Point3D определены, как в предыдущих примерах.
# Нам не нужны здесь DataStructures или PyCall.

"""
    select_best_unique_pairs(candidate_pairs::Vector{Tuple{Int, Int, Float64}}) -> Vector{Tuple{Int, Int, Float64}}

Выбирает из списка пар-кандидатов "лучшие" уникальные пары.
"Лучшие" означает пары с минимальным расстоянием в первую очередь.
Каждый индекс из первого и второго исходных наборов точек может быть
использован не более чем в одной итоговой паре. Использует жадный подход.

Аргументы:
- `candidate_pairs`: Вектор кортежей вида `(индекс1, индекс2, расстояние)`,
                     обычно результат работы `find_pairs_within_threshold`.

Возвращает:
- Вектор кортежей `(индекс1, индекс2, расстояние)` выбранных уникальных пар,
  упорядоченный по возрастанию расстояния.
"""
function select_best_unique_pairs(candidate_pairs::Vector{Tuple{Int, Int, Float64}})

    if isempty(candidate_pairs)
        return Tuple{Int, Int, Float64}[]
    end

    # 1. Сортируем пары-кандидаты по расстоянию (3-й элемент кортежа)
    # sort создает новый отсортированный массив
    sorted_candidates = sort(candidate_pairs, by = pair -> pair[3])

    # 2. Множества для отслеживания использованных индексов
    used_indices1 = Set{Int}() # Индексы из первого исходного вектора (fp2)
    used_indices2 = Set{Int}() # Индексы из второго исходного вектора (fp3)
    selected_pairs = Vector{Tuple{Int, Int, Float64}}()
    # Оптимизация: предполагаем максимальный размер результата
    sizehint!(selected_pairs, length(sorted_candidates))

    # 3. Жадный выбор по отсортированным кандидатам
    for (idx1, idx2, dist) in sorted_candidates
        # 4. Проверка, свободны ли оба индекса
        if !(idx1 in used_indices1 || idx2 in used_indices2)
            # 5. Выбираем пару и помечаем индексы
            push!(selected_pairs, (idx1, idx2, dist))
            push!(used_indices1, idx1)
            push!(used_indices2, idx2)
        end
        # Если хотя бы один индекс занят, пропускаем эту пару
    end

    # 6. Возвращаем результат
    return selected_pairs
end

function visualize_best_pairs(pairs::Vector{Tuple{Int, Int, Float64}}, points1::Vector, points2::Vector)
    # Makie, GLMakie
    fig = Figure()
    ax = Axis3(fig[1, 1], title = "Best Unique Pairs")
    # Отображаем точки из первого набора
    scatter!(ax, [get_svector(p) for p in points1], color = :blue, label = "Points 1")
    # Отображаем точки из второго набора
    scatter!(ax, [get_svector(p) for p in points2], color = :red, label = "Points 2")
    # Отображаем линии между парами
    for (idx1, idx2, dist) in pairs
        p1 = get_svector(points1[idx1])
        p2 = get_svector(points2[idx2])
        lines!(ax, [p1[1], p2[1]], [p1[2], p2[2]], color = :green, label = "Pair $(idx1)-$(idx2)")
    end

    display(fig)
end

# --- Пример использования ---

# Допустим, find_pairs_within_threshold(fp2, fp3, 10.0) вернула такой список:
# (индекс_в_fp2, индекс_в_fp3, расстояние)
candidate_pairs_example = [
    (2, 3, 0.8),
    (1, 5, 0.5),  # Реально мин расстояние
    (3, 3, 1.5),  # Конфликт по индексу 3 из fp3
    (1, 2, 1.1),  # Конфликт по индексу 1 из fp2
    (4, 1, 1.8),
    (2, 6, 2.0)   # Конфликт по индексу 2 из fp2
]

println("Входные пары-кандидаты (не отсортированные):")
display(candidate_pairs_example)

println("\nВыбор лучших уникальных пар...")
best_unique_pairs = select_best_unique_pairs(candidate_pairs_example)

println("\nВыбранные уникальные пары (отсортированы по расстоянию):")
if isempty(best_unique_pairs)
    println("Уникальные пары не найдены.")
else
    for pair_info in best_unique_pairs
        idx1, idx2, dist = pair_info
        println("  ($idx1, $idx2, $(round(dist, digits=3)))")
    end
end

# Ожидаемый результат:
# Сначала сортировка даст: (1,5,0.5), (2,3,0.8), (1,2,1.1), (3,3,1.5), (4,1,1.8), (2,6,2.0)
# 1. Берем (1, 5, 0.5). Используем idx1=1, idx2=5. Результат: [(1, 5, 0.5)]
# 2. Берем (2, 3, 0.8). Используем idx1=2, idx2=3. Результат: [(1, 5, 0.5), (2, 3, 0.8)]
# 3. Берем (1, 2, 1.1). Пропускаем, т.к. idx1=1 уже использован.
# 4. Берем (3, 3, 1.5). Пропускаем, т.к. idx2=3 уже использован.
# 5. Берем (4, 1, 1.8). Используем idx1=4, idx2=1. Результат: [(1, 5, 0.5), (2, 3, 0.8), (4, 1, 1.8)]
# 6. Берем (2, 6, 2.0). Пропускаем, т.к. idx1=2 уже использован.
# Итог: [(1, 5, 0.5), (2, 3, 0.8), (4, 1, 1.8)]

# --- Вспомогательные функции ---
# Адаптируем get_xyz для возврата SVector для эффективности с NearestNeighbors
function get_svector(p)::SVector{3, Float64}
    try; return SVector{3, Float64}(p.x, p.y, p.z); catch; end
    try; return SVector{3, Float64}(p[1], p[2], p[3]); catch; end
    error("Не удалось извлечь x, y, z из точки: $p.")
end

# Функция для преобразования вектора точек в матрицу (точки по столбцам)
function points_to_matrix(points::Vector)::Matrix{Float64}
    if isempty(points)
        return Matrix{Float64}(undef, 3, 0)
    end
    # Собираем SVector'ы и используем hcat для создания матрицы
    svectors = [get_svector(p) for p in points]
    return hcat(svectors...) # Каждый SVector становится столбцом
end

# Вычисление расстояния (можно использовать norm)
distance(p1, p2) = norm(get_svector(p1) - get_svector(p2))

"""
    find_pairs_within_threshold(points1::Vector, points2::Vector, threshold::Float64) -> Vector{Tuple{Int, Int, Float64}}

Находит все пары точек (индекс из points1, индекс из points2),
расстояние между которыми меньше или равно `threshold`.
Использует `NearestNeighbors.jl` для эффективности.
"""
function find_pairs_within_threshold(points1::Vector, points2::Vector, threshold::Float64)
    n1 = length(points1)
    n2 = length(points2)
    if n1 == 0 || n2 == 0 || threshold < 0
        return Tuple{Int, Int, Float64}[]
    end

    data2 = points_to_matrix(points2)
    if isempty(data2) # Проверка после преобразования
        return Tuple{Int, Int, Float64}[]
    end

    # Строим KD-дерево для второго набора точек
    kdtree = KDTree(data2)

    close_pairs = Vector{Tuple{Int, Int, Float64}}()

    # Ищем соседей в радиусе для каждой точки из первого набора
    for i in 1:n1
        p1_vec = get_svector(points1[i])
        # inrange возвращает индексы точек из data2 (т.е. points2)
        indices_in_range = inrange(kdtree, p1_vec, threshold)

        for j in indices_in_range
            # Вычисляем точное расстояние для найденных пар
            dist = distance(points1[i], points2[j])
            # Дополнительная проверка (inrange может быть чуть неточной на границах)
            if dist <= threshold
                push!(close_pairs, (i, j, dist))
            end
        end
    end

    return close_pairs
end


# --- Пример использования ---
println("--- Пример Алгоритмов Поиска Близких Пар ---")
struct Point3D; x::Float64; y::Float64; z::Float64; end
pts1 = [Point3D(0,0,0), Point3D(5,5,5), Point3D(10,0,0)]
pts2 = [Point3D(0.5,0.5,0.5), Point3D(4.9,4.9,4.9), Point3D(15,0,0), Point3D(5.5, 5.5, 5.5)]

# 1. Поиск в радиусе
threshold = 1.0
println("\nПоиск пар с расстоянием <= $threshold:")
pairs_in_threshold = find_pairs_within_threshold(pts1, pts2, threshold)
if isempty(pairs_in_threshold)
    println("Пар не найдено.")
else
    println("Найденные пары (индекс1, индекс2, расстояние):")
    for p in pairs_in_threshold
        println("  ($(p[1]), $(p[2]), $(round(p[3], digits=3))) | p1: $(pts1[p[1]]) <-> p2: $(pts2[p[2]])")
    end
end

