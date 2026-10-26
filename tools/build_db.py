"""
Usage:  DB_USER=root DB_PASSWORD= DB_NAME=globalconnect_db python tools/build_db.py assets/db/koravuba.db

Build assets/db/koravuba.db for the standalone KoraVuba app.

1. Reads the MariaDB database `globalconnect_db` (your dump + Django migrations).
2. Copies every table 1:1 into SQLite (same table and column names).
3. Adds the app-only tables (kv_*) and the demo data from the new design.
"""
import datetime, decimal, json, os, sqlite3, sys, uuid, hashlib, base64, secrets
import MySQLdb

OUT = sys.argv[1]
if os.path.exists(OUT):
    os.remove(OUT)
my = MySQLdb.connect(host=os.environ.get('DB_HOST', '127.0.0.1'), user=os.environ.get('DB_USER', 'root'),
                     passwd=os.environ.get('DB_PASSWORD', ''), db=os.environ.get('DB_NAME', 'globalconnect_db'), charset='utf8mb4')
cur = my.cursor()
lite = sqlite3.connect(OUT)
lc = lite.cursor()

def sqltype(t):
    t = t.lower()
    if any(x in t for x in ('int', 'bool')):
        return 'INTEGER'
    if any(x in t for x in ('decimal', 'double', 'float', 'numeric')):
        return 'REAL'
    return 'TEXT'

