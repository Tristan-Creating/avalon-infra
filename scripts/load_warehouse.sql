-- ELT: full reload of the star schema from the app schema.
-- Idempotent: truncates and rebuilds. Run after (re)seeding:
--   psql $DSN -f load_warehouse.sql

BEGIN;

TRUNCATE warehouse.fact_enrollments, warehouse.dim_student, warehouse.dim_course, warehouse.dim_date;

-- dim_date: every day covering the enrollment span (with margin)
INSERT INTO warehouse.dim_date (date_key, full_date, year, month, day, academic_year, semester)
SELECT
    (EXTRACT(YEAR FROM d)::INT * 10000 + EXTRACT(MONTH FROM d)::INT * 100 + EXTRACT(DAY FROM d)::INT),
    d::DATE,
    EXTRACT(YEAR FROM d)::INT,
    EXTRACT(MONTH FROM d)::INT,
    EXTRACT(DAY FROM d)::INT,
    CASE WHEN EXTRACT(MONTH FROM d) >= 9 THEN EXTRACT(YEAR FROM d)::INT ELSE EXTRACT(YEAR FROM d)::INT - 1 END,
    CASE WHEN EXTRACT(MONTH FROM d) >= 9 OR EXTRACT(MONTH FROM d) = 1 THEN 'S1' ELSE 'S2' END
FROM generate_series(
    (SELECT MIN(enrolled_at)::DATE - INTERVAL '30 days' FROM app.enrollments),
    (SELECT MAX(enrolled_at)::DATE + INTERVAL '365 days' FROM app.enrollments),
    INTERVAL '1 day'
) AS d;

INSERT INTO warehouse.dim_student (student_key, student_id, full_name, program, program_level, faculty, enrollment_year, status)
SELECT
    s.student_id, s.student_id,
    s.first_name || ' ' || s.last_name,
    p.name, p.level, f.name,
    s.enrollment_year, s.status
FROM app.students s
JOIN app.programs  p ON p.program_id = s.program_id
JOIN app.faculties f ON f.faculty_id = p.faculty_id;

INSERT INTO warehouse.dim_course (course_key, course_id, code, title, faculty, level, semester, ects, teacher)
SELECT
    c.course_id, c.course_id, c.code, c.title,
    f.name, c.level, c.semester, c.ects,
    t.first_name || ' ' || t.last_name
FROM app.courses c
JOIN app.faculties f ON f.faculty_id = c.faculty_id
JOIN app.teachers  t ON t.teacher_id = c.teacher_id;

INSERT INTO warehouse.fact_enrollments
    (enrollment_key, date_key, student_key, course_key, academic_year, grade, ects_attempted, ects_earned, status)
SELECT
    e.enrollment_id,
    (EXTRACT(YEAR FROM e.enrolled_at)::INT * 10000 + EXTRACT(MONTH FROM e.enrolled_at)::INT * 100 + EXTRACT(DAY FROM e.enrolled_at)::INT),
    e.student_id,
    e.course_id,
    e.academic_year,
    e.grade,
    c.ects,
    CASE WHEN e.status = 'completed' THEN c.ects ELSE 0 END,
    e.status
FROM app.enrollments e
JOIN app.courses c ON c.course_id = e.course_id;

COMMIT;

-- quick sanity report
SELECT 'dim_date' AS t, COUNT(*) FROM warehouse.dim_date
UNION ALL SELECT 'dim_student', COUNT(*) FROM warehouse.dim_student
UNION ALL SELECT 'dim_course', COUNT(*) FROM warehouse.dim_course
UNION ALL SELECT 'fact_enrollments', COUNT(*) FROM warehouse.fact_enrollments;
