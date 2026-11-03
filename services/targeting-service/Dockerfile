# syntax=docker/dockerfile:1
# --- build: instala dependências num prefixo isolado ---
FROM python:3.11-slim AS builder
WORKDIR /build
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# --- runtime: dependências + código, usuário sem privilégios ---
FROM python:3.11-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PORT=8003
WORKDIR /app
COPY --from=builder /install /usr/local
COPY app.py .
RUN useradd -u 10001 -m app
USER 10001
EXPOSE 8003
CMD exec gunicorn --bind 0.0.0.0:${PORT} --workers 2 --access-logfile - app:app
