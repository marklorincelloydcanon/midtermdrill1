"""Make fake HarborWing Air data and write it to seed.sql.

Run:   pip install -r requirements.txt
       python generate_data.py
Same seed = same data every time. All people and places are made up.
"""
import random
from datetime import date, datetime, timedelta
from decimal import Decimal

from faker import Faker

SEED = 42                                  # fixed seed -> repeatable data
NOW = datetime(2026, 11, 18, 12, 0, 0)     # fixed "today" so output never changes
OUT = "seed.sql"

random.seed(SEED)
Faker.seed(SEED)
fake = Faker("en_US")

N_AGENTS, N_PASSENGERS, N_AIRPORTS = 50, 200, 50
N_SCHEDULES, N_LEGS, N_RESERVATIONS, N_PAYMENTS = 60, 120, 200, 150

AIRCRAFT = ["AT72", "DH8D", "E175", "B738", "A320"]
RES_STATUS = ["CONF", "PEND", "CANC"]
TICKET = ["OW", "RT", "MC"]
CLASS = ["ECO", "PRE", "BUS"]
PAY_STATUS = ["PAID", "PEND", "REFD"]


def q(v):
    """Turn a Python value into an SQL literal."""
    if v is None:
        return "NULL"
    if isinstance(v, (int, Decimal)):
        return str(v)
    if isinstance(v, datetime):
        return "'" + v.strftime("%Y-%m-%d %H:%M:%S") + "'"
    if isinstance(v, date):
        return "'" + v.isoformat() + "'"
    return "'" + str(v).replace("\\", "\\\\").replace("'", "''") + "'"


def rand_dt(start, end):
    return start + timedelta(seconds=random.randint(0, int((end - start).total_seconds())))


tables = {}   # table name -> (columns, rows), in insert order (parents first)


def add(name, cols, rows):
    tables[name] = (cols, rows)
    return rows


# --- parents first -----------------------------------------------------------
agents = add("booking_agents", ["agent_id", "name", "other_details"],
             [[i, fake.name(), fake.company()] for i in range(1, N_AGENTS + 1)])

passengers = add(
    "passengers",
    ["passenger_id", "first_name", "second_name", "last_name", "phone_number",
     "email_address", "address_line_1", "address_line_2", "city",
     "state_province_county", "country", "other_details"],
    [[i, fake.first_name(),
      fake.first_name() if random.random() < 0.3 else None,   # second name is optional
      fake.last_name(), fake.phone_number()[:30], fake.unique.email(),
      fake.street_address(),
      fake.secondary_address() if random.random() < 0.3 else None,
      fake.city(), fake.state(), fake.country(), None]
     for i in range(1, N_PASSENGERS + 1)])

