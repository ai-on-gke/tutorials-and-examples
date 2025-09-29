FROM rayproject/ray-llm:2.46.0-py311-cu124
WORKDIR /app

USER root

RUN chown -R ray /app

USER ray

COPY serve-chat-completion.py .

ENV PYTHONPATH="/app:${PYTHONPATH}"

CMD []
