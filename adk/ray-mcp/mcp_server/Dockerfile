FROM python:3.13-slim
WORKDIR /app

RUN adduser --disabled-password --gecos "" myuser
    
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY weather_mcp.py .

RUN chown -R myuser:myuser /app
USER myuser

CMD ["python", "./weather_mcp.py"]