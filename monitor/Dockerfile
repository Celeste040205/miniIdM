FROM python:3.11-slim
RUN apt-get update && apt-get install -y --no-install-recommends ldap-utils && \
    apt-get clean && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir prometheus_client python-ldap
WORKDIR /app
COPY exporter.py /app/exporter.py
CMD ["python", "/app/exporter.py"]