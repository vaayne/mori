FROM golang:1.24-alpine AS build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=0 go build -o /relay .

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=build /relay /relay
EXPOSE 8080
CMD ["/relay"]
