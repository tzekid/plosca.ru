########## Build stage ##########
FROM --platform=linux/amd64 golang:1.23-alpine AS builder

WORKDIR /app
RUN apk add --no-cache ca-certificates && update-ca-certificates

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /bin/webapp .

########## Runtime stage ##########
FROM --platform=linux/amd64 alpine:3.20

RUN adduser -D -u 10001 appuser
USER appuser
WORKDIR /app

COPY --from=builder /bin/webapp /app/webapp
COPY --from=builder /app/static_old /app/static_old

ENV PORT=9327
EXPOSE 9327

ENTRYPOINT ["/app/webapp"]
