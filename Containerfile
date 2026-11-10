# smaller for testing use cases
FROM eclipse-temurin:21-jdk-jammy

WORKDIR /app

COPY app/*.java ./
COPY otel/opentelemetry-javaagent.jar ./otel/

RUN javac *.java
# ENV vars
ENV OTEL_SERVICE_NAME=hello-world-app
ENV OTEL_METRICS_EXPORTER=otlp
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp
ENV OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318

EXPOSE 8000

CMD [ "java", "-javaagent:otel/opentelemetry-javaagent.jar", "TestServer" ]
