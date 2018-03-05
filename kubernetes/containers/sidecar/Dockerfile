FROM python:3.6-slim-stretch

ENV PYTHONUNBUFFERED 1

ENV GHOSTUNNEL_FORK=ewdurbin
ENV GHOSTUNNEL_VERSION=v1.2.0-ewdurbin-rc.1
ENV GHOSTUNNEL_SHASUM=5c55a7da6ed37db00c90c89415dcc9ad0e3ec627b6ff29f9846d87e86d65cba0

RUN apt-get update && apt-get install wget -y && rm -rf /var/lib/apt/lists/*

RUN wget --quiet https://github.com/${GHOSTUNNEL_FORK}/ghostunnel/releases/download/${GHOSTUNNEL_VERSION}/ghostunnel_${GHOSTUNNEL_VERSION}_linux_amd64.tgz
RUN if [ "$(sha256sum ghostunnel_${GHOSTUNNEL_VERSION}_linux_amd64.tgz)" != "$GHOSTUNNEL_SHASUM  ghostunnel_${GHOSTUNNEL_VERSION}_linux_amd64.tgz" ]; then exit 1; fi
RUN tar -xzf ghostunnel_${GHOSTUNNEL_VERSION}_linux_amd64.tgz && rm ghostunnel_${GHOSTUNNEL_VERSION}_linux_amd64.tgz

RUN chmod +x ghostunnel

RUN set -x \
    && python3 -m venv /opt/sidecar

ENV PATH="/opt/sidecar/bin:${PATH}"

RUN pip --no-cache-dir --disable-pip-version-check install --upgrade pip setuptools wheel

COPY requirements.txt /opt/sidecar/requirements.txt

RUN pip --no-cache-dir --disable-pip-version-check install -r /opt/sidecar/requirements.txt

COPY sidecar.py /opt/sidecar/sidecar.py

ENTRYPOINT ["python", "/opt/sidecar/sidecar.py"]
