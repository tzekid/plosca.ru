use std::mem::MaybeUninit;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use axum::http::StatusCode;

const LATENCY_BUCKETS: [f64; 11] = [
    0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
];

#[derive(Clone, Debug)]
pub struct AppMetrics {
    inner: Arc<MetricsInner>,
}

#[derive(Debug)]
struct MetricsInner {
    ready: AtomicBool,
    started_at: Instant,
    started_at_unix: u64,
    requests_in_flight: AtomicU64,
    requests_total: AtomicU64,
    responses_2xx: AtomicU64,
    responses_3xx: AtomicU64,
    responses_4xx: AtomicU64,
    responses_5xx: AtomicU64,
    responses_other: AtomicU64,
    latency_buckets: [AtomicU64; LATENCY_BUCKETS.len()],
    latency_count: AtomicU64,
    latency_sum_micros: AtomicU64,
}

impl AppMetrics {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(MetricsInner {
                ready: AtomicBool::new(true),
                started_at: Instant::now(),
                started_at_unix: SystemTime::now()
                    .duration_since(UNIX_EPOCH)
                    .unwrap_or_default()
                    .as_secs(),
                requests_in_flight: AtomicU64::new(0),
                requests_total: AtomicU64::new(0),
                responses_2xx: AtomicU64::new(0),
                responses_3xx: AtomicU64::new(0),
                responses_4xx: AtomicU64::new(0),
                responses_5xx: AtomicU64::new(0),
                responses_other: AtomicU64::new(0),
                latency_buckets: std::array::from_fn(|_| AtomicU64::new(0)),
                latency_count: AtomicU64::new(0),
                latency_sum_micros: AtomicU64::new(0),
            }),
        }
    }

    pub fn track_start(&self) {
        self.inner
            .requests_in_flight
            .fetch_add(1, Ordering::Relaxed);
    }

    pub fn track_finish(&self, status: StatusCode, elapsed: Duration) {
        self.inner
            .requests_in_flight
            .fetch_sub(1, Ordering::Relaxed);
        self.inner.requests_total.fetch_add(1, Ordering::Relaxed);
        self.inner.latency_count.fetch_add(1, Ordering::Relaxed);
        self.inner
            .latency_sum_micros
            .fetch_add(elapsed.as_micros() as u64, Ordering::Relaxed);

        let seconds = elapsed.as_secs_f64();
        for (index, bucket) in LATENCY_BUCKETS.iter().enumerate() {
            if seconds <= *bucket {
                self.inner.latency_buckets[index].fetch_add(1, Ordering::Relaxed);
                break;
            }
        }

        match status.as_u16() / 100 {
            2 => self.inner.responses_2xx.fetch_add(1, Ordering::Relaxed),
            3 => self.inner.responses_3xx.fetch_add(1, Ordering::Relaxed),
            4 => self.inner.responses_4xx.fetch_add(1, Ordering::Relaxed),
            5 => self.inner.responses_5xx.fetch_add(1, Ordering::Relaxed),
            _ => self.inner.responses_other.fetch_add(1, Ordering::Relaxed),
        };
    }

    pub fn render(&self) -> String {
        let (heap_used, heap_total) = heap_bytes();
        let rss = linux_rss_bytes()
            .or_else(process_memory_estimate_bytes)
            .unwrap_or(heap_total.max(heap_used));
        let uptime = self.inner.started_at.elapsed().as_secs_f64();
        let latency_sum =
            self.inner.latency_sum_micros.load(Ordering::Relaxed) as f64 / 1_000_000.0;

        let mut out = String::new();
        out.push_str("# HELP webapp_ready Whether the process is ready to serve traffic.\n");
        out.push_str("# TYPE webapp_ready gauge\n");
        out.push_str(&format!(
            "webapp_ready {}\n",
            if self.inner.ready.load(Ordering::Relaxed) {
                1
            } else {
                0
            }
        ));
        out.push_str("# HELP http_requests_in_flight Active requests currently being served.\n");
        out.push_str("# TYPE http_requests_in_flight gauge\n");
        out.push_str(&format!(
            "http_requests_in_flight {}\n",
            self.inner.requests_in_flight.load(Ordering::Relaxed)
        ));
        out.push_str("# HELP http_requests_total Total HTTP requests completed.\n");
        out.push_str("# TYPE http_requests_total counter\n");
        out.push_str(&format!(
            "http_requests_total {}\n",
            self.inner.requests_total.load(Ordering::Relaxed)
        ));
        out.push_str("# HELP http_responses_total Total HTTP responses by status class.\n");
        out.push_str("# TYPE http_responses_total counter\n");
        for (label, count) in [
            ("2xx", self.inner.responses_2xx.load(Ordering::Relaxed)),
            ("3xx", self.inner.responses_3xx.load(Ordering::Relaxed)),
            ("4xx", self.inner.responses_4xx.load(Ordering::Relaxed)),
            ("5xx", self.inner.responses_5xx.load(Ordering::Relaxed)),
            ("other", self.inner.responses_other.load(Ordering::Relaxed)),
        ] {
            out.push_str(&format!(
                "http_responses_total{{status_class=\"{label}\"}} {count}\n"
            ));
        }
        out.push_str("# HELP http_request_duration_seconds Request latency histogram.\n");
        out.push_str("# TYPE http_request_duration_seconds histogram\n");
        let mut cumulative = 0_u64;
        for (index, bucket) in LATENCY_BUCKETS.iter().enumerate() {
            cumulative += self.inner.latency_buckets[index].load(Ordering::Relaxed);
            out.push_str(&format!(
                "http_request_duration_seconds_bucket{{le=\"{bucket}\"}} {}\n",
                cumulative
            ));
        }
        out.push_str(&format!(
            "http_request_duration_seconds_bucket{{le=\"+Inf\"}} {}\n",
            self.inner.latency_count.load(Ordering::Relaxed)
        ));
        out.push_str(&format!(
            "http_request_duration_seconds_sum {:.6}\n",
            latency_sum
        ));
        out.push_str(&format!(
            "http_request_duration_seconds_count {}\n",
            self.inner.latency_count.load(Ordering::Relaxed)
        ));
        out.push_str("# HELP process_start_time_seconds Process start time since unix epoch.\n");
        out.push_str("# TYPE process_start_time_seconds gauge\n");
        out.push_str(&format!(
            "process_start_time_seconds {}\n",
            self.inner.started_at_unix
        ));
        out.push_str("# HELP process_uptime_seconds Process uptime in seconds.\n");
        out.push_str("# TYPE process_uptime_seconds gauge\n");
        out.push_str(&format!("process_uptime_seconds {:.3}\n", uptime));
        out.push_str("# HELP process_resident_memory_bytes Resident set size estimate.\n");
        out.push_str("# TYPE process_resident_memory_bytes gauge\n");
        out.push_str(&format!("process_resident_memory_bytes {rss}\n"));
        out.push_str("# HELP process_heap_used_bytes Heap bytes currently in use.\n");
        out.push_str("# TYPE process_heap_used_bytes gauge\n");
        out.push_str(&format!("process_heap_used_bytes {heap_used}\n"));
        out.push_str("# HELP process_heap_total_bytes Heap bytes ever allocated.\n");
        out.push_str("# TYPE process_heap_total_bytes gauge\n");
        out.push_str(&format!("process_heap_total_bytes {heap_total}\n"));
        out.push_str("# HELP webapp_build_info Static build information.\n");
        out.push_str("# TYPE webapp_build_info gauge\n");
        out.push_str(&format!(
            "webapp_build_info{{version=\"{}\"}} 1\n",
            env!("CARGO_PKG_VERSION")
        ));
        out
    }
}

