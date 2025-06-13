FROM rayproject/ray-ml:2.41.0.deprecated-py39-gpu
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

USER root

RUN chown -R ray /app

USER ray

COPY serve-chat-completion.py .

ENV PYTHONPATH="/app:${PYTHONPATH}"

CMD []