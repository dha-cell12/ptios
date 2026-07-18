use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
};

use axum::extract::ws::Message;
use base64::{engine::general_purpose, Engine as _};
use serde::{Deserialize, Serialize};
use tokio::sync::{mpsc, oneshot, Mutex, RwLock};

#[derive(Debug, Deserialize)]
pub struct RemoteControlHello {
    #[serde(rename = "type")]
    pub message_type: String,
    pub device_id: String,
    #[serde(default)]
    pub display_name: String,
    #[serde(default)]
    pub system_name: String,
    #[serde(default)]
    pub system_version: String,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub service_version: u64,
}

#[derive(Debug, Deserialize)]
pub struct RemoteControlInbound {
    #[serde(rename = "type")]
    pub message_type: String,
    #[serde(default)]
    pub request_id: u64,
    #[serde(default)]
    pub payload_b64: String,
}

#[derive(Serialize)]
struct RemoteTaskOutbound<'a> {
    #[serde(rename = "type")]
    message_type: &'static str,
    request_id: u64,
    payload_b64: String,
    expect_response: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    profile: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    stream_id: Option<&'a str>,
}

pub struct RemoteIosSession {
    pub device_id: String,
    outgoing: mpsc::Sender<Message>,
    pending: Mutex<HashMap<u64, oneshot::Sender<Vec<u8>>>>,
    next_request_id: AtomicU64,
}

impl RemoteIosSession {
    pub fn new(device_id: String, outgoing: mpsc::Sender<Message>) -> Arc<Self> {
        Arc::new(Self {
            device_id,
            outgoing,
            pending: Mutex::new(HashMap::new()),
            next_request_id: AtomicU64::new(1),
        })
    }

    async fn send_json<T: Serialize>(&self, value: &T) -> Result<(), ()> {
        let text = serde_json::to_string(value).map_err(|_| ())?;
        self.outgoing.send(Message::text(text)).await.map_err(|_| ())
    }

    pub async fn send_touch(&self, bytes: Vec<u8>) -> Result<(), ()> {
        self.send_json(&RemoteTaskOutbound {
            message_type: "task",
            request_id: 0,
            payload_b64: general_purpose::STANDARD.encode(bytes),
            expect_response: false,
            profile: None,
            stream_id: None,
        })
        .await
    }

    pub async fn send_request(&self, bytes: Vec<u8>) -> Result<Vec<u8>, ()> {
        let request_id = self.next_request_id.fetch_add(1, Ordering::Relaxed);
        let (response_tx, response_rx) = oneshot::channel();
        self.pending.lock().await.insert(request_id, response_tx);
        if self
            .send_json(&RemoteTaskOutbound {
                message_type: "task",
                request_id,
                payload_b64: general_purpose::STANDARD.encode(bytes),
                expect_response: true,
                profile: None,
                stream_id: None,
            })
            .await
            .is_err()
        {
            self.pending.lock().await.remove(&request_id);
            return Err(());
        }
        match tokio::time::timeout(std::time::Duration::from_secs(60), response_rx).await {
            Ok(Ok(response)) => Ok(response),
            _ => {
                self.pending.lock().await.remove(&request_id);
                Err(())
            }
        }
    }

    pub async fn resolve_response(&self, request_id: u64, payload_b64: &str) {
        let response = general_purpose::STANDARD
            .decode(payload_b64)
            .or_else(|_| general_purpose::STANDARD_NO_PAD.decode(payload_b64));
        if let (Some(tx), Ok(bytes)) = (self.pending.lock().await.remove(&request_id), response) {
            let _ = tx.send(bytes);
        }
    }

    pub async fn start_video(&self, stream_id: &str, profile: &str) -> Result<(), ()> {
        self.send_json(&RemoteTaskOutbound {
            message_type: "video_start",
            request_id: 0,
            payload_b64: String::new(),
            expect_response: false,
            profile: Some(profile),
            stream_id: Some(stream_id),
        })
        .await
    }

