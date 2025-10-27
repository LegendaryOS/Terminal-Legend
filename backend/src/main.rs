use std::io;
use std::process::Stdio;
use futures_util::{SinkExt, StreamExt};
use serde::{Deserialize, Serialize};
use tokio::net::TcpListener;
use tokio_tungstenite::accept_async;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Command;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::Message as WsMessage;

#[derive(Serialize, Deserialize)]
struct InputMessage {
    command: String,
}

#[tokio::main]
async fn main() -> io::Result<()> {
    let listener = TcpListener::bind("127.0.0.1:8080").await?;
    println!("Backend listening on ws://127.0.0.1:8080");

    while let Ok((stream, _)) = listener.accept().await {
        tokio::spawn(handle_connection(stream));
    }

    Ok(())
}

async fn handle_connection(stream: tokio::net::TcpStream) {
    let ws_stream = accept_async(stream).await.expect("Failed to accept");
    let (mut ws_tx, mut ws_rx) = ws_stream.split();

    let (tx, mut rx) = mpsc::channel::<WsMessage>(32);

    // Spawn a task to handle sending messages
    tokio::spawn(async move {
        while let Some(msg) = rx.recv().await {
            ws_tx.send(msg).await.unwrap();
        }
    });

    while let Some(msg) = ws_rx.next().await {
        let msg = msg.expect("Failed to read message");
        if msg.is_text() {
            let text = msg.into_text().expect("Not text");
            let message: InputMessage = serde_json::from_str(&text).expect("Invalid JSON");

            // Spawn Bash process
            let mut child = Command::new("bash")
            .arg("-c")
            .arg(&message.command)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .spawn()
            .expect("Failed to spawn bash");

            // Read stdout and stderr
            let stdout = child.stdout.take().unwrap();
            let stderr = child.stderr.take().unwrap();

            let tx_clone = tx.clone();
            let stdout_handle = tokio::spawn(async move {
                let reader = BufReader::new(stdout);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    tx_clone.send(WsMessage::Text(line)).await.unwrap();
                }
            });

            let tx_clone = tx.clone();
            let stderr_handle = tokio::spawn(async move {
                let reader = BufReader::new(stderr);
                let mut lines = reader.lines();
                while let Ok(Some(line)) = lines.next_line().await {
                    tx_clone.send(WsMessage::Text(format!("ERR: {}", line))).await.unwrap();
                }
            });

            stdout_handle.await.unwrap();
            stderr_handle.await.unwrap();

            // Send end signal
            tx.send(WsMessage::Text("---END---".to_string())).await.unwrap();
        }
    }
}
