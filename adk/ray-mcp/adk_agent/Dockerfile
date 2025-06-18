FROM python:3.13-slim
WORKDIR /app

RUN adduser --uid 1001 --disabled-password --gecos "" myuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .
COPY weather_agent ./weather_agent

RUN chown -R myuser:myuser /app
USER myuser

ENV PATH="/home/myuser/.local/bin:$PATH"

CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port $PORT"]
