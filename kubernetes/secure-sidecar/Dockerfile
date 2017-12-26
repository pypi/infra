FROM python:3.6-slim-stretch

ENV PYTHONUNBUFFERED 1

RUN set -x \
    && python3 -m venv /opt/sidecar

ENV PATH="/opt/sidecar/bin:${PATH}"

RUN pip --no-cache-dir --disable-pip-version-check install --upgrade pip setuptools wheel

COPY requirements.txt /opt/sidecar/requirements.txt

RUN pip --no-cache-dir --disable-pip-version-check install -r /opt/sidecar/requirements.txt

COPY sidecar.py /opt/sidecar/sidecar.py

ENTRYPOINT ["python", "/opt/sidecar/sidecar.py"]
