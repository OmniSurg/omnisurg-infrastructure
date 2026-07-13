FROM golang:1.25-alpine AS builder
WORKDIR /app
COPY go.mod ./
RUN go mod download
COPY main.go ./
RUN go build -o /bin/stub main.go

FROM alpine:3.19
RUN apk add --no-cache wget
COPY --from=builder /bin/stub /bin/stub
EXPOSE 9003
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://localhost:9003/healthz || exit 1
CMD ["/bin/stub"]
