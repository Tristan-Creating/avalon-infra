-- Avalon University — operational (OLTP) schema
-- Normalised model behind the intranet: faculties, programs, people, courses, enrollments.

CREATE SCHEMA IF NOT EXISTS app;

CREATE TABLE app.faculties (
    faculty_id   SERIAL PRIMARY KEY,
    code         TEXT NOT NULL UNIQUE,          -- e.g. 'SCI'
    name         TEXT NOT NULL UNIQUE
);

CREATE TABLE app.programs (
    program_id     SERIAL PRIMARY KEY,
    faculty_id     INT  NOT NULL REFERENCES app.faculties(faculty_id),
    name           TEXT NOT NULL,
    level          TEXT NOT NULL CHECK (level IN ('bachelor', 'master')),
    duration_years INT  NOT NULL CHECK (duration_years BETWEEN 1 AND 5),
    UNIQUE (faculty_id, name)
);

CREATE TABLE app.teachers (
    teacher_id  SERIAL PRIMARY KEY,
    faculty_id  INT  NOT NULL REFERENCES app.faculties(faculty_id),
    first_name  TEXT NOT NULL,
    last_name   TEXT NOT NULL,
    email       TEXT NOT NULL UNIQUE
);

CREATE TABLE app.students (
    student_id      SERIAL PRIMARY KEY,
    program_id      INT  NOT NULL REFERENCES app.programs(program_id),
    first_name      TEXT NOT NULL,
    last_name       TEXT NOT NULL,
    email           TEXT NOT NULL UNIQUE,
    enrollment_year INT  NOT NULL,              -- first academic year at Avalon
    status          TEXT NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'graduated', 'withdrawn'))
);

CREATE TABLE app.courses (
    course_id   SERIAL PRIMARY KEY,
    faculty_id  INT  NOT NULL REFERENCES app.faculties(faculty_id),
    teacher_id  INT  NOT NULL REFERENCES app.teachers(teacher_id),
    code        TEXT NOT NULL UNIQUE,           -- e.g. 'SCI-301'
    title       TEXT NOT NULL,
    level       TEXT NOT NULL CHECK (level IN ('bachelor', 'master')),
    semester    TEXT NOT NULL CHECK (semester IN ('S1', 'S2')),
    ects        INT  NOT NULL CHECK (ects BETWEEN 2 AND 10),
    capacity    INT  NOT NULL CHECK (capacity > 0)
);

CREATE TABLE app.enrollments (
    enrollment_id  BIGSERIAL PRIMARY KEY,
    student_id     INT  NOT NULL REFERENCES app.students(student_id),
    course_id      INT  NOT NULL REFERENCES app.courses(course_id),
    academic_year  INT  NOT NULL,               -- 2024 means 2024-2025
    enrolled_at    TIMESTAMPTZ NOT NULL,
    grade          NUMERIC(4,2) CHECK (grade BETWEEN 0 AND 20),  -- French scale; NULL until graded
    status         TEXT NOT NULL DEFAULT 'in_progress'
                   CHECK (status IN ('in_progress', 'completed', 'failed', 'dropped')),
    UNIQUE (student_id, course_id, academic_year)
);

CREATE INDEX idx_enrollments_student ON app.enrollments(student_id);
CREATE INDEX idx_enrollments_course  ON app.enrollments(course_id);
CREATE INDEX idx_enrollments_year    ON app.enrollments(academic_year);
CREATE INDEX idx_students_program    ON app.students(program_id);
CREATE INDEX idx_courses_faculty     ON app.courses(faculty_id);
