FROM python:3.6-slim-stretch

ENV PYTHONUNBUFFERED 1

RUN set -x \
    && python3 -m venv /opt/approver

ENV PATH="/opt/approver/bin:${PATH}"

RUN pip --no-cache-dir --disable-pip-version-check install --upgrade pip setuptools wheel

COPY requirements.txt /opt/approver/requirements.txt

RUN pip --no-cache-dir --disable-pip-version-check install -r /opt/approver/requirements.txt

COPY approver.py /opt/approver/approver.py

ENTRYPOINT ["python", "/opt/approver/approver.py"]
