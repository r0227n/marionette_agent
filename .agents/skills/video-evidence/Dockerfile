FROM debian:trixie-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg python3 python3-pil python3-fonttools fonts-noto-cjk \
    && rm -rf /var/lib/apt/lists/*

ENV PYTHONDONTWRITEBYTECODE=1
ENV VIDEO_EVIDENCE_FONT=/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc
COPY scripts/ /opt/video-evidence/scripts/
WORKDIR /job
CMD ["python3", "/opt/video-evidence/scripts/render-caption.py", "--help"]
