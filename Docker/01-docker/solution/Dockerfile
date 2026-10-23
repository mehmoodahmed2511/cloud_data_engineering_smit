# Pinned, and slim: see the "picking a base image" slide.
FROM python:3.11-slim

WORKDIR /app

# Requirements first, so editing etl.py does not reinstall pandas every build.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY etl.py .

ENV DATA_DIR=/app/data

CMD ["python", "etl.py"]
