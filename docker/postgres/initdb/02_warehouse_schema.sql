-- Avalon University — analytical star schema
-- One fact (enrollments) surrounded by conformed dimensions.
-- Loaded from the app schema by scripts/load_warehouse.sql (ELT).

CREATE SCHEMA IF NOT EXISTS warehouse;

CREATE TABLE warehouse.dim_date (
    date_key      INT PRIMARY KEY,              -- YYYYMMDD
    full_date     DATE NOT NULL UNIQUE,
    year          INT  NOT NULL,
    month         INT  NOT NULL,
    day           INT  NOT NULL,
    academic_year INT  NOT NULL,                -- Sep-Aug; 2024 means 2024-2025
    semester      TEXT NOT NULL                 -- S1 (Sep-Jan) / S2 (Feb-Aug)
);

CREATE TABLE warehouse.dim_student (
    student_key     INT PRIMARY KEY,            -- surrogate = app student_id (full reload)
    student_id      INT  NOT NULL,
    full_name       TEXT NOT NULL,
    program         TEXT NOT NULL,
    program_level   TEXT NOT NULL,
    faculty         TEXT NOT NULL,
    enrollment_year INT  NOT NULL,
    status          TEXT NOT NULL
);

CREATE TABLE warehouse.dim_course (
    course_key  INT PRIMARY KEY,                -- surrogate = app course_id (full reload)
    course_id   INT  NOT NULL,
    code        TEXT NOT NULL,
    title       TEXT NOT NULL,
    faculty     TEXT NOT NULL,
    level       TEXT NOT NULL,
    semester    TEXT NOT NULL,
    ects        INT  NOT NULL,
    teacher     TEXT NOT NULL
);

CREATE TABLE warehouse.fact_enrollments (
    enrollment_key BIGINT PRIMARY KEY,          -- surrogate = app enrollment_id (full reload)
    date_key       INT    NOT NULL REFERENCES warehouse.dim_date(date_key),
    student_key    INT    NOT NULL REFERENCES warehouse.dim_student(student_key),
    course_key     INT    NOT NULL REFERENCES warehouse.dim_course(course_key),
    academic_year  INT    NOT NULL,
    grade          NUMERIC(4,2),
    ects_attempted INT    NOT NULL,
    ects_earned    INT    NOT NULL,             -- = ects_attempted when completed, else 0
    status         TEXT   NOT NULL
);

CREATE INDEX idx_fact_enr_date    ON warehouse.fact_enrollments(date_key);
CREATE INDEX idx_fact_enr_student ON warehouse.fact_enrollments(student_key);
CREATE INDEX idx_fact_enr_course  ON warehouse.fact_enrollments(course_key);
