# Docker cheat sheet

## Images
```bash
docker pull postgres:16            # download an image
docker images                      # what is on my disk
docker build -t sales-etl:v1 .     # build from the Dockerfile here
docker rmi sales-etl:v1            # delete an image
docker history sales-etl:v1        # see the layers
```

## Containers
```bash
docker run -d --name db postgres:16     # start one in the background
docker run --rm -it python:3.11 bash    # start one, delete it on exit
docker ps                               # what is running
docker ps -a                            # everything, stopped ones too
docker stop db                          # polite shutdown
docker start db                         # start it again
docker rm db                            # delete the container
```

## Looking inside
```bash
docker logs -f db                  # follow the output
docker logs --tail 50 db           # last 50 lines
docker exec -it db bash            # open a shell inside
docker exec -it db psql -U postgres sales
docker inspect db                  # every setting, as JSON
docker stats                       # live CPU and memory
docker port db                     # which ports are published
```

## Flags you will use on `docker run`
| Flag | Means |
|---|---|
| `-d` | Detached: run in the background |
| `--rm` | Delete the container when it stops |
| `-it` | Interactive terminal (for a shell) |
| `--name x` | Call it `x` instead of a random name |
| `-p 8080:80` | Your port 8080 reaches its port 80 |
| `-e KEY=val` | Set an environment variable inside |
| `-v name:/path` | Mount a named volume (database data) |
| `-v $(pwd)/data:/app/data` | Bind-mount your folder (code, CSVs) |
| `--network net` | Join a network so containers can see each other |

## Compose
```bash
docker compose up -d               # start the whole stack
docker compose up --build          # rebuild images first
docker compose ps                  # what is running
docker compose logs -f etl         # follow one service
docker compose exec db psql -U postgres sales
docker compose down                # stop and remove containers
docker compose down -v             # ... and delete the volumes (DELETES DATA)
```

## Cleaning up
```bash
docker system df                   # how much disk am I using
docker system prune                # remove stopped containers, unused networks
docker system prune -a             # ... and every image you are not running
docker volume ls                   # list volumes
```

## The five things that go wrong
1. **`Cannot connect to the Docker daemon`** — Docker Desktop is not running.
2. **`failed to read dockerfile`** — wrong folder, or the file is named `Dockerfile.txt`.
3. **`port is already allocated`** — change the left-hand number: `-p 5433:5432`.
4. **`could not translate host name "localhost"`** — between containers, use the
   service name (`db`), not `localhost`.
5. **"I edited the file but nothing changed"** — rebuild: `docker compose up --build`.
