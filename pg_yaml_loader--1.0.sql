-- pg_yaml_loader--1.0.sql
-- Extension for advanced YAML processing in PostgreSQL
-- Author: [Ваше Имя]

\echo Use "CREATE EXTENSION pg_yaml_loader" to load this file. \quit

-- Тип для плоского представления YAML (ключ-значение)
CREATE TYPE yaml_kv_pair AS (
    key_path TEXT,
    val_text TEXT,
    val_type TEXT,
    depth INTEGER
);

-- Тип для метаданных файла
CREATE TYPE yaml_file_info AS (
    file_name TEXT,
    file_size_bytes BIGINT,
    last_modified TIMESTAMP,
    is_valid_yaml BOOLEAN
);

-- Основная функция парсинга (PL/Python)
CREATE OR REPLACE FUNCTION yaml_parse_full(file_path TEXT)
RETURNS SETOF yaml_kv_pair
AS $$
    import yaml
    import os

    if not os.path.exists(file_path):
        plpy.error(f"YAML Loader Error: File not found at {file_path}")

    def flatten_node(data, prefix='', depth=0):
        """
        Рекурсивный обход дерева YAML (алгоритм DFS).
        Преобразует вложенную структуру в плоский список для SQL.
        """
        items = []
        if isinstance(data, dict):
            for k, v in data.items():
                new_key = f"{prefix}.{k}" if prefix else str(k)
                items.extend(flatten_node(v, new_key, depth + 1))
        elif isinstance(data, list):
            for i, v in enumerate(data):
                new_key = f"{prefix}[{i}]"
                items.extend(flatten_node(v, new_key, depth + 1))
        else:
            # Базовый случай: записываем значение и его тип
            items.append((prefix, str(data), type(data).__name__, depth))
        return items

    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            # Используем SafeLoader для безопасности
            content = yaml.safe_load(f)
            if content is None:
                return []

            flat_data = flatten_node(content)
            for row in flat_data:
                yield row
    except yaml.YAMLError as exc:
        plpy.error(f"YAML Syntax Error: {str(exc)}")
    except Exception as e:
        plpy.error(f"Unexpected error: {str(e)}")
$$ LANGUAGE plpython3u;

-- Функция получения метаданных файла
CREATE OR REPLACE FUNCTION yaml_get_file_info(file_path TEXT)
RETURNS yaml_file_info
AS $$
    import os
    import yaml
    from datetime import datetime

    try:
        stat = os.stat(file_path)
        with open(file_path, 'r') as f:
            yaml.safe_load(f)
            valid = True
    except:
        valid = False

    return (
        os.path.basename(file_path),
        stat.st_size,
        datetime.fromtimestamp(stat.st_mtime),
        valid
    )
$$ LANGUAGE plpython3u;

-- Функция конвертации в JSONB (удобно для нативного поиска в PG)
CREATE OR REPLACE FUNCTION yaml_as_jsonb(yaml_text TEXT)
RETURNS JSONB
AS $$
    import yaml
    import json
    try:
        data = yaml.safe_load(yaml_text)
        return json.dumps(data)
    except Exception as e:
        plpy.error(f"YAML to JSONB conversion failed: {str(e)}")
$$ LANGUAGE plpython3u;

-- Процедура для автоматизированного импорта
CREATE OR REPLACE PROCEDURE import_yaml_config(
    p_table_name TEXT,
    p_file_path TEXT,
    p_drop_existing BOOLEAN DEFAULT FALSE
)
LANGUAGE plpgsql
AS $proc$
DECLARE
    v_count INTEGER;
BEGIN
    IF p_drop_existing THEN
        EXECUTE format('DROP TABLE IF EXISTS %I', p_table_name);
    END IF;

    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %I (
            id SERIAL PRIMARY KEY,
            property_path TEXT,
            property_value TEXT,
            data_type TEXT,
            nesting_level INTEGER,
            imported_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )', p_table_name);

    EXECUTE format('
        INSERT INTO %I (property_path, property_value, data_type, nesting_level)
        SELECT key_path, val_text, val_type, depth FROM yaml_parse_full(%L)',
        p_table_name, p_file_path);

    GET DIAGNOSTICS v_count = ROW_COUNT;
    RAISE NOTICE 'Успешно импортировано % записей в таблицу %', v_count, p_table_name;
END;
$proc$;

-- Вспомогательное представление для анализа типов данных в YAML
CREATE OR REPLACE FUNCTION yaml_stats(file_path TEXT)
RETURNS TABLE (
    key_path TEXT,
    val_text TEXT,
    val_type TEXT,
    depth INT
) AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM yaml_parse_full(file_path);
END;
$$ LANGUAGE plpgsql;