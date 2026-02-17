use std::mem::MaybeUninit;

use serde::Serialize;

#[derive(Debug, Serialize)]
pub struct StatsResponse {
    pub runtime: &'static str,
    pub memory: MemoryStats,
}

#[derive(Debug, Serialize)]
pub struct MemoryStats {
    pub rss: String,
    pub heap_used: String,
    pub heap_total: String,
}

pub fn collect() -> StatsResponse {
    let (heap_used, heap_total) = heap_bytes();
    let rss = linux_rss_bytes()
        .or_else(process_memory_estimate_bytes)
        .unwrap_or(heap_total.max(heap_used));

    StatsResponse {
        runtime: "rust/axum",
        memory: MemoryStats {
            rss: format_mb(rss),
            heap_used: format_mb(heap_used),
            heap_total: format_mb(heap_total.max(heap_used)),
        },
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

fn format_mb(bytes: u64) -> String {
    format!("{:.2} MB", bytes as f64 / (1024.0 * 1024.0))
}
