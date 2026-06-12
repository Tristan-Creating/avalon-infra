#!/usr/bin/env python3
"""Synthetic data generator for Avalon University.

Seeds the app schema (faculties, programs, teachers, students, courses,
enrollments) with deterministic, believable data:

- students enroll mostly inside their own faculty (electives cross over),
- course levels match the student's program level,
- past academic years are graded on the French 0-20 scale, the current
  year is in progress,
- everything is reproducible from --seed.

This is the shared dataset for all blocks: Block 2 seeds the database,
Block 3 replays enrollments through Kafka, Block 4 trains the course
recommender on it.

Usage:
    python generate_data.py --dsn postgresql://avalon:...@localhost:5432/avalon
    python generate_data.py --students 5000 --years 3 --seed 42
"""

import argparse
import random
import sys
from datetime import date, datetime, timedelta, timezone

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    sys.exit("psycopg2 is required: pip install -r requirements.txt")

try:
    from faker import Faker
except ImportError:
    sys.exit("faker is required: pip install -r requirements.txt")

CURRENT_ACADEMIC_YEAR = 2025  # 2025-2026

FACULTIES = [
    ("ART", "Arts & Humanities"),
    ("SCI", "Science & Engineering"),
    ("MED", "Medicine & Health"),
    ("BUS", "Business"),
    ("LAW", "Law"),
]

PROGRAMS = {
    "ART": [("History & Heritage", "bachelor", 3), ("Modern Literature", "bachelor", 3), ("Cultural Studies", "master", 2)],
    "SCI": [("Computer Science", "bachelor", 3), ("Applied Mathematics", "bachelor", 3), ("Data Science & AI", "master", 2)],
    "MED": [("Health Sciences", "bachelor", 3), ("Public Health", "master", 2), ("Biomedical Research", "master", 2)],
    "BUS": [("Management", "bachelor", 3), ("Finance", "bachelor", 3), ("International Business", "master", 2)],
    "LAW": [("French Law", "bachelor", 3), ("European Law", "master", 2), ("Business Law", "master", 2)],
}

COURSE_TOPICS = {
    "ART": ["Medieval Europe", "Art History", "French Poetry", "Philosophy", "Linguistics", "Archaeology", "World Cinema", "Critical Theory"],
    "SCI": ["Algorithms", "Databases", "Linear Algebra", "Statistics", "Machine Learning", "Physics", "Distributed Systems", "Numerical Methods"],
    "MED": ["Anatomy", "Epidemiology", "Biochemistry", "Health Policy", "Clinical Methods", "Neuroscience", "Pharmacology", "Medical Ethics"],
    "BUS": ["Accounting", "Marketing", "Corporate Finance", "Microeconomics", "Strategy", "Negotiation", "Supply Chains", "Entrepreneurship"],
    "LAW": ["Constitutional Law", "Contract Law", "EU Institutions", "Criminal Law", "Tax Law", "Data Protection Law", "Labour Law", "International Law"],
}

COURSE_QUALIFIERS = ["Introduction to", "Foundations of", "Advanced", "Seminar:", "Applied", "Topics in"]


def build_catalog(fake, rng):
    """Faculties, programs, teachers and courses as in-memory rows."""
    faculties = [{"faculty_id": i + 1, "code": c, "name": n} for i, (c, n) in enumerate(FACULTIES)]

    programs, teachers, courses = [], [], []
    pid = tid = cid = 0
    for fac in faculties:
        for name, level, years in PROGRAMS[fac["code"]]:
            pid += 1
            programs.append({"program_id": pid, "faculty_id": fac["faculty_id"], "name": name, "level": level, "duration_years": years})

        fac_teachers = []
        for _ in range(8):
            tid += 1
            first, last = fake.first_name(), fake.last_name()
            t = {"teacher_id": tid, "faculty_id": fac["faculty_id"], "first_name": first, "last_name": last,
                 "email": f"{first}.{last}.t{tid}@avalon-university.fr".lower().replace(" ", "-")}
            teachers.append(t)
            fac_teachers.append(t)

        used_titles = set()
        for level in ("bachelor", "master"):
            n_courses = 24 if level == "bachelor" else 16
            for _ in range(n_courses):
                cid += 1
                while True:
                    title = f"{rng.choice(COURSE_QUALIFIERS)} {rng.choice(COURSE_TOPICS[fac['code']])}"
                    if title not in used_titles:
                        used_titles.add(title)
                        break
                courses.append({
                    "course_id": cid,
                    "faculty_id": fac["faculty_id"],
                    "teacher_id": rng.choice(fac_teachers)["teacher_id"],
                    "code": f"{fac['code']}-{100 if level == 'bachelor' else 500 + cid % 100:03d}-{cid}",
                    "title": title,
                    "level": level,
                    "semester": rng.choice(["S1", "S2"]),
                    "ects": rng.choice([2, 3, 4, 5, 6]),
                    "capacity": rng.choice([30, 60, 90, 120, 200]),
                })
    return faculties, programs, teachers, courses


