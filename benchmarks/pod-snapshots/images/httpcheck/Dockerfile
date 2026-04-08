FROM golang:1.22 AS builder

COPY client.go /client.go
RUN CGO_ENABLED=0 go build -o /httpclient /client.go

FROM alpine:latest
RUN apk add curl
COPY --from=builder /httpclient /usr/bin/
CMD ["/usr/bin/httpclient"]
