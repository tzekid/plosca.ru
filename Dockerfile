########## Build stage ##########
FROM --platform=linux/amd64 rust:1-alpine AS builder

WORKDIR /app
RUN apk add --no-cache musl-dev pkgconfig build-base ca-certificates && update-ca-certificates

COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY static_old ./static_old

RUN cargo build --release --bin webapp

########## Runtime stage ##########
FROM --platform=linux/amd64 alpine:3.20

RUN adduser -D -u 10001 appuser
USER appuser
WORKDIR /app

COPY --from=builder /app/target/release/webapp /app/webapp
COPY --from=builder /app/static_old /app/static_old

ENV PORT=9327
EXPOSE 9327

ENTRYPOINT ["/app/webapp"]
