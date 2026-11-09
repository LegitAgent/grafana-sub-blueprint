# smaller for testing use cases
FROM eclipse-temurin:21-jdk-jammy

WORKDIR /app
# . . is shorthand when WORKDIR is set
COPY app/*.java ./

RUN javac *.java

EXPOSE 8000

CMD [ "java", "TestServer" ]
