pub mod config;
pub mod error_response;
pub mod routes;
pub mod server;
pub mod static_files;
pub mod stats;

#[global_allocator]
pub static GLOBAL_ALLOCATOR: &stats_alloc::StatsAlloc<std::alloc::System> =
    &stats_alloc::INSTRUMENTED_SYSTEM;
