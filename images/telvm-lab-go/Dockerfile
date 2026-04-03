# Telvm certified lab: Go + Fiber. GET / -> JSON 200 on port 3333.
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
RUN go mod tidy && CGO_ENABLED=0 go build -o /lab -ldflags="-s -w" .

FROM alpine:3.21
RUN adduser -D -u 10001 labuser
COPY --from=build /lab /lab
USER labuser
EXPOSE 3333
CMD ["/lab"]
