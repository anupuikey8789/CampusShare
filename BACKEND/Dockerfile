# ==========================================
# CampusShare Backend Dockerfile (Production)
# Multi-stage C++ Crow Service Build
# ==========================================

# Stage 1: Build binary with CMake and GCC
FROM ubuntu:22.04 AS builder

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    libboost-all-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy backend source tree
COPY . /app/BACKEND
WORKDIR /app/BACKEND

# Configure and compile in Release mode
RUN cmake -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --config Release && \
    if [ -f build/Release/campusshare_backend ]; then \
        cp build/Release/campusshare_backend /app/campusshare_backend; \
    else \
        cp build/campusshare_backend /app/campusshare_backend; \
    fi

# Stage 2: Minimal runtime image
FROM ubuntu:22.04 AS runner

RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    libcurl4 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy compiled executable from builder
COPY --from=builder /app/campusshare_backend /app/campusshare_backend

# Render binds to 0.0.0.0 and assigns PORT dynamically
ENV SERVER_HOST=0.0.0.0
ENV SERVER_PORT=18080
ENV PORT=18080
EXPOSE 18080

CMD ["/app/campusshare_backend"]
