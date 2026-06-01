# Build stage
FROM golang:1.22-alpine AS builder

WORKDIR /app

# Copy dependency manifests and download Go modules
COPY go.mod go.sum ./
RUN go mod download

# Copy source code
COPY . .

# Build the binary
RUN CGO_ENABLED=0 GOOS=linux go build -o incident-service .

# Run stage
FROM alpine:latest

WORKDIR /app

RUN apk --no-cache add ca-certificates

# Copy the compiled binary from build stage
COPY --from=builder /app/incident-service .

# Copy the schema file for reference
COPY schema.sql .

EXPOSE 8090

ENV PORT=8090

CMD ["./incident-service"]
