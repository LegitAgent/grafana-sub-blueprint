
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpHandler;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public class TestServer {
    public static void main(String[] args) {
        try {
            // open port, 0.0.0.0 for wildcard connections
            HttpServer server = HttpServer.create(new InetSocketAddress("0.0.0.0", 8000), 0);
            server.createContext("/", new MyHandler()); // root
            // start server
            server.setExecutor(null);
            server.start();

            System.out.println("Server is now running on port 8000: http://localhost:8000");
        } catch (IOException e) {
            System.out.println("Error starting the server: " + e.getMessage());
        }
    }

    // custom handler
    static class MyHandler implements HttpHandler {
        @Override 
        public void handle(HttpExchange exchange) throws IOException {
            String response = "Hello from MyHandler.\n";
            
            byte[] utf8Response = response.getBytes(StandardCharsets.UTF_8);

            exchange.sendResponseHeaders(200, utf8Response.length);
            try(OutputStream os = exchange.getResponseBody()) {
                os.write(utf8Response);
            }
        }
    }
}