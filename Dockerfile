# Build stage
FROM rust:alpine3.20 AS builder
# Install build dependencies
RUN apk add --no-cache musl-dev
# Set the working directory
WORKDIR /app
# Copy the project files
COPY . .
# Build the project
RUN cargo build --release

# Runtime stage
FROM alpine:3.16
# Copy the built binary from the builder stage
COPY --from=builder /app/target/release/vproxy /bin/vproxy
# Iproute2 and procps are needed for the vproxy to work
RUN apk add --no-cache iproute2 procps
# Script that serves the PAC file, generated from Railway's own env vars
COPY serve-pac.sh /app/serve-pac.sh
RUN chmod +x /app/serve-pac.sh
# Serve the PAC file on 8090 alongside vproxy
ENTRYPOINT ["/bin/sh", "-c", "/app/serve-pac.sh & exec /bin/vproxy run --bind 0.0.0.0:$PORT http"]
