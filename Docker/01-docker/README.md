# Workshop 1 — Docker for Data Engineers

**Time:** about 90 minutes, in three checkpoints that follow the slides.
**You need:** Docker Desktop running, and a terminal.

Check it works before you start:

```bash
docker --version
docker compose version
docker run --rm hello-world
```

If the last one fails, Docker Desktop is not running. Open it, wait for the whale
icon to stop moving, and try again.

## What is in this folder

| File | What it is |
|---|---|
| `etl.py` | A 40-line sales ETL. Reads `data/sales.csv`, cleans it, writes it to Postgres. |
| `requirements.txt` | The three libraries it needs. |
| `data/sales.csv` | 403 rows of fake orders, including three deliberately broken ones. |
| `solution/` | The answers. **Do not open these until you have tried.** |
| `CHEATSHEET.md` | Every command from the class, in one page. |
| `EXERCISES.md` | Extra practice once the checkpoints are done. |

---

## Checkpoint 1 — Run a database without installing one

Start Postgres:

```bash
docker run -d \
  --name sales-db \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=sales \
  -p 5432:5432 \
  postgres:16
```

Check it is up, then look inside it:

```bash
docker ps
docker logs sales-db
docker exec -it sales-db psql -U postgres -d sales
```

At the `sales=#` prompt:

```sql
CREATE TABLE hello (id int, note text);
INSERT INTO hello VALUES (1, 'I made a table inside a container');
SELECT * FROM hello;
\q
```

Now delete it and start a fresh one:

```bash
docker stop sales-db && docker rm sales-db
docker run -d --name sales-db -e POSTGRES_PASSWORD=secret -e POSTGRES_DB=sales -p 5432:5432 postgres:16
docker exec -it sales-db psql -U postgres -d sales -c "SELECT * FROM hello;"
```

**Your table is gone.** That is not a bug, and we fix it in checkpoint 3.

> **Questions to answer before moving on**
> 1. What does `-d` do? What happens if you leave it out?
> 2. In `-p 5432:5432`, which number is your laptop and which is the container?
> 3. Why did the table disappear?

---

## Checkpoint 2 — Build your own image

Read `etl.py` first. It is ordinary pandas; nothing clever.

**Write the Dockerfile yourself.** Create a file called `Dockerfile` in this folder.
You need six lines. Think about:

- Which base image? (Pinned, and slim.)
- Which folder does the code live in inside the container?
- What has to be copied in, and in what order? (Remember the caching slide.)
- What command runs when the container starts?

Then build and run it:

```bash
docker build -t sales-etl:v1 .
docker run --rm sales-etl:v1
```

It will fail with a database connection error. **That is the expected result** —
there is no database wired up yet.

Now add a `.dockerignore` and rebuild. Note how much faster it is, and compare
`docker images` sizes before and after.

Only once you have something that builds: compare it with `solution/Dockerfile`.

> **Questions to answer before moving on**
> 1. Why does `COPY requirements.txt .` come before `COPY etl.py .`?
> 2. What does the `.` at the end of `docker build -t sales-etl:v1 .` mean?
> 3. You change one line of `etl.py`. Which build steps re-run?

---

## Checkpoint 3 — The whole stack with Compose

Write `docker-compose.yml` in this folder with two services:

- `db` — `postgres:16`, with a password, a named volume for its data, and a
  healthcheck.
- `etl` — built from your Dockerfile, with `DB_HOST` set to the **service name**,
  a bind mount for `./data`, and `depends_on` the db being healthy.

Then:

```bash
docker compose up --build
```

You should see the ETL wait for the database, then print something like:

```
Read 403 rows from /app/data/sales.csv
400 rows left after cleaning
Loaded 400 rows, PKR 1,234,560 in sales
```

Check the data really landed:

```bash
docker compose exec db psql -U postgres sales -c "SELECT city, count(*) FROM sales GROUP BY city;"
```

Now prove the volume works:

```bash
docker compose down          # stop everything, keep the volume
docker compose up -d db      # start just the database
docker compose exec db psql -U postgres sales -c "SELECT count(*) FROM sales;"
```

The rows are still there. Then:

```bash
docker compose down -v       # -v deletes the volume too
docker compose up -d db
docker compose exec db psql -U postgres sales -c "SELECT count(*) FROM sales;"
```

Gone. **That is the difference `-v` makes.** Remember it.

---

## The final test

Push this folder to GitHub with a README whose setup instructions are one line:

```
docker compose up --build
```

Then hand it to the person next to you and watch them run it on their laptop,
first try, with nothing installed.

If they need a second instruction, it is not finished.
