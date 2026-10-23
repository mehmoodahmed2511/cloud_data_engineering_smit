# Docker — extra exercises

Do these after the three checkpoints. Roughly in order of difficulty.

## 1. Break it on purpose (10 min)
Remove the `healthcheck` and the `condition: service_healthy` from your Compose
file, then `docker compose up --build`. Read the error carefully.

- What exactly does the ETL say?
- Why does it sometimes work anyway if you run it twice?
- Put them back and explain to someone else what they do.

## 2. Make the image smaller (15 min)
Run `docker images` and note the size of `sales-etl`.

- Does the `.dockerignore` include `data/`? That CSV does not belong in the image.
- Try `python:3.11-alpine` instead of `-slim`. Time the build. Does it even finish?
  (This is a trap — find out why for yourself.)
- Add `--no-cache-dir` to the pip install if you have not already.

Report the before and after sizes.

## 3. One image, many containers (10 min)
```bash
docker run -d --name a sales-etl:v1 sleep 300
docker run -d --name b sales-etl:v1 sleep 300
docker run -d --name c sales-etl:v1 sleep 300
docker ps
```
Three containers, one image. Open a shell in `a`, create a file in `/app`, then
check whether it exists in `b`. Explain the result.

## 4. Bind mount for live editing (15 min)
Add a bind mount for your source code, not just the data:

```yaml
volumes:
  - ./data:/app/data
  - ./etl.py:/app/etl.py
```

Now edit `etl.py` and re-run `docker compose run --rm etl` without rebuilding.
When is this a good idea, and when is it a bad one?

## 5. A second service (20 min)
Add Adminer, a web UI for databases, to your Compose file:

```yaml
  adminer:
    image: adminer
    ports:
      - "8081:8080"
    depends_on:
      - db
```

Open `http://localhost:8081`, log in (server `db`, user `postgres`, password
`secret`, database `sales`), and browse the table your ETL loaded.

- Why is the server field `db` and not `localhost`?
- Why does the ETL service have no `ports:` entry but this one does?

## 6. Run as a non-root user (20 min, stretch)
Production images should not run as root. Add to your Dockerfile:

```dockerfile
RUN useradd --create-home appuser
USER appuser
```

Rebuild. If it breaks, work out why from the error — it is a real one, and the
fix teaches you something about where `COPY` puts files and who owns them.

## 7. Push it to a registry (20 min, stretch)
This is tomorrow's class, but try it now:

```bash
docker login ghcr.io -u YOUR_GITHUB_USERNAME
docker tag sales-etl:v1 ghcr.io/YOUR_GITHUB_USERNAME/sales-etl:v1
docker push ghcr.io/YOUR_GITHUB_USERNAME/sales-etl:v1
```

Then have a classmate `docker pull` and run it. Nothing of yours is on their
machine except the image.
