FROM python:3.6-slim-stretch

ENV PYTHONUNBUFFERED 1

RUN set -x \
    && python3 -m venv /opt/controller

ENV PATH="/opt/controller/bin:${PATH}"

RUN pip --no-cache-dir --disable-pip-version-check install --upgrade pip setuptools wheel

COPY requirements.txt /opt/controller/requirements.txt

RUN pip --no-cache-dir --disable-pip-version-check install -r /opt/controller/requirements.txt

COPY controller.py /opt/controller/controller.py

ENTRYPOINT ["python", "/opt/controller/controller.py"]
