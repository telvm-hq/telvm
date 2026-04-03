# Telvm certified lab: Python + FastAPI + uvicorn. GET / -> JSON 200 on port 3333.
FROM python:3.12-slim-bookworm

WORKDIR /app

RUN useradd -m -u 10001 labuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

USER labuser

EXPOSE 3333

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "3333"]
