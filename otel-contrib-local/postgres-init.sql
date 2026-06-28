CREATE USER otelu WITH PASSWORD 'otelp';
GRANT SELECT ON pg_stat_database TO otelu;
GRANT pg_monitor TO otelu;

CREATE TABLE table1 (
    id serial PRIMARY KEY
);

CREATE TABLE table2 (
    id serial PRIMARY KEY
);

CREATE DATABASE db_staging;
\c db_staging

CREATE TABLE stag1 (
    id serial PRIMARY KEY
);

CREATE TABLE stag2 (
    id serial PRIMARY KEY
);

CREATE INDEX db_staging_stag1_idx ON stag1(id);
CREATE INDEX db_staging_stag2_idx ON stag2(id);

INSERT INTO stag2 (id)
VALUES (67);

SELECT *
FROM stag2;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT SELECT ON stag2 TO otelu;

SET work_mem = '64kB';
SELECT *
FROM generate_series(1, 100000) AS x
ORDER BY x;
SET work_mem = '4MB';

CREATE DATABASE db_prod;
\c db_prod

CREATE TABLE prod1 (
    id serial PRIMARY KEY
);

CREATE TABLE prod2 (
    id serial PRIMARY KEY
);

CREATE INDEX db_prod_prod1_idx ON prod1(id);
CREATE INDEX db_prod_prod2_idx ON prod2(id);

INSERT INTO prod2 (id)
VALUES (101);

SELECT *
FROM prod2;

CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
GRANT SELECT ON prod2 TO otelu;

\c postgres
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