def build_students(fake, rng, programs, n_students, n_years):
    students = []
    for sid in range(1, n_students + 1):
        program = rng.choice(programs)
        first, last = fake.first_name(), fake.last_name()
        start = CURRENT_ACADEMIC_YEAR - rng.randint(0, n_years - 1)
        finished = start + program["duration_years"] <= CURRENT_ACADEMIC_YEAR
        status = "graduated" if finished else ("withdrawn" if rng.random() < 0.03 else "active")
        students.append({
            "student_id": sid,
            "program_id": program["program_id"],
            "first_name": first,
            "last_name": last,
            "email": f"{first}.{last}.{sid}@avalon-university.fr".lower().replace(" ", "-"),
            "enrollment_year": start,
            "status": status,
            "_program": program,
        })
    return students


def build_enrollments(rng, students, programs, courses, faculties_by_id):
    """Per student, per attended academic year: ~8-12 courses, faculty-biased."""
    by_faculty_level = {}
    for c in courses:
        by_faculty_level.setdefault((c["faculty_id"], c["level"]), []).append(c)
    all_by_level = {}
    for c in courses:
        all_by_level.setdefault(c["level"], []).append(c)

    enrollments, eid = [], 0
    for s in students:
        program = s["_program"]
        last_year = min(CURRENT_ACADEMIC_YEAR, s["enrollment_year"] + program["duration_years"] - 1)
        for year in range(s["enrollment_year"], last_year + 1):
            if s["status"] == "withdrawn" and year > s["enrollment_year"]:
                break
            own = by_faculty_level[(program["faculty_id"], program["level"])]
            pool_other = [c for c in all_by_level[program["level"]] if c["faculty_id"] != program["faculty_id"]]
            n = rng.randint(8, 12)
            n_own = max(1, round(n * 0.8))
            picked = rng.sample(own, min(n_own, len(own))) + rng.sample(pool_other, min(n - n_own, len(pool_other)))

            for course in picked:
                eid += 1
                # enrollment happens at the start of the course's semester
                month, day = (9, rng.randint(1, 25)) if course["semester"] == "S1" else (2, rng.randint(1, 25))
                cal_year = year if course["semester"] == "S1" else year + 1
                enrolled_at = datetime(cal_year, month, day, rng.randint(8, 18), rng.randint(0, 59), tzinfo=timezone.utc)

                if year < CURRENT_ACADEMIC_YEAR:
                    if rng.random() < 0.04:
                        grade, status = None, "dropped"
                    else:
                        grade = round(min(20.0, max(0.0, rng.gauss(12.3, 3.4))), 2)
                        status = "completed" if grade >= 10 else "failed"
                else:
                    grade, status = None, "in_progress"

                enrollments.append({
                    "enrollment_id": eid,
                    "student_id": s["student_id"],
                    "course_id": course["course_id"],
                    "academic_year": year,
                    "enrolled_at": enrolled_at,
                    "grade": grade,
                    "status": status,
                })
    return enrollments


def insert_rows(cur, table, rows, columns):
    psycopg2.extras.execute_values(
        cur,
        f"INSERT INTO {table} ({', '.join(columns)}) VALUES %s",
        [[r[c] for c in columns] for r in rows],
        page_size=2000,
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dsn", default="postgresql://avalon:avalon_dev_password@localhost:5432/avalon")
    parser.add_argument("--students", type=int, default=5000)
    parser.add_argument("--years", type=int, default=4, help="how many cohort start years, back from the current year")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--truncate", action="store_true", help="empty the app tables before inserting")
    args = parser.parse_args()

    rng = random.Random(args.seed)
    Faker.seed(args.seed)
    fake = Faker("fr_FR")

    faculties, programs, teachers, courses = build_catalog(fake, rng)
    students = build_students(fake, rng, programs, args.students, args.years)
    faculties_by_id = {f["faculty_id"]: f for f in faculties}
    enrollments = build_enrollments(rng, students, programs, courses, faculties_by_id)

    conn = psycopg2.connect(args.dsn)
    conn.autocommit = False
    with conn, conn.cursor() as cur:
        if args.truncate:
            cur.execute("TRUNCATE app.enrollments, app.students, app.courses, app.teachers, app.programs, app.faculties RESTART IDENTITY CASCADE")

        insert_rows(cur, "app.faculties", faculties, ["faculty_id", "code", "name"])
        insert_rows(cur, "app.programs", programs, ["program_id", "faculty_id", "name", "level", "duration_years"])
        insert_rows(cur, "app.teachers", teachers, ["teacher_id", "faculty_id", "first_name", "last_name", "email"])
        insert_rows(cur, "app.courses", courses, ["course_id", "faculty_id", "teacher_id", "code", "title", "level", "semester", "ects", "capacity"])
        insert_rows(cur, "app.students", students, ["student_id", "program_id", "first_name", "last_name", "email", "enrollment_year", "status"])
        insert_rows(cur, "app.enrollments", enrollments, ["enrollment_id", "student_id", "course_id", "academic_year", "enrolled_at", "grade", "status"])

        # serial sequences must catch up with explicit ids
        for table, col in [("app.faculties", "faculty_id"), ("app.programs", "program_id"), ("app.teachers", "teacher_id"),
                           ("app.courses", "course_id"), ("app.students", "student_id"), ("app.enrollments", "enrollment_id")]:
            cur.execute(f"SELECT setval(pg_get_serial_sequence('{table}', '{col}'), (SELECT MAX({col}) FROM {table}))")
    conn.close()

    print(f"Seeded: {len(faculties)} faculties, {len(programs)} programs, {len(teachers)} teachers, "
          f"{len(courses)} courses, {len(students)} students, {len(enrollments)} enrollments (seed={args.seed})")


if __name__ == "__main__":
    main()
