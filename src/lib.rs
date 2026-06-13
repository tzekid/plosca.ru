pub mod config;
pub mod metrics;
pub mod routes;
pub mod server;
pub mod static_files;

#[global_allocator]
pub static GLOBAL_ALLOCATOR: &stats_alloc::StatsAlloc<std::alloc::System> =
    &stats_alloc::INSTRUMENTED_SYSTEM;
