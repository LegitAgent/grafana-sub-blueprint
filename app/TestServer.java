
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.Executors;
import java.util.logging.Level;
import java.util.logging.Logger;

public class TestServer {
    private static final Logger logger = Logger.getLogger("otel-logger");
    public static void main(String[] args) {
        try {
            // open port, 0.0.0.0 for wildcard connections
            HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", 8000), 0);
            server.createContext("/", new MyHandler()); // root
            // start server
            server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());  // creates a virtual thread per task
            server.start();

            logger.info("Server is now running on port 8000: http://localhost:8000");
        } catch (IOException e) {
            logger.log(Level.SEVERE, "Error starting the server", e);
        }
    }

    // custom handler
    static class MyHandler implements HttpHandler {
        @Override 
        public void handle(HttpExchange exchange) {
            String method = exchange.getRequestMethod();
            String path = exchange.getRequestURI().getPath();
            
            logger.info(() -> String.format("Received %s request for %s", method, path));

            try {
                if (method.equals("GET")) {
                    if (path.equals("/")) {
                        sendResponse(exchange, 200, "Welcome to the Root Path!");
                        return;
                    }
                    if (path.equals("/hello-world")) {
                        sendResponse(exchange, 200, "Hello World!");
                        return;
                    } 
                }

                sendResponse(exchange, 404, "404 Not Found\n");
            } catch (IOException e) {
                logger.log(Level.SEVERE, "Server returned an error exception", e);
            }            
        }

        public void sendResponse(HttpExchange exchange, int statusCode, String response) throws IOException{
            byte[] utf8Response = response.getBytes(StandardCharsets.UTF_8); // standardized encoding system
    
            exchange.getResponseHeaders().set("Content-Type", "text/plain; charset=utf-8");
            exchange.sendResponseHeaders(statusCode, utf8Response.length);
            try(OutputStream os = exchange.getResponseBody()) {
                os.write(utf8Response);
            }
        }
    }
}