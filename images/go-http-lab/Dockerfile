# Minimal HTTP lab for VM manager pre-flight: GET / -> 200 on port 3333.
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY go.mod main.go ./
RUN CGO_ENABLED=0 go build -o /lab -ldflags="-s -w" .

FROM alpine:3.20
RUN adduser -D -u 10001 labuser
COPY --from=build /lab /lab
USER labuser
EXPOSE 3333
CMD ["/lab"]
