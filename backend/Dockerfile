# Render Docker setup for the plain-Dart HTTP API.
# Build context must be the backend/ directory.
FROM dart:stable

# pdftotext (poppler-utils) reads the airport's seasonal winter PDF timetable.
# Without it that one source reports "unavailable"; the others keep working.
RUN apt-get update \
    && apt-get install -y --no-install-recommends poppler-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Render injects PORT (10000 by default) and the server reads it. The server
# binds to loopback unless HOST says otherwise, so a container must set it.
ENV PORT=10000
ENV HOST=0.0.0.0
EXPOSE 10000

# Copy dependency manifests first to improve Docker layer caching.
COPY pubspec.yaml pubspec.lock* ./
RUN dart pub get

# Copy backend source (bin/ and lib/ are all the server needs at runtime).
COPY . .
RUN dart pub get --offline

CMD ["dart", "run", "bin/server.dart"]
