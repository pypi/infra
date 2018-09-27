FROM python:3.6-slim-stretch

ENV PYTHONUNBUFFERED 1

RUN set -x \
    && python3 -m venv /opt/requestor

ENV PATH="/opt/requestor/bin:${PATH}"

RUN pip --no-cache-dir --disable-pip-version-check install --upgrade pip setuptools wheel

COPY requirements.txt /opt/requestor/requirements.txt

RUN pip --no-cache-dir --disable-pip-version-check install -r /opt/requestor/requirements.txt

COPY requestor.py /opt/requestor/requestor.py

ENTRYPOINT ["python", "/opt/requestor/requestor.py"]
