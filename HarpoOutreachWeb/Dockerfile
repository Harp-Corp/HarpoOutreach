# ================================
# Build Stage
# ================================
FROM swift:5.10-jammy AS builder

WORKDIR /build

# Copy the entire HarpoOutreachWeb package
COPY . .

# Copy HarpoOutreachCore (sibling package)
COPY ../HarpoOutreachCore /HarpoOutreachCore

# Resolve dependencies and build in release mode
RUN swift package resolve
RUN swift build -c release --disable-sandbox

# ================================
# Run Stage
# ================================
FROM ubuntu:jammy

# Install Swift runtime dependencies
RUN apt-get update && apt-get install -y \
  libatomic1 \
  libbsd0 \
  libcurl4 \
  libxml2 \
  libz-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the built executable
COPY --from=builder /build/.build/release/HarpoOutreachWeb ./

# Copy the Public folder for static files
COPY --from=builder /build/Public ./Public

# Expose Vapor's default port
EXPOSE 8080

# Set environment for production
ENV VAPOR_ENV=production

# Run the server
CMD ["./HarpoOutreachWeb", "serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
