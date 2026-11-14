package io.github.yawasau.speedbackup.webview;
import java.net.*;import java.io.*;import java.util.concurrent.atomic.*;
public class NativeApiCancellationTest {
 public static void main(String[]args)throws Exception {
  int empty=0,partial=0,complete=0,reset=0;
  for(int i=0;i<100;i++)try(ServerSocket server=new ServerSocket(0,8,InetAddress.getByName("127.0.0.1"))){
   NativeApi api=new NativeApi("http://127.0.0.1:"+server.getLocalPort()+"/#"+"0000000000000000000000000000000000000000000000000000000000000000");
   AtomicBoolean ended=new AtomicBoolean();
   Thread request=new Thread(()->{try{api.get("session");}catch(IOException expected){}finally{ended.set(true);}});request.start();
   server.setSoTimeout(5000);
   try(Socket socket=server.accept()){
    api.close();socket.setSoTimeout(3000);ByteArrayOutputStream bytes=new ByteArrayOutputStream();
    try{for(int n;(n=socket.getInputStream().read())!=-1;){bytes.write(n);if(bytes.toString("UTF-8").endsWith("\r\n\r\n"))break;}}
    catch(SocketException e){reset++;}
    String header=bytes.toString("UTF-8");if(header.isEmpty())empty++;else if(!header.endsWith("\r\n\r\n"))partial++;else complete++;
   }
   request.join(5000);if(!ended.get())throw new AssertionError("cancellation stuck");
  }
  System.out.println("cancellation attempts=100 empty="+empty+" partial="+partial+" complete="+complete+" reset="+reset);
 }
}
