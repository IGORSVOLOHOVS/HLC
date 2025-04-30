using Printf

"""
Функция для обхода директории и сбора метрик из файлов .jl.
"""
function collect_metrics(src_dir::String)
    total_lines = 0
    blank_lines = 0
    comment_lines = 0
    struct_count = 0  # NC approximation
    function_count = 0 # NOM approximation

    println("Analyzing directory: ", abspath(src_dir))

    files_processed = 0
    files_skipped = 0

    try
        for (root, dirs, files) in walkdir(src_dir)
            for file in files
                if endswith(lowercase(file), ".jl")
                    filepath = joinpath(root, file)
                    files_processed += 1
                    try
                        current_file_comments = 0
                        lines = readlines(filepath)
                        total_lines += length(lines)

                        in_multiline_comment = false # Базовое отслеживание многострочных комментариев

                        for line in lines
                            stripped_line = strip(line)

                            # Проверка на пустую строку
                            if isempty(stripped_line)
                                blank_lines += 1
                                continue # Переходим к следующей строке
                            end

                            # Проверка на начало/конец многострочного комментария (упрощенно)
                            if startswith(stripped_line, "#=")
                                in_multiline_comment = true
                                comment_lines += 1 # Считаем строку начала комментария
                                # Если комментарий закрывается на той же строке
                                if endswith(stripped_line, "=#") && length(stripped_line) > 2
                                     in_multiline_comment = false
                                end
                                continue
                            end
                            if endswith(stripped_line, "=#")
                                in_multiline_comment = false
                                comment_lines += 1 # Считаем строку конца комментария
                                continue
                            end
                            if in_multiline_comment
                                comment_lines += 1
                                continue
                            end

                            # Проверка на однострочный комментарий
                            if startswith(stripped_line, "#") && !startswith(stripped_line, "#=") # Исключаем начало многострочного
                                comment_lines += 1
                                current_file_comments += 1
                                continue # Переходим к следующей строке
                            end

                            # Проверка на определение структуры (упрощенно)
                            if occursin(r"^\s*(mutable\s+)?struct\s+", stripped_line)
                                struct_count += 1
                            end

                            # Проверка на определение функции (упрощенно)
                            if occursin(r"^\s*function\s+", stripped_line)
                                function_count += 1
                            end
                        end # end line loop

                    catch e
                        println("Error reading file $filepath: $e")
                        files_skipped += 1
                    end
                end # end if .jl
            end # end file loop
        end # end walkdir

        code_lines = total_lines - blank_lines - comment_lines

        println("\n--- Basic Code Metrics ---")
        @printf "Total files processed: %d\n" files_processed
        if files_skipped > 0
             @printf "Total files skipped due to errors: %d\n" files_skipped
        end
        println("-"^25)
        @printf "Total Lines (TLOC):      %d\n" total_lines
        @printf "Blank Lines:             %d\n" blank_lines
        @printf "Comment Lines (approx.): %d\n" comment_lines
        @printf "Code Lines (approx.):    %d\n" code_lines
        println("-"^25)
        @printf "Struct Count (NC approx.):    %d\n" struct_count
        @printf "Function Count (NOM approx.): %d\n" function_count
        println("-"^25)
        println("NOC (Number of Children):  0 (assuming no struct inheritance)")
        println("DIT (Depth of Inheritance): 0 (assuming no struct inheritance)")
        println("-"^25)
        println("NOTE: WMC, CBO, RFC, LCOM metrics require more advanced")
        println("      static analysis tools (e.g., SciTools Understand)")
        println("      and cannot be reliably calculated by this script.")
        println("--------------------------")

    catch e
         println("Error walking directory $src_dir: $e")
    end
end

# --- Запуск анализа ---
# Укажите путь к вашей папке src относительно места запуска скрипта
# или укажите абсолютный путь
source_directory = "src" # Можно заменить на "C:\\path\\to\\your\\project\\src"

if !isdir(source_directory)
    println("Error: Directory '$source_directory' not found.")
    println("Please ensure the script is run from the project root or update the 'source_directory' variable.")
else
    collect_metrics(source_directory)
end