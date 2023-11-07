# Building the binary of the App
FROM golang:1.21 AS build

WORKDIR /go/src
# Copy go.mod and go.sum
COPY go.* ./

# Downloads all the dependencies in advance (could be left out, but it's more clear this way)
RUN go mod download

# Copy all the Code and stuff to compile everything
COPY . .

# Builds the application as a staticly linked one, to allow it to run on alpine
# RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -a -installsuffix cgo -o app .
RUN CGO_ENABLED=0 go build -o catgpt

# Moving the binary to the 'final Image' to make it smaller
FROM gcr.io/distroless/static-debian12:latest-amd64 as prod

WORKDIR /app

COPY --from=build /go/src/catgpt /app/catgpt

# Exposes port 8080 because our program listens on that port
EXPOSE 8080

ENTRYPOINT ["/app/catgpt"]