airport_codes = []
airport_rows = []
for _ in range(N_AIRPORTS):
    code = fake.unique.bothify(text="???", letters="ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    city = fake.unique.city()
    airport_codes.append(code)
    airport_rows.append([code, city + " Airport", city + ", " + fake.country(), None])
add("airports", ["airport_code", "name", "location", "other_details"], airport_rows)

cal_start, cal_end = date(2026, 1, 1), date(2026, 12, 31)
cal_rows, d = [], cal_start
while d <= cal_end:
    cal_rows.append([d, d.day, 1 if d.weekday() < 5 else 0])
    d += timedelta(days=1)
add("calendar_dates", ["calendar_date", "day_of_month", "is_business_day"], cal_rows)

flight_numbers = ["HW" + str(n) for n in random.sample(range(100, 1000), N_SCHEDULES)]
schedules = []
for fn in flight_numbers:
    o, dst = random.sample(airport_codes, 2)               # always different
    dep = rand_dt(datetime(2026, 9, 1), datetime(2026, 12, 31))
    arr = dep + timedelta(minutes=random.randint(45, 240))
    schedules.append([fn, "HW", random.choice(AIRCRAFT), o, dst, dep, arr])
add("flight_schedules",
    ["flight_number", "airline_code", "aircraft_type_code", "origin_airport",
     "destination_airport", "scheduled_departure", "scheduled_arrival"], schedules)
sched = {s[0]: s for s in schedules}

# flight legs: every schedule gets one, then extra legs on later days
leg_rows = []
for leg_id in range(1, N_LEGS + 1):
    fn = flight_numbers[leg_id - 1] if leg_id <= N_SCHEDULES else random.choice(flight_numbers)
    s = sched[fn]
    shift = timedelta(days=0 if leg_id <= N_SCHEDULES else random.randint(1, 30))
    sched_dep, sched_arr = s[5] + shift, s[6] + shift
    if sched_dep < NOW:                                     # flight already happened
        a_dep = sched_dep + timedelta(minutes=random.randint(-5, 60))
        a_arr = sched_arr + timedelta(minutes=random.randint(-5, 60))
        if a_arr <= a_dep:
            a_arr = a_dep + timedelta(minutes=45)
    else:                                                   # not flown yet -> unknown
        a_dep = a_arr = None
    leg_rows.append([leg_id, fn, s[3], s[4], a_dep, a_arr])
add("flight_legs",
    ["leg_id", "flight_number", "origin_airport", "destination_airport",
     "actual_departure", "actual_arrival"], leg_rows)

# flight costs: two non-overlapping periods per schedule, split date differs
cost_rows = []
for fn in flight_numbers:
    s = sched[fn]
    split = date(2026, random.randint(3, 10), random.randint(1, 28))
    base = Decimal(random.randint(8000, 60000)) / 100
    cost_rows.append([fn, s[2], cal_start, split, base])
    cost_rows.append([fn, s[2], split + timedelta(days=1), cal_end,
                      (base * Decimal("1.15")).quantize(Decimal("0.01"))])
add("flight_costs",
    ["flight_number", "aircraft_type_code", "valid_from", "valid_to", "cost_amount"],
    cost_rows)

res_rows = []
for rid in range(1, N_RESERVATIONS + 1):
    agent = random.randint(1, N_AGENTS) if random.random() < 0.6 else None  # else direct
    res_rows.append([rid, random.randint(1, N_PASSENGERS), agent,
                     random.choice(RES_STATUS), random.choice(TICKET), random.choice(CLASS),
                     rand_dt(datetime(2026, 1, 1), NOW), random.randint(1, 6)])
add("reservations",
    ["reservation_id", "passenger_id", "agent_id", "reservation_status_code",
     "ticket_type_code", "travel_class_code", "created_at", "party_size"], res_rows)

pay_rows = [[pid, random.choice(PAY_STATUS), rand_dt(datetime(2026, 1, 1), NOW),
             Decimal(random.randint(5000, 250000)) / 100]
            for pid in range(1, N_PAYMENTS + 1)]
add("payments", ["payment_id", "payment_status_code", "payment_date", "payment_amount"],
    pay_rows)

# linking tables: a set cannot hold the same pair twice
rp = set()
for rid in range(1, N_RESERVATIONS + 1):
    if random.random() < 0.7:                               # some have 2-3 payments
        for pid in random.sample(range(1, N_PAYMENTS + 1), random.randint(1, 3)):
            rp.add((rid, pid))
for pid in range(1, N_PAYMENTS + 1):                        # every payment is used,
    rp.add((random.randint(1, N_RESERVATIONS), pid))        # many are shared
add("reservation_payments", ["reservation_id", "payment_id"], sorted([list(x) for x in rp]))

rl = set()
for rid in range(1, N_RESERVATIONS + 1):
    if random.random() < 0.8:                               # some have 2-3 legs
        for lid in random.sample(range(1, N_LEGS + 1), random.randint(1, 3)):
            rl.add((rid, lid))
add("reservation_legs", ["reservation_id", "leg_id"], sorted([list(x) for x in rl]))

# --- self checks: fail loudly instead of writing bad data ---------------------
for name, (cols, rows) in tables.items():
    assert len(rows) >= 50, f"{name} has only {len(rows)} rows"
assert all(c[0] <= c[1] for c in [(r[2], r[3]) for r in cost_rows]), "bad cost dates"
assert len({tuple(r[:3]) for r in cost_rows}) == len(cost_rows), "duplicate cost key"
assert len({r[5] for r in schedules} | {r[6] for r in schedules}) > 0

# --- write the file -----------------------------------------------------------
with open(OUT, "w", encoding="utf-8") as f:
    f.write("-- Made by generate_data.py (seed %d). Fictional data only.\n" % SEED)
    f.write("USE harborwing;\nSET FOREIGN_KEY_CHECKS = 1;\n\n")
    for name, (cols, rows) in tables.items():
        for i in range(0, len(rows), 50):
            chunk = rows[i:i + 50]
            f.write("INSERT INTO %s (%s) VALUES\n" % (name, ", ".join(cols)))
            f.write(",\n".join("(" + ", ".join(q(v) for v in r) + ")" for r in chunk))
            f.write(";\n")
        f.write("\n")

print("Wrote", OUT)
for name, (_, rows) in tables.items():
    print(f"  {name}: {len(rows)} rows")
