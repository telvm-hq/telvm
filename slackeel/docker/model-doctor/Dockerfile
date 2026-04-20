# Minimal image for manifest checks (curl + jq). Used only by slackeel/docker-compose.yml model_doctor.
FROM alpine:3.20
RUN apk add --no-cache bash curl jq
COPY doctor.sh /doctor.sh
# Windows checkouts may use CRLF; BusyBox sh errors with "set: illegal option -" on line endings.
RUN sed -i 's/\r$//' /doctor.sh && chmod +x /doctor.sh
ENTRYPOINT ["/bin/bash", "/doctor.sh"]
