FROM python:3.6-slim-stretch

ENV PYTHONUNBUFFERED 1

ENV GHOSTUNNEL_FORK=square
ENV GHOSTUNNEL_VERSION=v1.2.0-rc.2
ENV GHOSTUNNEL_SHASUM=2917dc65f664378ff023dc966a1725ef13b8decaf3590e24055be9061f222216

RUN apt-get update && apt-get install wget -y && rm -rf /var/lib/apt/lists/*

RUN wget --quiet https://github.com/${GHOSTUNNEL_FORK}/ghostunnel/releases/download/${GHOSTUNNEL_VERSION}/ghostunnel-${GHOSTUNNEL_VERSION}-linux-amd64-with-pkcs11
RUN if [ "$(sha256sum ghostunnel-${GHOSTUNNEL_VERSION}-linux-amd64-with-pkcs11)" != "$GHOSTUNNEL_SHASUM  ghostunnel-${GHOSTUNNEL_VERSION}-linux-amd64-with-pkcs11" ]; then exit 1; fi
RUN mv ghostunnel-${GHOSTUNNEL_VERSION}-linux-amd64-with-pkcs11 ghostunnel

RUN chmod +x ghostunnel

RUN set -x \
    && python3 -m venv /opt/sidecar

ENV PATH="/opt/sidecar/bin:${PATH}"

RUN pip --no-cache-dir --disable-pip-version-check install --upgrade pip setuptools wheel

COPY requirements.txt /opt/sidecar/requirements.txt

RUN pip --no-cache-dir --disable-pip-version-check install -r /opt/sidecar/requirements.txt

COPY sidecar.py /opt/sidecar/sidecar.py

ENTRYPOINT ["python", "/opt/sidecar/sidecar.py"]