def conv(v):
    if isinstance(v, decimal.Decimal):
        return float(v)
    if isinstance(v, datetime.datetime):
        return v.strftime('%Y-%m-%d %H:%M:%S.%f')
    if isinstance(v, (datetime.date,)):
        return v.isoformat()
    if isinstance(v, datetime.timedelta):  # TIME columns
        s = int(v.total_seconds())
        return '%02d:%02d:%02d' % (s // 3600, (s % 3600) // 60, s % 60)
    if isinstance(v, (bytes, bytearray)):
        return v.decode('utf8', 'replace')
    return v

SKIP = {'django_session', 'django_admin_log', 'auth_permission', 'auth_group_permissions', 'users_user_permissions'}
cur.execute("SELECT table_name FROM information_schema.tables WHERE table_schema=DATABASE() ORDER BY table_name")
tables = [r[0] for r in cur.fetchall()]
for t in tables:
    cur.execute("SELECT column_name, column_type, is_nullable, column_key, column_default FROM information_schema.columns "
                "WHERE table_schema=DATABASE() AND table_name=%s ORDER BY ordinal_position", (t,))
    cols = cur.fetchall()
    pk = [c[0] for c in cols if c[3] == 'PRI']
    defs = []
    for name, ctype, nullable, key, default in cols:
        d = f'"{name}" {sqltype(ctype)}'
        if len(pk) == 1 and name == pk[0]:
            d += ' PRIMARY KEY'
        defs.append(d)
    if len(pk) > 1:
        defs.append('PRIMARY KEY (' + ','.join(f'"{p}"' for p in pk) + ')')
    lc.execute(f'CREATE TABLE "{t}" ({", ".join(defs)})')
    if t in SKIP:
        continue
    cur.execute(f'SELECT * FROM `{t}`')
    rows = cur.fetchall()
    if rows:
        ph = ','.join('?' * len(cols))
        lc.executemany(f'INSERT INTO "{t}" VALUES ({ph})', [tuple(conv(v) for v in r) for r in rows])
    print(f'{t:35s} {len(rows):5d} rows')

# useful indexes
for sql in [
    'CREATE INDEX ix_users_email ON users(email)', 'CREATE INDEX ix_users_phone ON users(phone)',
    'CREATE INDEX ix_bookings_client ON bookings(client_id)', 'CREATE INDEX ix_bookings_provider ON bookings(provider_id)',
    'CREATE INDEX ix_msgs_conv ON chat_messages(conversation_id)', 'CREATE INDEX ix_notif_user ON notifications(user_id)',
    'CREATE INDEX ix_ps_provider ON provider_services(provider_id)', 'CREATE INDEX ix_pp_user ON provider_profiles(user_id)']:
    lc.execute(sql)

# ------------------------------------------------------------------ remove stuck accounts
# Provider users with no provider profile (pending web applications that were
# never approved) cannot use the app, so they are removed together with their
# own rows (applications, notifications, login history). Set KEEP_STUCK=1 to keep them.
if os.environ.get('KEEP_STUCK') != '1':
    stuck = lc.execute("SELECT id, email FROM users u WHERE user_type = 'provider' AND NOT EXISTS "
                       "(SELECT 1 FROM provider_profiles p WHERE p.user_id = u.id)").fetchall()
    ids = [r[0] for r in stuck]
    if ids:
        ph = ','.join('?' * len(ids))
        lc.execute(f"DELETE FROM provider_applications WHERE email IN ({ph})", [r[1] for r in stuck])
        for (t,) in lc.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
            for col in [r[1] for r in lc.execute(f'PRAGMA table_info("{t}")').fetchall()]:
                if t == 'users' and col == 'id' or col == 'user_id':
                    lc.execute(f'DELETE FROM "{t}" WHERE "{col}" IN ({ph})', ids)
                elif col.endswith('_id'):
                    lc.execute(f'UPDATE "{t}" SET "{col}" = NULL WHERE "{col}" IN ({ph})', ids)
        print('removed stuck accounts:', ', '.join(r[1] for r in stuck))

# ------------------------------------------------------------------ fresh start
# FRESH=1 empties every data table and keeps only the HQ admin account
# (HQ_EMAIL, default admin@gmail.com). Django's own bookkeeping tables
# (migrations, content types) are kept so the schema still matches.
ONLY_HQ = os.environ.get('ONLY_HQ') == '1'   # FRESH + no categories / settings: only the HQ login
if os.environ.get('FRESH') == '1' or ONLY_HQ:
    hq = os.environ.get('HQ_EMAIL', 'admin@gmail.com')
    keep_tables = {'django_migrations', 'django_content_type', 'auth_permission', 'auth_group'}
    hq_row = lc.execute('SELECT id FROM users WHERE lower(email) = lower(?)', (hq,)).fetchone()
    if hq_row is None:
        sys.exit(f'FRESH=1: HQ account {hq} not found in the dump')
    for (t,) in lc.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall():
        if t in keep_tables or t.startswith('sqlite_'):
            continue
        if t == 'users':
            lc.execute('DELETE FROM users WHERE id != ?', hq_row)
        elif t == 'user_profiles':
            lc.execute('DELETE FROM user_profiles WHERE user_id != ?', hq_row)
        else:
            lc.execute(f'DELETE FROM "{t}"')
    print('FRESH: emptied all data, kept HQ account', hq)

# ------------------------------------------------------------------ app-only tables
lc.executescript('''
CREATE TABLE kv_settings (key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE kv_badges (provider_id TEXT PRIMARY KEY, badge_id TEXT UNIQUE, category TEXT, national_id TEXT, issued_at TEXT);
CREATE TABLE kv_category_meta (category_id TEXT PRIMARY KEY, code TEXT UNIQUE, kinyarwanda_name TEXT, base_price REAL, price_unit TEXT, color TEXT);
CREATE TABLE kv_sos_alerts (id TEXT PRIMARY KEY, booking_id TEXT, raised_by_id TEXT, message TEXT, latitude REAL, longitude REAL, status TEXT, created_at TEXT, resolved_at TEXT);
CREATE TABLE kv_user_settings (user_id TEXT PRIMARY KEY, momo_number TEXT, momo_network TEXT, sector TEXT);
CREATE TABLE kv_sync_log (id INTEGER PRIMARY KEY AUTOINCREMENT, table_name TEXT, row_id TEXT, action TEXT, created_at TEXT);
''')

NOW = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d %H:%M:%S.%f')
def uid():
    return uuid.uuid4().hex

def django_hash(pw, iterations=100000):
    salt = secrets.token_urlsafe(16)[:22]
    dk = hashlib.pbkdf2_hmac('sha256', pw.encode(), salt.encode(), iterations)
    return 'pbkdf2_sha256$%d$%s$%s' % (iterations, salt, base64.b64encode(dk).decode())

for k, v in {'platform_commission_percent': '9', 'upfront_deposit_percent': '50', 'allow_instant_booking': '1',
             'platform_notice': 'Welcome to KoraVuba — company-verified services across Kigali.',
             'db_source': 'globalconnect_db (MariaDB dump, 20 Apr 2026) upgraded to current schema',
             'db_built_at': NOW}.items():
    lc.execute('INSERT INTO kv_settings VALUES (?,?)', (k, v))

CATS = [
    ('car_taxi', 'Car Taxi', 'Taxi y’Imodoka', 'Car', 'On-demand city cabs, air-conditioned comfortable rides across Kigali', 1500, 'per km (+1,500 RWF base fare)', 'amber'),
    ('moto_taxi', 'Moto Taxi', 'Taxi y’Ikinyabiziga (Moto)', 'Zap', 'Fast, helmet-equipped motorcycle transit through Kigali traffic', 500, 'per km (+500 RWF base fare)', 'emerald'),
    ('cleaner', 'Home & Office Cleaners', 'Isuku y’Inzu n’Ibiro', 'Sparkles', 'Deep home cleaning, sofa/carpet washing, post-construction cleanup', 20000, 'per session (3h)', 'emerald'),
    ('driver', 'Designated Drivers', 'Abashoferi b’Inararibonye', 'Car', 'Safe night-out drivers, personal daily drivers, airport transfers', 18000, 'per trip / night', 'blue'),
    ('plumber', 'Licensed Plumbers', 'Abafundi b’Imiyoboro', 'Wrench', 'Pipe repair, water tank installation, leak fixes, bathroom fitting', 25000, 'per job', 'amber'),
    ('electrician', 'Certified Electricians', 'Abafundi b’Amashanyarazi', 'Zap', 'Wiring repair, breaker installation, solar system troubleshooting', 25000, 'per job', 'violet'),
    ('nanny', 'Nannies & Childcare', 'Abarera b’Abana', 'HeartHandshake', 'Trained, vetted babysitters and full-day child caretakers', 22000, 'per day', 'pink'),
    ('chef', 'Private Event Chefs', 'Abatetsi b’Inararibonye', 'Utensils', 'Professional cooks for home dinners, buffets and meal prep', 45000, 'per event', 'yellow'),
    ('tutor', 'Private Tutors', 'Abarimu bigisha mu rugo', 'GraduationCap', 'Academic tutoring, language lessons, STEM coaching & homework support', 25000, 'per session (2h)', 'sky'),
    ('barber', 'At-Home Barbers & Stylists', 'Abogoshi bo mu rugo', 'Scissors', 'Mobile haircuts, beard grooming and hair styling at your door', 15000, 'per person', 'teal'),
]
cat_ids = {}
for i, (code, name, rw, icon, desc, price, unit, color) in enumerate(CATS):
    cid = uid(); cat_ids[code] = cid
    lc.execute('INSERT INTO service_categories (id,created_at,updated_at,deleted_at,name,slug,icon,image,description,sort_order,is_active,parent_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
               (cid, NOW, NOW, None, name, code.replace('_', '-'), icon, '', desc, i, 1, None))
    lc.execute('INSERT INTO kv_category_meta VALUES (?,?,?,?,?,?)', (cid, code, rw, price, unit, color))

# map the real (existing) provider services to categories
KEYWORDS = {'clean': 'cleaner', 'wash': 'cleaner', 'plumb': 'plumber', 'transport': 'driver', 'repair': 'electrician',
            'carpent': 'plumber', 'massage': 'barber', 'video': 'chef', 'rent': 'driver'}
for sid, name in lc.execute('SELECT id, name FROM provider_services').fetchall():
    for kw, code in KEYWORDS.items():
        if kw in (name or '').lower():
            lc.execute('UPDATE provider_services SET category_id=? WHERE id=?', (cat_ids[code], sid)); break

def user_cols():
    return [r[1] for r in lc.execute('PRAGMA table_info(users)')]
UCOLS = user_cols()
def add_user(email, phone, first, last, utype, pw, city='Kigali', lat=None, lng=None, staff=0):
    u = dict.fromkeys(UCOLS)
    u.update(id=uid(), password=django_hash(pw), is_superuser=1 if utype == 'admin' else 0, created_at=NOW, updated_at=NOW,
             email=email, phone=phone, first_name=first, last_name=last, user_type=utype, email_verified=1, phone_verified=1,
             is_active=1, is_staff=staff, profile_image='', address='', city=city, country='Rwanda', postal_code='',
             state='', latitude=lat, longitude=lng)
    lc.execute(f'INSERT INTO users ({",".join(UCOLS)}) VALUES ({",".join("?"*len(UCOLS))})', [u[c] for c in UCOLS])
    lc.execute('INSERT INTO user_profiles (id,created_at,updated_at,deleted_at,bio,city,state,postal_code,country,latitude,longitude,language,notification_enabled,facebook_url,twitter_url,instagram_url,linkedin_url,user_id) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
               (uid(), NOW, NOW, None, '', city, '', '', 'Rwanda', lat, lng, 'en', 1, '', '', '', '', u['id']))
    return u['id']

DEMO = os.environ.get('DEMO', '0') == '1'   # DEMO=1 adds the design's demo companies/workers/accounts
if DEMO:
    # platform admin + demo client
    add_user('admin@koravuba.rw', '+250788000001', 'KoraVuba', 'HQ Admin', 'admin', 'Admin@2026', staff=1)
    client_id = add_user('diane.kanimba@gmail.com', '+250788123456', 'Diane', 'Kanimba', 'client', '123456', lat=-1.9536, lng=30.1131)

    COMPANIES = [
        ('comp-uburiza', 'Uburiza Cleaning and Maintenance Ltd', 'KV-COMP-UBURIZA', 'TIN-109922883', 'RDB-2025-00412', '+250788900100', 'info@uburizacleaning.rw', 'Remera', 'Bank of Kigali • 000551122-88'),
        ('comp-1', 'CleanRwanda Express Ltd', 'KV-COMP-101', 'TIN-109847291', 'RDB-2023-09812', '+250788123450', 'support@cleanrwanda.rw', 'Remera', 'Bank of Kigali • 000129384-91'),
        ('comp-2', 'Kigali Designated Drivers Co.', 'KV-COMP-102', 'TIN-104928172', 'RDB-2022-04421', '+250788987654', 'info@kigalidrivers.rw', 'Kiyovu', 'I&M Bank • 000492817-22'),
        ('comp-3', 'QuickFix Plumbing & Sanitation Ltd', 'KV-COMP-103', 'TIN-107726152', 'RDB-2024-01123', '+250788555333', 'service@quickfix.rw', 'Gikondo', 'Equity Bank • 000772615-33'),
        ('comp-4', 'SparkElectric Rwanda Ltd', 'KV-COMP-104', 'TIN-103388291', 'RDB-2023-07781', '+250788444888', 'support@sparkelectric.rw', 'Kimironko', 'Cogebanque • 000338829-11'),
        ('comp-5', 'BrightNanny Rwanda Care', 'KV-COMP-105', 'TIN-105544332', 'RDB-2024-09981', '+250788222111', 'hello@brightnanny.rw', 'Kacyiru', 'MTN MoMo • 788222111'),
        ('comp-6', 'Kigali Premier Tutors & Mentors Co.', 'KV-COMP-106', 'TIN-106677889', 'RDB-2025-01822', '+250788333999', 'contact@kigalitutors.rw', 'Remera', 'Bank of Kigali • 000667788-99'),
        ('comp-7', 'Kigali Executive Mobile Barbers', 'KV-COMP-107', 'TIN-107788990', 'RDB-2025-02199', '+250788666555', 'info@kigalibarbers.rw', 'Nyamirambo', 'MTN MoMo • 788666555'),
    ]
    ECOLS = [r[1] for r in lc.execute('PRAGMA table_info(entities)')]
    ent_ids = {}
    for key, name, code, tin, rdb, phone, email, sector, bank in COMPANIES:
        e = dict.fromkeys(ECOLS)
        eid = uid(); ent_ids[key] = eid
        e.update(id=eid, entity_type='company', business_name=name, business_description=f'{name} — company-verified service providers in {sector}, Kigali.',
                 logo='', registration_number=rdb, registration_certificate='', tin_number=tin, tin_certificate='', official_email=email,
                 official_phone=phone, physical_address=f'{sector}, Kigali', website='', subscription_type='monthly', provider_count=20,
                 max_providers=50, subscription_fee=10000, payment_method='mobile_money', payment_reference='', payment_confirmed=1,
                 company_id=code, payout_account_type='bank', payout_account_number=bank, bank_name=bank.split(' •')[0],
                 account_holder_name=name, status='active', admin_notes='', rejection_reason='', created_at=NOW, updated_at=NOW,
                 verified_at=NOW, subscription_start=NOW, subscription_end=(datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=30)).strftime('%Y-%m-%d %H:%M:%S.%f'))
        lc.execute(f'INSERT INTO entities ({",".join(ECOLS)}) VALUES ({",".join("?"*len(ECOLS))})', [e[c] for c in ECOLS])
        admin_uid = add_user(email, phone, name.split()[0], 'Admin', 'entity_admin', 'KoraVuba#2026')
        lc.execute('INSERT INTO entity_admins (is_primary_admin,position,permissions,created_at,entity_id,user_id) VALUES (1,?,?,?,?,?)', ('Company Admin', '{}', NOW, eid, admin_uid))

    WORKERS = [
        ('KV-TAXI-001', 'comp-uburiza', 'Fabrice', 'Manzi', '+250788444555', 'car_taxi', 4.95, 310, -1.9540, 30.1140),
        ('KV-MOTO-001', 'comp-uburiza', 'Eric', 'Nsengiyumva', '+250788666777', 'moto_taxi', 4.88, 420, -1.9480, 30.1080),
        ('KV-UBUR-001', 'comp-uburiza', 'Divine', 'Mukamana', '+250788900111', 'cleaner', 4.9, 195, -1.9530, 30.1120),
        ('KV-UBUR-002', 'comp-uburiza', 'Innocent', 'Nshimiyimana', '+250788900222', 'cleaner', 4.85, 140, -1.9420, 30.1250),
        ('KV-CLEAN-00147', 'comp-1', 'Jean-Luc', 'Mugisha', '+250788111222', 'cleaner', 4.9, 184, -1.9520, 30.1110),
        ('KV-CLEAN-00148', 'comp-1', 'Aline', 'Umutoni', '+250788333444', 'cleaner', 4.85, 122, -1.9440, 30.1240),
        ('KV-DRIV-00201', 'comp-2', 'Eric', 'Nshimiye', '+250788777888', 'driver', 4.95, 310, -1.9480, 30.0650),
        ('KV-PLUMB-00305', 'comp-3', 'David', 'Kayitare', '+250788666999', 'plumber', 4.75, 95, -1.9670, 30.0810),
        ('KV-ELEC-00412', 'comp-4', 'Patrick', 'Habimana', '+250788222999', 'electrician', 4.9, 140, -1.9410, 30.1220),
        ('KV-NANY-00508', 'comp-5', 'Marie-Grace', 'Keza', '+250788444333', 'nanny', 5.0, 215, -1.9350, 30.0750),
        ('KV-TUTO-00601', 'comp-6', 'Christian', 'Bizimana', '+250788333111', 'tutor', 4.95, 168, -1.9510, 30.1140),
        ('KV-BARB-00701', 'comp-7', 'Pacifique', 'Twagiramungu', '+250788666111', 'barber', 4.9, 240, -1.9710, 30.0480),
    ]
    PCOLS = [r[1] for r in lc.execute('PRAGMA table_info(provider_profiles)')]
    SCOLS = [r[1] for r in lc.execute('PRAGMA table_info(provider_services)')]
    ACOLS = [r[1] for r in lc.execute('PRAGMA table_info(provider_availability)')]
    meta = {c[0]: c for c in CATS}
    for badge, comp, first, last, phone, cat, rating, jobs, lat, lng in WORKERS:
        email = f'{badge.lower()}@workers.koravuba.rw'
        u = add_user(email, phone, first, last, 'provider', '123456', lat=lat, lng=lng)
        p = dict.fromkeys(PCOLS); pid = uid()
        p.update(id=pid, created_at=NOW, updated_at=NOW, business_name=f'{first} {last}', business_description=f'{meta[cat][1]} • {meta[cat][4]}',
                 is_verified=1, verification_status='approved', verified_at=NOW, average_rating=rating, total_reviews=max(5, jobs // 6),
                 max_travel_distance=10, total_jobs_completed=jobs, total_earnings=0, user_id=u, address='Kigali', can_travel=1,
                 city='Kigali', country='Rwanda', phone=phone, postal_code='', state='', latitude=lat, longitude=lng,
                 location_updated_at=NOW, location_verified=1, company_id=dict((c[0], c[2]) for c in COMPANIES)[comp],
                 entity_verified_at=NOW, is_active=1, last_active_at=NOW, verified_by_entity=1, entity_id=ent_ids[comp])
        lc.execute(f'INSERT INTO provider_profiles ({",".join(PCOLS)}) VALUES ({",".join("?"*len(PCOLS))})', [p[c] for c in PCOLS])
        s = dict.fromkeys(SCOLS)
        s.update(id=uid(), created_at=NOW, updated_at=NOW, name=meta[cat][1], description=meta[cat][4], price_type='hourly' if 'per km' not in meta[cat][6] else 'fixed',
                 price=meta[cat][5], price_unit=meta[cat][6], estimated_duration=60, is_active=1, provider_id=pid, category_id=cat_ids[cat], image='')
        lc.execute(f'INSERT INTO provider_services ({",".join(SCOLS)}) VALUES ({",".join("?"*len(SCOLS))})', [s[c] for c in SCOLS])
        a = dict.fromkeys(ACOLS)
        a.update(id=uid(), created_at=NOW, updated_at=NOW, provider_id=pid, is_available=1, monday=1, tuesday=1, wednesday=1, thursday=1,
                 friday=1, saturday=1, sunday=0, available_from='07:00:00', available_to='20:00:00')
        lc.execute(f'INSERT INTO provider_availability ({",".join(ACOLS)}) VALUES ({",".join("?"*len(ACOLS))})', [a[c] for c in ACOLS])
        lc.execute('INSERT INTO kv_badges VALUES (?,?,?,?,?)', (pid, badge, cat, '', NOW))

# badges for the real providers already in your database
for pid, name in lc.execute('SELECT id, business_name FROM provider_profiles WHERE id NOT IN (SELECT provider_id FROM kv_badges)').fetchall():
    lc.execute('INSERT INTO kv_badges VALUES (?,?,?,?,?)', (pid, 'KV-PRO-' + pid[:5].upper(), None, '', NOW))

if DEMO:
    # demo notifications for the demo client
    NCOLS = [r[1] for r in lc.execute('PRAGMA table_info(notifications)')]
    for title, msg, typ in [('Welcome to KoraVuba 👋', 'Book company-verified cleaners, drivers, plumbers and more across Kigali.', 'system'),
                            ('Top Rated Company Spotlight', 'CleanRwanda Express Ltd was awarded Top Cleaner Company this month.', 'promo')]:
        n = dict.fromkeys(NCOLS)
        n.update(id=uid(), created_at=NOW, updated_at=NOW, user_id=client_id, notification_type=typ, title=title, message=msg, priority='medium',
                 data='{}', is_read=0, is_active=1, is_email_sent=0, is_push_sent=0, is_sms_sent=0, action_url='', is_broadcast=0,
                 target_user_type='', related_object_id='', related_object_type='')
        lc.execute(f'INSERT INTO notifications ({",".join(NCOLS)}) VALUES ({",".join("?"*len(NCOLS))})', [n[c] for c in NCOLS])

if ONLY_HQ:
    for t in ('service_categories', 'kv_category_meta', 'kv_settings', 'kv_badges'):
        lc.execute(f'DELETE FROM "{t}"')
    print('ONLY_HQ: removed categories and settings too')

# optional: set a new HQ admin password (HQ_EMAIL defaults to admin@gmail.com)
if os.environ.get('HQ_PASSWORD'):
    lc.execute('UPDATE users SET password = ?, is_active = 1 WHERE lower(email) = lower(?)',
               (django_hash(os.environ['HQ_PASSWORD']), os.environ.get('HQ_EMAIL', 'admin@gmail.com')))
    print('HQ password reset for', os.environ.get('HQ_EMAIL', 'admin@gmail.com'))

lite.commit()
lc.execute('VACUUM')
lite.close()
print('OK ->', OUT, os.path.getsize(OUT) // 1024, 'KB')
