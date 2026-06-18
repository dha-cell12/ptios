use std::{
    io,
    net::{Ipv4Addr, UdpSocket},
    sync::Arc,
    time::Duration,
};

use base64::{engine::general_purpose, Engine as _};
use tokio::{io::AsyncReadExt, io::AsyncWriteExt, net::TcpStream};
use tokio::sync::Semaphore;

use crate::ios_provider::{HelloStatusPayload, IosDevice};

#[derive(Clone)]
pub struct IosLanScanner {
    timeout: Duration,
    concurrency: usize,
}

impl IosLanScanner {
    pub fn new(timeout: Duration, concurrency: usize) -> Self {
        Self {
            timeout,
            concurrency,
        }
    }

    pub async fn scan_subnet(&self, subnet_base: Ipv4Addr) -> Vec<IosDevice> {
        let semaphore = Arc::new(Semaphore::new(self.concurrency));
        let mut tasks = Vec::new();

        for host in 2u8..=254u8 {
            let ip = Ipv4Addr::new(
                subnet_base.octets()[0],
                subnet_base.octets()[1],
                subnet_base.octets()[2],
                host,
            );
            let permit = semaphore.clone().acquire_owned().await.unwrap();
            let timeout = self.timeout;
            tasks.push(tokio::spawn(async move {
                let _permit = permit;
                probe_device(ip, timeout).await
            }));
        }

        let mut devices = Vec::new();
        for task in tasks {
            if let Ok(Some(device)) = task.await {
                devices.push(device);
            }
        }

        devices
    }
}

pub fn local_ipv4() -> io::Result<Ipv4Addr> {
    let socket = UdpSocket::bind("0.0.0.0:0")?;
    socket.connect("8.8.8.8:80")?;
    match socket.local_addr()? {
        std::net::SocketAddr::V4(addr) => Ok(*addr.ip()),
        std::net::SocketAddr::V6(_) => Err(io::Error::new(io::ErrorKind::Other, "no ipv4")),
    }
}

async fn probe_device(
    ip: Ipv4Addr,
    timeout: Duration,
) -> Option<IosDevice> {
    let payload = hello_status(ip, 6000, timeout).await?;

    let ip_string = ip.to_string();
    let display_name = if payload.device.name.is_empty() {
        ip_string.clone()
    } else {
        payload.device.name.clone()
    };

    Some(IosDevice {
        id: format!("ios:{}", ip_string),
        display_name,
        ip: ip_string,
        status: payload,
    })
}

async fn hello_status(ip: Ipv4Addr, port: u16, timeout: Duration) -> Option<HelloStatusPayload> {
    let addr = (ip, port);

    let mut stream = tokio::time::timeout(timeout, TcpStream::connect(addr))
        .await
        .ok()?
        .ok()?;

    // Match python: send b"60\r\n"
    tokio::time::timeout(timeout, stream.write_all(b"60\r\n"))
        .await
        .ok()?
        .ok()?;

    // Read until newline (max 64 KiB)
    let mut buf = Vec::with_capacity(4096);
    let mut chunk = [0u8; 4096];
    loop {
        if buf.len() > 64 * 1024 {
            return None;
        }

        let n = tokio::time::timeout(timeout, stream.read(&mut chunk))
            .await
            .ok()?
            .ok()?;
        if n == 0 {
            return None;
        }

        buf.extend_from_slice(&chunk[..n]);
        if buf.iter().any(|b| *b == b'\n') {
            break;
        }
    }

    let newline_pos = buf.iter().position(|b| *b == b'\n')?;
    let line = &buf[..=newline_pos];
    let text = String::from_utf8_lossy(line).trim().to_string();
    if !text.starts_with("0;;") {
        return None;
    }

    let b64 = text.splitn(2, ";;").nth(1)?;
    let decoded = general_purpose::STANDARD
        .decode(b64)
        .or_else(|_| general_purpose::STANDARD_NO_PAD.decode(b64))
        .ok()?;

    serde_json::from_slice::<HelloStatusPayload>(&decoded).ok()
}
