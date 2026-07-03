# Build stage
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum* ./
COPY . .
# No go.sum was shipped, so resolve + write it here (needs network, which
# the Docker build has even though the environment that generated this
# project didn't). go mod tidy both downloads modules and writes go.sum.
RUN go mod tidy
RUN CGO_ENABLED=0 GOOS=linux go build -o innerarc-core .

# Run stage
FROM alpine:3.19
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=builder /app/innerarc-core .
RUN adduser -D -u 1001 appuser
USER appuser
EXPOSE 8080
CMD ["./innerarc-core"]