impl Default for AppMetrics {
    fn default() -> Self {
        Self::new()
    }
}

fn heap_bytes() -> (u64, u64) {
    let stats = crate::GLOBAL_ALLOCATOR.stats();
    let allocated = stats.bytes_allocated as u64;
    let deallocated = stats.bytes_deallocated as u64;
    let in_use = allocated.saturating_sub(deallocated);
    (in_use, allocated.max(in_use))
}

#[cfg(target_os = "linux")]
fn linux_rss_bytes() -> Option<u64> {
    let content = std::fs::read_to_string("/proc/self/statm").ok()?;
    let mut fields = content.split_whitespace();
    let _size_pages = fields.next()?;
    let resident_pages = fields.next()?.parse::<u64>().ok()?;
    let page_size = unsafe { libc::sysconf(libc::_SC_PAGESIZE) };
    if page_size <= 0 {
        return None;
    }
    Some(resident_pages.saturating_mul(page_size as u64))
}

#[cfg(not(target_os = "linux"))]
fn linux_rss_bytes() -> Option<u64> {
    None
}

fn process_memory_estimate_bytes() -> Option<u64> {
    let mut usage = MaybeUninit::<libc::rusage>::uninit();
    let status = unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) };
    if status != 0 {
        return None;
    }

    let usage = unsafe { usage.assume_init() };

    #[cfg(target_os = "macos")]
    {
        Some(usage.ru_maxrss as u64)
    }

    #[cfg(not(target_os = "macos"))]
    {
        Some((usage.ru_maxrss as u64).saturating_mul(1024))
    }
}
