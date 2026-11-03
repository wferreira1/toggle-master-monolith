# syntax=docker/dockerfile:1
# --- build: compila um binário estático ---
FROM golang:1.23-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/auth-service .

# --- runtime: só o binário, usuário sem privilégios ---
FROM alpine:3.20
RUN adduser -D -u 10001 app
COPY --from=builder /out/auth-service /usr/local/bin/auth-service
USER 10001
ENV PORT=8001
EXPOSE 8001
ENTRYPOINT ["/usr/local/bin/auth-service"]