    pub async fn stop_video(&self, stream_id: &str) {
        let _ = self
            .send_json(&RemoteTaskOutbound {
                message_type: "video_stop",
                request_id: 0,
                payload_b64: String::new(),
                expect_response: false,
                profile: None,
                stream_id: Some(stream_id),
            })
            .await;
    }
}

struct RemoteVideoSlot {
    device_id: String,
    sender: mpsc::Sender<Vec<u8>>,
}

pub struct RemoteIosHub {
    token: Option<String>,
    sessions: RwLock<HashMap<String, Arc<RemoteIosSession>>>,
    video_slots: Mutex<HashMap<String, RemoteVideoSlot>>,
    next_stream_id: AtomicU64,
}

impl RemoteIosHub {
    pub fn from_env() -> Arc<Self> {
        Arc::new(Self {
            token: std::env::var("TLINK_REMOTE_TOKEN")
                .ok()
                .filter(|value| value.len() >= 16),
            sessions: RwLock::new(HashMap::new()),
            video_slots: Mutex::new(HashMap::new()),
            next_stream_id: AtomicU64::new(1),
        })
    }

    pub fn enabled(&self) -> bool {
        self.token.is_some()
    }

    pub fn authorize(&self, authorization: Option<&str>) -> bool {
        let Some(expected) = self.token.as_deref() else { return false; };
        let Some(actual) = authorization.and_then(|value| value.strip_prefix("Bearer ")) else {
            return false;
        };
        let actual = actual.as_bytes();
        let expected = expected.as_bytes();
        if actual.len() != expected.len() {
            return false;
        }
        actual
            .iter()
            .zip(expected.iter())
            .fold(0u8, |difference, (left, right)| difference | (left ^ right))
            == 0
    }

    pub async fn insert(&self, id: String, session: Arc<RemoteIosSession>) {
        self.sessions.write().await.insert(id, session);
    }

    pub async fn get(&self, id: &str) -> Option<Arc<RemoteIosSession>> {
        self.sessions.read().await.get(id).cloned()
    }

    pub async fn connected_count(&self) -> usize {
        self.sessions.read().await.len()
    }

    pub async fn remove_if_current(&self, id: &str, session: &Arc<RemoteIosSession>) -> bool {
        let mut sessions = self.sessions.write().await;
        let should_remove = sessions
            .get(id)
            .map(|current| Arc::ptr_eq(current, session))
            .unwrap_or(false);
        if should_remove {
            sessions.remove(id);
        }
        should_remove
    }

    pub async fn open_video(
        &self,
        session: &Arc<RemoteIosSession>,
        profile: &str,
    ) -> Result<(String, mpsc::Receiver<Vec<u8>>), ()> {
        let ordinal = self.next_stream_id.fetch_add(1, Ordering::Relaxed);
        let stream_id = format!("{}-{}", ordinal, std::process::id());
        let (sender, receiver) = mpsc::channel(12);
        self.video_slots.lock().await.insert(
            stream_id.clone(),
            RemoteVideoSlot {
                device_id: session.device_id.clone(),
                sender,
            },
        );
        if session.start_video(&stream_id, profile).await.is_err() {
            self.video_slots.lock().await.remove(&stream_id);
            return Err(());
        }
        Ok((stream_id, receiver))
    }

    pub async fn take_video_sender(
        &self,
        device_id: &str,
        stream_id: &str,
    ) -> Option<mpsc::Sender<Vec<u8>>> {
        let mut slots = self.video_slots.lock().await;
        let matches = slots
            .get(stream_id)
            .map(|slot| slot.device_id == device_id)
            .unwrap_or(false);
        if !matches {
            return None;
        }
        slots.remove(stream_id).map(|slot| slot.sender)
    }

    pub async fn cancel_video_slot(&self, stream_id: &str) {
        self.video_slots.lock().await.remove(stream_id);
    }
}
